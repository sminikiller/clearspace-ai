import Foundation
import Observation
import UIKit

/// Fasi della scansione progressiva. La fase E (esecuzione) non è qui: appartiene al `SafetyEngine`
/// e parte soltanto dopo la conferma dell'utente.
enum ScanPhase: Int, CaseIterable, Identifiable, Sendable {
    case metadata
    case previews
    case deep
    case recommendations

    var id: Int { rawValue }

    var letter: String {
        switch self {
        case .metadata: return "A"
        case .previews: return "B"
        case .deep: return "C"
        case .recommendations: return "D"
        }
    }

    var title: String {
        switch self {
        case .metadata: return "Metadati"
        case .previews: return "Anteprime"
        case .deep: return "Analisi approfondita"
        case .recommendations: return "Raccomandazioni"
        }
    }

    var detail: String {
        switch self {
        case .metadata: return "Date, tipi e dimensioni: nessun contenuto viene scaricato"
        case .previews: return "Qualità, testo e somiglianze dalle miniature"
        case .deep: return "Verifica dei duplicati sul contenuto originale"
        case .recommendations: return "Priorità di revisione e spazio potenziale"
        }
    }
}

struct PhaseProgress: Equatable, Sendable {
    var completed = 0
    var total = 0

    var fraction: Double {
        total > 0 ? min(1, Double(completed) / Double(total)) : 0
    }
}

enum ScanState: Equatable, Sendable {
    case idle
    case running(ScanPhase)
    case paused(PauseReason)
    case completed
    case cancelled
}

/// Coordina la scansione: metadati, anteprime, analisi approfondita e raccomandazioni.
/// È incrementale (riesamina solo ciò che è nuovo o cambiato), si può mettere in pausa e
/// si sospende da sola quando il dispositivo è caldo o la batteria è scarica.
/// Produce soltanto analisi e suggerimenti: non seleziona e non elimina mai nulla.
@MainActor
@Observable
final class ScanCoordinator {

    private(set) var state: ScanState = .idle
    private(set) var currentPhase: ScanPhase?
    private(set) var progress: [ScanPhase: PhaseProgress] = [:]
    /// Descrizione dell'attività in corso, es. "Ricerca di foto simili".
    private(set) var activity = ""
    /// La libreria è cambiata dall'ultima scansione.
    private(set) var needsRescan = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isCancelled = false
    @ObservationIgnored private var pausedByUser = false

    private let store: IndexStore
    private let preferences: PreferencesStore
    private let photos: PhotoLibraryService
    private let folders: FolderAccessService
    private let conditions: SystemConditionsMonitor
    private let safety: SafetyEngine
    private let plan: PlanManager

    private let photoIndexer = PhotoIndexer()
    private let photoPipeline = PhotoAnalysisPipeline()
    private let fileIndexer = FileIndexer()
    private let filePipeline = FileAnalysisPipeline()

    init(
        store: IndexStore,
        preferences: PreferencesStore,
        photos: PhotoLibraryService,
        folders: FolderAccessService,
        conditions: SystemConditionsMonitor,
        safety: SafetyEngine,
        plan: PlanManager
    ) {
        self.store = store
        self.preferences = preferences
        self.photos = photos
        self.folders = folders
        self.conditions = conditions
        self.safety = safety
        self.plan = plan
    }

    // MARK: - Controlli

