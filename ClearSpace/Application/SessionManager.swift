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

    /// Prossimi elementi ancora da decidere dopo quello corrente: quelli già decisi altrove
    /// (ad esempio con una scelta su un intero gruppo) non verranno più proposti.
    func upcomingItems(limit: Int) -> [IndexedItem] {
        guard let session = active, limit > 0 else { return [] }
        var result: [IndexedItem] = []
        var offset = 1
        while result.count < limit, offset < 200, let id = session.itemID(atOffset: offset) {
            if let item = store.item(id), item.isPendingReview {
                result.append(item)
            }
            offset += 1
        }
        return result
    }

    // MARK: - Avvio e chiusura

    /// Avvia una nuova sessione. Restituisce `false` se non c'è nulla da rivedere.
    @discardableResult
    func start(title: String, mode: CleanupMode, queue: [UUID], goalBytes: Int64? = nil) -> Bool {
        let available = queue.filter { store.item($0) != nil }
        guard !available.isEmpty else { return false }
        // Gli scatti simili vengono proposti uno dopo l'altro, a partire da quello consigliato.
        let ordered = CleanupPlanner.clusteredByGroup(available) { [store] id in
            guard let item = store.item(id) else { return nil }
            return store.presentationGroup(for: item)
        }
        let session = CleanupSession(title: title, mode: mode, queue: ordered, goalBytes: goalBytes)
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
        skipSettledItems(at: index)
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

    /// Avanza oltre gli elementi su cui non c'è più nulla da decidere: quelli non più disponibili
    /// e quelli già decisi altrove, ad esempio con una scelta su un intero gruppo di foto simili.
    private func skipSettledItems(at index: Int) {
        while let id = sessions[index].currentItemID {
            if let item = store.item(id) {
                if item.isPendingReview { break }
                // Un elemento portato in primo piano dall'utente resta sulla carta anche se è già
                // stato deciso: lo sta riguardando, magari per cambiare idea.
                if sessions[index].focusedItemID == id { break }
            }
            sessions[index].skipCurrent()
        }
    }

    /// Porta sulla carta un elemento scelto dall'utente, ad esempio uno degli scatti o dei video
    /// simili mostrati sotto: lo si può guardare e decidere come qualsiasi altro, anche se era già
    /// stato deciso o non faceva parte della coda.
    func focus(on itemID: UUID) {
        guard let index = activeIndex, store.item(itemID) != nil else { return }
        sessions[index].bringToFront(itemID)
        scheduleSave()
    }

    /// Salta gli elementi della sessione attiva che nel frattempo non sono più disponibili
    /// (ad esempio rimossi dalla libreria mentre la sessione era aperta) o già decisi.
    func skipUnavailableItems() {
        guard let index = activeIndex else { return }
        let previousCursor = sessions[index].cursor
        skipSettledItems(at: index)
        if sessions[index].cursor != previousCursor {
            scheduleSave()
        }
    }

    // MARK: - Decisioni

    /// Registra la scelta sull'elemento corrente e passa al successivo.
    /// Restituisce l'esito: se l'elemento è protetto la scelta "elimina" viene rifiutata e nulla cambia.
    /// - Parameter expectedItemID: l'elemento su cui l'utente ha fatto il gesto. Se nel frattempo la carta
    ///   è cambiata (ad esempio l'elemento è sparito durante l'animazione), la scelta non viene applicata a
    ///   un altro elemento.
    @discardableResult
    func decide(_ choice: SwipeChoice, expectedItemID: UUID? = nil) -> MarkResult? {
        guard let index = activeIndex,
              let itemID = sessions[index].currentItemID,
              expectedItemID == nil || expectedItemID == itemID,
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
        skipSettledItems(at: index)
        scheduleSave()
        return evaluation.result
    }

    /// Applica in blocco una scelta su più elementi, tipicamente un gruppo di foto simili:
    /// conserva `keepIDs` e propone `deleteIDs` per l'eliminazione. Gli elementi protetti vengono saltati.
    /// Come ogni altra scelta, cambia soltanto lo stato di revisione: nulla viene eliminato.
    /// Se c'è una sessione attiva la mossa vi viene registrata e si annulla con un solo gesto.
    @discardableResult
    func decideGroup(keep keepIDs: [UUID], delete deleteIDs: [UUID]) -> (applied: Int, blocked: Int) {
        let evaluator = safety.evaluator()
        var choices: [BatchChoice] = []
        var kept: [UUID] = []
        var marked: [UUID] = []
        var blocked = 0

        for id in keepIDs {
            guard let item = store.item(id) else { continue }
            kept.append(id)
            choices.append(BatchChoice(itemID: id, choice: .keep, previousStatus: item.reviewStatus, bytes: item.bytes))
        }
        for id in deleteIDs where !keepIDs.contains(id) {
            guard let item = store.item(id) else { continue }
            let evaluation = SafetyRules.evaluate(.delete, on: item, evaluator: evaluator)
            guard evaluation.status != nil else {
                blocked += 1
                continue
            }
            marked.append(id)
            choices.append(BatchChoice(itemID: id, choice: .delete, previousStatus: item.reviewStatus, bytes: item.bytes))
        }
        guard !choices.isEmpty else { return (0, blocked) }

        for entry in choices {
            if let item = store.item(entry.itemID) {
                history.recordDecision(entry.choice, bucket: bucket(for: item))
            }
        }
        store.setReviewStatus(.kept, for: kept)
        store.setReviewStatus(.markedForDeletion, for: marked)

        // La mossa entra nel registro della sessione solo se la modalità swipe è aperta:
        // una scelta fatta da un elenco non deve finire in una sessione messa da parte.
        if isPresentingSwipe, let index = activeIndex {
            sessions[index].recordBatch(choices)
            skipSettledItems(at: index)
            scheduleSave()
        }
        return (marked.count, blocked)
    }

    /// Segna gli elementi come «migliori»: vengono conservati e mostrati con una stella. La scelta di
    /// conservarli entra nella sessione come le altre, quindi si annulla con lo stesso gesto (e con
    /// lei sparisce la stella). Restituisce quanti elementi hanno ora la stella.
    @discardableResult
    func markBest(_ ids: [UUID]) -> Int {
        let present = ids.filter { store.item($0) != nil }
        guard !present.isEmpty else { return 0 }
        decideGroup(keep: present, delete: [])
        store.setStarred(true, for: present)
        return present.count
    }

    /// Toglie la stella. Gli elementi restano conservati.
    func removeBest(_ ids: [UUID]) {
        store.setStarred(false, for: ids)
    }

    /// Annulla l'ultima mossa (una scelta singola o una scelta di gruppo), ripristinando lo stato
    /// precedente degli elementi. Restituisce quante decisioni sono state annullate.
    @discardableResult
    func undo() -> Int {
        guard let index = activeIndex else { return 0 }
        let undone = sessions[index].undoLastMove()
        guard !undone.isEmpty else { return 0 }
        for decision in undone {
            guard let item = store.item(decision.itemID) else { continue }
            store.setReviewStatus(decision.previousStatus, for: [decision.itemID])
            history.revertDecision(decision.choice, bucket: bucket(for: item))
        }
        scheduleSave()
        return undone.count
    }

    var canUndo: Bool {
        !(active?.decisions.isEmpty ?? true)
    }

    /// Rimette in coda gli elementi rimandati per rivederli subito.
    func reviewPostponed() {
        guard let index = activeIndex else { return }
        sessions[index].requeuePostponed()
        skipSettledItems(at: index)
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
