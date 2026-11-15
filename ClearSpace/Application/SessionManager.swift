import Foundation
import Observation

private let sessionsFileName = "sessions.v1.bin"

/// Gestisce le sessioni di pulizia: avvio, decisioni, annullamento e ripresa.
/// Ogni decisione viene salvata subito, quindi una sessione può continuare in qualsiasi momento,
/// anche dopo la chiusura dell'app. Le decisioni non eliminano nulla: passano dal `SafetyEngine`
/// e modificano soltanto lo stato di revisione degli elementi.
@MainActor
@Observable
final class SessionManager {

    private(set) var sessions: [CleanupSession] = []
    private(set) var activeSessionID: UUID?
    /// Controlla la presentazione a tutto schermo della modalità swipe.
    var isPresentingSwipe = false

    @ObservationIgnored private var saveRunning = false
    @ObservationIgnored private var saveDirty = false

    private let store: IndexStore
    private let safety: SafetyEngine
    private let history: HistoryStore
    private let preferences: PreferencesStore
    private let files: SecureFileStore

    init(
        store: IndexStore,
        safety: SafetyEngine,
        history: HistoryStore,
        preferences: PreferencesStore,
        files: SecureFileStore = SecureFileStore()
    ) {
        self.store = store
        self.safety = safety
        self.history = history
        self.preferences = preferences
        self.files = files
    }

    // MARK: - Stato

    private var activeIndex: Int? {
        guard let activeSessionID else { return nil }
        return sessions.firstIndex { $0.id == activeSessionID }
    }

    var active: CleanupSession? {
        guard let index = activeIndex else { return nil }
        return sessions[index]
    }

    /// Sessioni interrotte che si possono riprendere, dalla più recente.
    var resumableSessions: [CleanupSession] {
        sessions
            .filter { !$0.isCompleted && !$0.isFinished }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var currentItem: IndexedItem? {
        item(atOffset: 0)
    }

    /// Elemento a una certa distanza da quello corrente (1 = il prossimo).
    func item(atOffset offset: Int) -> IndexedItem? {
        guard let id = active?.itemID(atOffset: offset) else { return nil }
        return store.item(id)
    }

    // MARK: - Avvio e chiusura

    /// Avvia una nuova sessione. Restituisce `false` se non c'è nulla da rivedere.
    @discardableResult
    func start(title: String, mode: CleanupMode, queue: [UUID], goalBytes: Int64? = nil) -> Bool {
        let available = queue.filter { store.item($0) != nil }
        guard !available.isEmpty else { return false }
        let session = CleanupSession(title: title, mode: mode, queue: available, goalBytes: goalBytes)
        sessions.insert(session, at: 0)
        trimSessions()
        activeSessionID = session.id
        isPresentingSwipe = true
        scheduleSave()
        return true
    }

    func resume(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessionID = id
        skipMissingItems(at: index)
        isPresentingSwipe = true
    }

    /// Chiude la schermata lasciando la sessione salvata per riprenderla più tardi.
    func closePresentation() {
        if let index = activeIndex, sessions[index].isFinished, sessions[index].postponedCount == 0 {
            sessions[index].isCompleted = true
        }
        isPresentingSwipe = false
        scheduleSave()
    }

    /// Segna la sessione come conclusa (gli eventuali rimandati restano "da rivedere").
    func completeActive() {
        guard let index = activeIndex else { return }
        sessions[index].isCompleted = true
        isPresentingSwipe = false
        scheduleSave()
    }

    /// Rimuove una sessione salvata. Le decisioni già prese sugli elementi restano valide.
    func discard(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = nil
            isPresentingSwipe = false
        }
        scheduleSave()
    }

    private func trimSessions() {
        guard sessions.count > 20 else { return }
        sessions = Array(sessions.prefix(20))
    }

    private func skipMissingItems(at index: Int) {
        while let id = sessions[index].currentItemID, store.item(id) == nil {
            sessions[index].skipCurrent()
        }
    }

    /// Salta gli elementi della sessione attiva che nel frattempo non sono più disponibili
    /// (ad esempio rimossi dalla libreria mentre la sessione era aperta).
    func skipUnavailableItems() {
        guard let index = activeIndex else { return }
        let previousCursor = sessions[index].cursor
        skipMissingItems(at: index)
        if sessions[index].cursor != previousCursor {
            scheduleSave()
        }
    }

    // MARK: - Decisioni

    /// Registra la scelta sull'elemento corrente e passa al successivo.
    /// Restituisce l'esito: se l'elemento è protetto la scelta "elimina" viene rifiutata e nulla cambia.
    @discardableResult
    func decide(_ choice: SwipeChoice) -> MarkResult? {
        guard let index = activeIndex,
              let itemID = sessions[index].currentItemID,
              let item = store.item(itemID) else {
            return nil
        }
        let evaluation = SafetyRules.evaluate(choice, on: item, evaluator: safety.evaluator())
        guard let status = evaluation.status else {
            return evaluation.result
        }

        store.setReviewStatus(status, for: [itemID])
        sessions[index].record(choice, previousStatus: item.reviewStatus, bytes: item.bytes)
        history.recordDecision(choice, bucket: bucket(for: item))
        skipMissingItems(at: index)
        scheduleSave()
        return evaluation.result
    }

    /// Annulla l'ultima scelta, ripristinando lo stato precedente dell'elemento.
    @discardableResult
    func undo() -> Bool {
        guard let index = activeIndex, let decision = sessions[index].undoLast() else { return false }
        if let item = store.item(decision.itemID) {
            store.setReviewStatus(decision.previousStatus, for: [decision.itemID])
            history.revertDecision(decision.choice, bucket: bucket(for: item))
        }
        scheduleSave()
        return true
    }

    var canUndo: Bool {
        !(active?.decisions.isEmpty ?? true)
    }

    /// Rimette in coda gli elementi rimandati per rivederli subito.
    func reviewPostponed() {
        guard let index = activeIndex else { return }
        sessions[index].requeuePostponed()
        skipMissingItems(at: index)
        scheduleSave()
    }

    private func bucket(for item: IndexedItem) -> LearningBucket {
        LearningBucket.bucket(for: item, largeVideoBytes: preferences.values.largeVideoBytes)
    }

    // MARK: - Persistenza

    func load() async {
        let files = self.files
        let loaded = await Task.detached(priority: .userInitiated) {
            files.load([CleanupSession].self, from: sessionsFileName)
        }.value
        if let loaded {
            sessions = loaded
        }
    }

    private func scheduleSave() {
        if saveRunning {
            saveDirty = true
            return
        }
        saveRunning = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.runSaveLoop()
        }
    }

    private func runSaveLoop() async {
        repeat {
            saveDirty = false
            await write()
        } while saveDirty
        saveRunning = false
    }

    private func write() async {
        let snapshot = sessions
        let files = self.files
        await Task.detached(priority: .userInitiated) {
            try? files.save(snapshot, as: sessionsFileName)
        }.value
    }

    func flush() async {
        await write()
    }
}
