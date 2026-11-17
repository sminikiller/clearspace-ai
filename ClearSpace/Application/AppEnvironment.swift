import Foundation
import Observation
import UIKit

/// Schede principali dell'app.
enum AppTab: Hashable, Sendable {
    case home
    case analyze
    case explore
    case review
    case results
}

/// Navigazione tra le schede, comandabile da qualsiasi schermata.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
}

/// Contenitore dei servizi dell'app: li crea una sola volta e li collega tra loro.
///
/// Strati, dall'alto verso il basso:
/// - presentazione (SwiftUI) → legge questo ambiente;
/// - servizi applicativi → `SessionManager`, `ScanCoordinator`, `CleanupPlanner`;
/// - servizi di piattaforma → Foto, file, analisi, sicurezza;
/// - dati locali → indice, decisioni, preferenze, risultati.
@MainActor
@Observable
final class AppEnvironment {

    let router: AppRouter
    let preferences: PreferencesStore
    let store: IndexStore
    let history: HistoryStore
    let conditions: SystemConditionsMonitor
    let photos: PhotoLibraryService
    let folders: FolderAccessService
    let thumbnails: ThumbnailProvider
    let fileOperations: FileOperationService
    let compression: VideoCompressionService
    let safety: SafetyEngine
    let sessions: SessionManager
    let scan: ScanCoordinator
    let plan: PlanManager
    let reminders: ReminderScheduler
    let background: BackgroundAnalysisScheduler

    /// Diventa `true` quando indice, sessioni e preferenze sono stati caricati dal disco.
    private(set) var isReady = false
    /// Messaggio da mostrare dopo un'importazione ("Apri in ClearSpace").
    var importMessage: String?

    init() {
        let files = SecureFileStore()
        let router = AppRouter()
        let preferences = PreferencesStore()
        let store = IndexStore(files: files)
        let history = HistoryStore(files: files)
        let conditions = SystemConditionsMonitor()
        let photos = PhotoLibraryService()
        let folders = FolderAccessService(files: files)
        let thumbnails = ThumbnailProvider(folders: folders)
        let fileOperations = FileOperationService()
        let plan = PlanManager()
        let safety = SafetyEngine(
            store: store,
            preferences: preferences,
            photos: photos,
            folders: folders,
            fileOperations: fileOperations,
            history: history,
            thumbnails: thumbnails
        )
        let sessions = SessionManager(
            store: store,
            safety: safety,
            history: history,
            preferences: preferences,
            files: files
        )
        let scan = ScanCoordinator(
            store: store,
            preferences: preferences,
            photos: photos,
            folders: folders,
            conditions: conditions,
            safety: safety,
            plan: plan
        )
        let background = BackgroundAnalysisScheduler()

        self.router = router
        self.preferences = preferences
        self.store = store
        self.history = history
        self.conditions = conditions
        self.photos = photos
        self.folders = folders
        self.thumbnails = thumbnails
        self.fileOperations = fileOperations
        self.compression = VideoCompressionService()
        self.safety = safety
        self.sessions = sessions
        self.scan = scan
        self.plan = plan
        self.reminders = ReminderScheduler()
        self.background = background

        store.evaluatorProvider = { [weak safety] in
            safety?.evaluator() ?? ProtectionEvaluator()
        }
        store.contextProvider = { [weak preferences] in
            CollectionContext(
                now: Date(),
                largeVideoBytes: preferences?.values.largeVideoBytes ?? 100 * AppConfiguration.Thresholds.megabyte
            )
        }
        plan.developerTierProvider = { [weak preferences] in
            preferences?.values.developerTier
        }
        background.onRun = { [weak scan] in
            await scan?.runInBackground() ?? false
        }
        background.onExpiration = { [weak scan] in
            scan?.pause()
        }
    }

    /// Carica i dati salvati e avvia i monitor di sistema.
    func bootstrap() async {
        guard !isReady else { return }
        conditions.start()
        plan.start()
        await folders.load()
        await history.load()
        await store.load()
        await sessions.load()
        await safety.refreshProtectedAlbums()
        await store.refreshSummaryNow()
        isReady = true
    }

    // MARK: - Pianificazione delle sessioni

    /// Fotografia dell'indice e delle regole correnti, da usare per costruire una coda di revisione.
    func plannerInput() -> PlannerInput {
        let groups = store.groupsSnapshot()
        let largeVideoBytes = preferences.values.largeVideoBytes
        let now = Date()
        return PlannerInput(
            items: store.snapshot(),
            groups: groups,
            evaluator: safety.evaluator(),
            scorer: RecoverabilityScorer(
                now: now,
                largeVideoBytes: largeVideoBytes,
                learner: history.learner,
                groups: groups
            ),
            context: CollectionContext(now: now, largeVideoBytes: largeVideoBytes)
        )
    }

    /// Costruisce la coda fuori dal thread principale e avvia la sessione di swipe.
    /// Restituisce `false` se non c'è nulla da rivedere.
    @discardableResult
    func startSession(
        title: String,
        mode: CleanupMode,
        goalBytes: Int64? = nil,
        queue: @escaping @Sendable (PlannerInput) -> [UUID]
    ) async -> Bool {
        let input = plannerInput()
        let ids = await Task.detached(priority: .userInitiated) {
            queue(input)
        }.value
        return sessions.start(title: title, mode: mode, queue: ids, goalBytes: goalBytes)
    }