    var isRunning: Bool {
        switch state {
        case .running, .paused: return true
        case .idle, .completed, .cancelled: return false
        }
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var pauseReason: PauseReason? {
        if case .paused(let reason) = state { return reason }
        return nil
    }

    func phaseProgress(_ phase: ScanPhase) -> PhaseProgress {
        progress[phase] ?? PhaseProgress()
    }

    /// Avvia una scansione. Con `deep` vengono verificati anche i duplicati sul contenuto originale.
    func start(deep: Bool = true) {
        guard !isRunning else { return }
        task = Task { [weak self] in
            await self?.run(deep: deep)
        }
    }

    func pause() {
        guard isRunning else { return }
        pausedByUser = true
        state = .paused(.user)
    }

    func resume() {
        pausedByUser = false
    }

    func cancel() {
        isCancelled = true
        pausedByUser = false
        task?.cancel()
    }

    func noteLibraryChanged() {
        needsRescan = true
    }

    /// Esegue una scansione completa e attende la fine: usato dalle attività in background.
    func runInBackground() async -> Bool {
        guard !isRunning else { return false }
        await run(deep: true)
        return state == .completed
    }

    // MARK: - Esecuzione

    private func run(deep: Bool) async {
        isCancelled = false
        pausedByUser = false
        progress = [:]
        // Con il dispositivo bloccato foto e file non sono leggibili: un'analisi in quel momento
        // vedrebbe una libreria vuota. Meglio rimandarla.
        guard UIApplication.shared.isProtectedDataAvailable else {
            return finish(cancelled: true)
        }
        await safety.refreshProtectedAlbums()

        // Fase A — Metadati
        enter(.metadata)
        guard await indexPhotoLibrary() else { return finish(cancelled: true) }
        if plan.isUnlocked(.documents) || plan.isUnlocked(.audioTools) {
            guard await indexFolders() else { return finish(cancelled: true) }
            await indexImports()
        }
        store.pruneGroups()
        detectICloudPhotos()

        // Fase B — Anteprime
        enter(.previews)
        if photos.canRead {
            activity = "Analisi delle anteprime"
            guard await analyzePhotoPreviews() else { return finish(cancelled: true) }
            if plan.isUnlocked(.similarPhotos) {
                activity = "Ricerca di foto simili"
                guard await groupSimilarPhotos() else { return finish(cancelled: true) }
            }
            if plan.isUnlocked(.exactDuplicates) {
                activity = "Ricerca di probabili duplicati"
                guard await groupVisualDuplicates() else { return finish(cancelled: true) }
            }
            if plan.isUnlocked(.similarPhotos) {
                activity = "Scelta dello scatto migliore"
                guard await rankSimilarShots() else { return finish(cancelled: true) }
            }
            // I gruppi esistenti sono allineati ai criteri correnti: non serve più la scansione
            // automatica prevista dopo un aggiornamento dell'app.
            if preferences.values.shotRankingVersion != AppConfiguration.shotRankingVersion {
                preferences.update { $0.shotRankingVersion = AppConfiguration.shotRankingVersion }
            }
        }
        setProgress(.previews, 1, 1)

        // Fase C — Analisi approfondita, solo sui gruppi candidati
        if deep {
            enter(.deep)
            if photos.canRead && plan.isUnlocked(.exactDuplicates) {
                activity = "Verifica dei duplicati esatti"
                guard await verifyLibraryDuplicates() else { return finish(cancelled: true) }
            }
            if photos.canRead && plan.isUnlocked(.similarPhotos) {
                activity = "Confronto dei video"
                guard await groupSimilarVideos() else { return finish(cancelled: true) }
            }
            if plan.isUnlocked(.documents) {
                guard await analyzeFiles() else { return finish(cancelled: true) }
            }
            if plan.isUnlocked(.audioTools) {
                activity = "Analisi delle registrazioni"
                guard await analyzeAudioFiles() else { return finish(cancelled: true) }
            }
            setProgress(.deep, 1, 1)
        }

        // Fase D — Raccomandazioni
        enter(.recommendations)
        activity = "Calcolo delle priorità di revisione"
        store.pruneGroups()
        await store.refreshSummaryNow()
        setProgress(.recommendations, 1, 1)
        preferences.update { $0.lastScanCompletedAt = Date() }
        finish(cancelled: false)
    }

    private func enter(_ phase: ScanPhase) {
        currentPhase = phase
        state = .running(phase)
        progress[phase] = PhaseProgress()
    }

    private func setProgress(_ phase: ScanPhase, _ completed: Int, _ total: Int) {
        progress[phase] = PhaseProgress(completed: completed, total: total)
    }

    private func finish(cancelled: Bool) {
        state = cancelled ? .cancelled : .completed
        currentPhase = nil
        activity = ""
        task = nil
        if !cancelled {
            needsRescan = false
        }
    }

    /// Punto di controllo chiamato dalle analisi: attende durante le pause e segnala l'annullamento.
    private func checkpoint() async -> Bool {
        while true {
            if isCancelled || Task.isCancelled { return false }
            let reason: PauseReason? = pausedByUser
                ? .user
                : conditions.heavyWorkPauseReason(pauseOnLowBattery: preferences.values.pauseOnLowBattery)
            guard let reason else {
                if isPaused, let phase = currentPhase {
                    state = .running(phase)
                }
                return true
            }
            if state != .paused(reason) {
                state = .paused(reason)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Il download da iCloud richiede il consenso dell'utente e rispetta la modalità solo Wi‑Fi.
    private func isNetworkAllowed() -> Bool {
        let values = preferences.values
        return values.allowCloudDownloadsForAnalysis && conditions.canDownload(wifiOnly: values.wifiOnlyDownloads)
    }

    private func makeControl(_ phase: ScanPhase) -> ScanControl {
        ScanControl(
            shouldContinue: { [weak self] in
                await self?.checkpoint() ?? false
            },
            progress: { [weak self] completed, total in
                await self?.setProgress(phase, completed, total)
            },
            networkAllowed: { [weak self] in
                await self?.isNetworkAllowed() ?? false
            }
        )
    }

    // MARK: - Fase A

    private func indexPhotoLibrary() async -> Bool {
        guard photos.canRead else {
            // Permesso negato o revocato: gli elementi della libreria non sono più utilizzabili.
            if photos.isDenied {
                store.removeMissing(source: .photoLibrary, keeping: [])
            }
            return true
        }
        activity = "Lettura della libreria Foto"
        let existing = store.existingItems(source: .photoLibrary)
        let includeHidden = preferences.values.includeHiddenAssets
        let seen = await photoIndexer.indexLibrary(
            existing: existing,
            includeHidden: includeHidden,
            control: makeControl(.metadata)
        ) { [store] batch in
            await store.upsert(batch)
        }
        guard let seen else { return false }
        // Una libreria che risulta vuota a dispositivo bloccato non è davvero vuota: l'indice non si tocca.
        if seen.isEmpty && !existing.isEmpty && !UIApplication.shared.isProtectedDataAvailable {
            return true
        }
        store.removeMissing(source: .photoLibrary, keeping: seen)
        return true
    }

    private func indexFolders() async -> Bool {
        for folder in folders.folders {
            guard let root = folders.resolvedURL(for: folder.id) else { continue }
            activity = "Lettura della cartella \(folder.name)"
            let seen = await fileIndexer.index(folder: folder, root: root, control: makeControl(.metadata)) { [store] batch in
                await store.upsert(batch)
            }
            guard let seen else { return false }
            // Cartella momentaneamente non raggiungibile (rete assente, provider non pronto):
            // un elenco vuoto non significa che i file siano stati rimossi.
            let isReachable = (try? root.checkResourceIsReachable()) ?? false
            if seen.isEmpty && !isReachable {
                continue
            }
            store.removeMissing(inFolder: folder.id, keeping: seen)
            let indexed = store.existingItems(inFolder: folder.id)
            folders.updateStatistics(
                folderID: folder.id,
                itemCount: indexed.count,
                totalBytes: indexed.values.reduce(0) { $0 + $1.bytes }
            )
        }
        return true
    }

    private func indexImports() async {
        let items = await fileIndexer.indexImports(directory: folders.importsDirectory)
        store.upsert(items)
        store.removeMissing(source: .appImports, keeping: Set(items.map { $0.sourceIdentifier }))
    }

    /// Un originale presente solo online dimostra che Foto di iCloud è attivo.
    private func detectICloudPhotos() {
        guard preferences.values.iCloudPhotosState == .unknown else { return }
        let hasCloudOnly = store.snapshot().contains {
            $0.source == .photoLibrary && $0.traits.contains(.cloudOnly)
        }
        if hasCloudOnly {
            preferences.update { $0.iCloudPhotosState = .enabled }
        }
    }

    // MARK: - Fase B

    private func analyzePhotoPreviews() async -> Bool {
        // Si analizza solo ciò che non è ancora stato esaminato, partendo dai contenuti più recenti.
        let pending = store.snapshot()
            .filter { $0.source == .photoLibrary && $0.analysisStatus == .metadataOnly }
            .sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        guard !pending.isEmpty else { return true }
        return await photoPipeline.analyzePreviews(items: pending, control: makeControl(.previews)) { [store] updates in
            await store.apply(updates)
        }
    }

    private func groupSimilarPhotos() async -> Bool {
        let images = store.snapshot().filter { $0.source == .photoLibrary && $0.category == .photo }
        let result = await photoPipeline.buildSimilarityGroups(
            items: images,
            onlyUnchecked: true,
            thresholds: preferences.values.similaritySensitivity.thresholds,
            control: makeControl(.previews)
        )
        store.replaceGroups(
            kinds: [.similar, .burst],
            scope: .photoLibrary,
            touching: result.processedIDs,
            with: result.groups
        )
        store.addTraits(.similarityChecked, to: result.processedIDs)
        return result.isComplete
    }

    private func groupVisualDuplicates() async -> Bool {
        // I duplicati già verificati sull'originale non vengono declassati a "probabili".
        let verifiedIDs = Set(
            store.groupsSnapshot()
                .filter { $0.kind == .exactDuplicate && $0.scope == .photoLibrary }
                .flatMap { $0.memberIDs }
        )
        let groups = await photoPipeline.buildVisualDuplicateGroups(
            items: store.snapshot(),
            excluding: verifiedIDs,
            control: makeControl(.previews)
        )
        guard let groups else { return false }
        store.replaceGroups(kinds: [.visualDuplicate], scope: .photoLibrary, with: groups)
        return true
    }

    /// Gruppi in cui lo scatto da conservare si sceglie confrontando la qualità.
    static let rankedKinds: Set<GroupKind> = [.similar, .burst, .visualDuplicate]

    /// Confronta tra loro gli scatti di ogni gruppo con misure più precise di quelle della scansione
    /// generale (volti, occhi, nitidezza del soggetto) e aggiorna il candidato suggerito.
    private func rankSimilarShots() async -> Bool {
        let pending = store.itemsMissingShotMetrics(kinds: Self.rankedKinds)
        guard !pending.isEmpty else { return true }
        let completed = await photoPipeline.analyzeShots(
            items: pending,
            control: makeControl(.previews)
        ) { [store] updates in
            await store.apply(updates)
        }
        store.refreshSuggestions(kinds: Self.rankedKinds) { members in
            QualityRanker.suggestion(among: members)
        }
        return completed
    }

    // MARK: - Fase C

    private func verifyLibraryDuplicates() async -> Bool {
        let groups = await photoPipeline.verifyExactDuplicates(
            items: store.snapshot(),
            control: makeControl(.deep)
        ) { [store] updates in
            await store.apply(updates)
        }
        guard let groups else { return false }
        store.replaceGroups(kinds: [.exactDuplicate], scope: .photoLibrary, with: groups)
        return true
    }

    private func groupSimilarVideos() async -> Bool {
        let groups = await photoPipeline.buildSimilarVideoGroups(
            items: store.snapshot(),
            control: makeControl(.deep)
        )
        guard let groups else { return false }
        store.replaceGroups(kinds: [.similarVideo], scope: .photoLibrary, with: groups)
        return true
    }

    /// Elementi basati su file, con l'indirizzo da cui leggerli.
    private func fileEntries(where isIncluded: (IndexedItem) -> Bool) -> [FileEntry] {
        store.snapshot().compactMap { item in
            guard item.source.isFileBased, isIncluded(item), let url = folders.url(for: item) else { return nil }
            return FileEntry(item: item, url: url)
        }
    }

    private func analyzeFiles() async -> Bool {
        let apply: @Sendable ([AnalysisUpdate]) async -> Void = { [store] updates in
            await store.apply(updates)
        }

        activity = "Ricerca di file duplicati"
        let allFiles = fileEntries { _ in true }
        let exact = await filePipeline.verifyExactDuplicates(
            entries: allFiles,
            control: makeControl(.deep),
            apply: apply
        )
        guard let exact else { return false }
        store.replaceGroups(kinds: [.exactDuplicate], scope: .files, with: exact)

        if plan.isUnlocked(.similarDocuments) {
            activity = "Confronto delle versioni dei documenti"
            let documents = fileEntries { $0.category.isDocument }
            let versions = await filePipeline.findDocumentVersions(
                entries: documents,
                control: makeControl(.deep),
                apply: apply
            )
            guard let versions else { return false }
            store.replaceGroups(kinds: [.documentVersion], scope: .files, with: versions)
        }

        if photos.canRead {
            activity = "Confronto tra file e libreria Foto"
            // I gruppi precedenti vengono azzerati, così il confronto riparte da elementi "liberi".
            store.replaceGroups(kinds: [.exactDuplicate, .visualDuplicate], scope: .crossSource, with: [])
            let images = fileEntries { $0.category == .photo }
            let library = store.snapshot().filter { $0.source == .photoLibrary && $0.category == .photo }
            let cross = await filePipeline.findCrossSourceDuplicates(
                imageEntries: images,
                libraryItems: library,
                control: makeControl(.deep),
                apply: apply
            )
            guard let cross else { return false }
            store.replaceGroups(kinds: [.exactDuplicate, .visualDuplicate], scope: .crossSource, with: cross)
        }
        return true
    }

    private func analyzeAudioFiles() async -> Bool {
        let audio = fileEntries { $0.category == .audio }
        guard !audio.isEmpty else { return true }
        let groups = await filePipeline.analyzeAudio(entries: audio, control: makeControl(.deep)) { [store] updates in
            await store.apply(updates)
        }
        guard let groups else { return false }
        store.replaceGroups(kinds: [.similarAudio], scope: .files, with: groups)
        return true
    }
}