    /// Avvia una sessione su un elenco di elementi già scelto (es. una selezione o un gruppo).
    @discardableResult
    func startSession(title: String, mode: CleanupMode, itemIDs: [UUID]) -> Bool {
        let protection = safety.evaluator()
        let reviewable = store.items(itemIDs).filter { protection.isReviewable($0) }.map { $0.id }
        return sessions.start(title: title, mode: mode, queue: reviewable)
    }

    /// Versione dell'indice osservata dagli elenchi. Resta ferma mentre è aperta la modalità swipe,
    /// così le schermate sottostanti non si ricaricano a ogni scelta; si aggiornano alla chiusura.
    var listRevision: Int {
        sessions.isPresentingSwipe ? -1 : store.revision
    }

    // MARK: - Rete

    /// Indica se è consentito scaricare un originale da iCloud per mostrarlo all'utente.
    var canDownloadForViewing: Bool {
        conditions.canDownload(wifiOnly: preferences.values.wifiOnlyDownloads)
    }

    /// Indica se si può scaricare la versione nitida della sola foto che l'utente sta esaminando
    /// (confronto, tutto schermo), anche con la rete cellulare: una foto alla volta, mai con
    /// la modalità Dati ridotti attiva.
    var canDownloadForInspection: Bool {
        if canDownloadForViewing { return true }
        return preferences.values.sharpPreviewsOnCellular
            && conditions.isOnline
            && !conditions.isLowDataMode
    }

    // MARK: - Scatto migliore

    /// Calcola subito, per un gruppo, le misure che mancano e aggiorna il candidato suggerito.
    /// Serve quando si apre un confronto prima che la scansione abbia esaminato quel gruppo.
    func refineSuggestion(forGroup groupID: UUID) async {
        guard let group = store.group(groupID), ScanCoordinator.rankedKinds.contains(group.kind) else { return }
        let missing = store.members(of: group).filter {
            $0.shot == nil && $0.category == .photo && $0.source == .photoLibrary
        }
        guard !missing.isEmpty else { return }
        let allowNetwork = canDownloadForViewing
        let updates = await Task.detached(priority: .userInitiated) { () -> [AnalysisUpdate] in
            var result: [AnalysisUpdate] = []
            for item in missing {
                guard let metrics = PhotoAnalysisPipeline.shotMetrics(for: item, allowNetwork: allowNetwork) else {
                    continue
                }
                var update = AnalysisUpdate(id: item.id)
                update.shot = metrics
                result.append(update)
            }
            return result
        }.value
        guard !updates.isEmpty else { return }
        store.apply(updates)
        store.refreshSuggestions(kinds: ScanCoordinator.rankedKinds, groupIDs: [groupID]) { members in
            QualityRanker.suggestion(among: members)
        }
    }

    /// Gruppo di simili o duplicati da mostrare per un elemento. Se appartiene a entrambi viene scelto
    /// quello che li comprende tutti, così non si decide due volte sulle stesse foto.
    func group(containing item: IndexedItem) -> ItemGroup? {
        store.presentationGroup(for: item)
    }

    // MARK: - Regole e cartelle

    /// Va chiamato dopo una modifica delle regole di protezione.
    func protectionRulesDidChange() async {
        await safety.refreshProtectedAlbums()
        await store.refreshSummaryNow()
    }

    /// Revoca l'accesso a una cartella e toglie i suoi elementi dall'indice. I file non vengono toccati.
    func removeFolder(_ id: UUID) {
        store.removeMissing(inFolder: id, keeping: [])
        folders.removeFolder(id)
        preferences.update { $0.protection.protectedFolderIDs.remove(id) }
    }

    // MARK: - Ciclo di vita

    func didBecomeActive() {
        photos.refreshAuthorization()
        guard isReady, !scan.isRunning else { return }
        // Scansione leggera quando la libreria è cambiata o non è mai stata analizzata, e una volta
        // dopo un aggiornamento che cambia i criteri di scelta dello scatto migliore: i gruppi già
        // trovati ricevono così i nuovi suggerimenti senza che l'utente debba rilanciare l'analisi.
        let rankingIsOutdated = !store.isEmpty
            && preferences.values.shotRankingVersion != AppConfiguration.shotRankingVersion
        if photos.canRead && (scan.needsRescan || store.isEmpty || rankingIsOutdated) {
            scan.start(deep: false)
        }
    }

    func didEnterBackground() {
        let application = UIApplication.shared
        let identifier = application.beginBackgroundTask(withName: "ClearSpace.save")
        if scan.isRunning || store.summary.analysisProgress < 1 {
            background.schedule()
        }
        Task {
            await store.flush()
            await history.flush()
            await sessions.flush()
            application.endBackgroundTask(identifier)
        }
    }

    /// Gestisce un file ricevuto con "Apri in ClearSpace" (ad esempio un memo vocale condiviso).
    func handleIncomingFile(_ url: URL) {
        do {
            let destination = try folders.importFile(from: url)
            importMessage = "«\(destination.lastPathComponent)» è stato importato. L'originale nell'app di origine non è stato modificato."
            if !scan.isRunning {
                scan.start(deep: true)
            }
        } catch let error as FolderAccessError {
            importMessage = error.message
        } catch {
            importMessage = "Importazione non riuscita."
        }
    }
}
