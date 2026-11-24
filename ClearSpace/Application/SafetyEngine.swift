import Foundation

/// Avanzamento di un'operazione di eliminazione confermata.
struct ExecutionProgress: Equatable, Sendable {
    var completed: Int
    var total: Int
    var message: String
}

/// Motore di sicurezza: è l'unico punto dell'app da cui parte un'eliminazione.
///
/// Regole garantite qui:
/// 1. uno swipe (o una selezione) cambia soltanto lo stato di revisione di un elemento;
/// 2. gli elementi protetti non possono entrare nella lista delle eliminazioni;
/// 3. si elimina solo ciò che compare in un piano mostrato all'utente e confermato in modo valido;
/// 4. prima di eseguire, ogni elemento viene ricontrollato;
/// 5. dopo l'esecuzione si verifica l'esito e si registra soltanto ciò che è realmente avvenuto;
/// 6. nessuna analisi automatica può avviare un'eliminazione.
@MainActor
final class SafetyEngine {

    private let store: IndexStore
    private let preferences: PreferencesStore
    private let photos: PhotoLibraryService
    private let folders: FolderAccessService
    private let fileOperations: FileOperationService
    private let history: HistoryStore
    private let thumbnails: ThumbnailProvider

    /// Identificativi degli asset contenuti negli album protetti dall'utente.
    private(set) var protectedAlbumMembers: Set<String> = []

    init(
        store: IndexStore,
        preferences: PreferencesStore,
        photos: PhotoLibraryService,
        folders: FolderAccessService,
        fileOperations: FileOperationService,
        history: HistoryStore,
        thumbnails: ThumbnailProvider
    ) {
        self.store = store
        self.preferences = preferences
        self.photos = photos
        self.folders = folders
        self.fileOperations = fileOperations
        self.history = history
        self.thumbnails = thumbnails
    }

    // MARK: - Protezioni

    func evaluator() -> ProtectionEvaluator {
        ProtectionEvaluator(
            rules: preferences.values.protection,
            protectedAlbumMembers: protectedAlbumMembers
        )
    }

    /// Rilegge il contenuto degli album protetti. Va chiamato quando cambiano le regole o la libreria.
    func refreshProtectedAlbums() async {
        let albumIDs = preferences.values.protection.protectedAlbumIDs
        guard photos.canRead, !albumIDs.isEmpty else {
            protectedAlbumMembers = []
            return
        }
        protectedAlbumMembers = await Task.detached(priority: .utility) {
            PhotoLibraryService.memberIdentifiers(ofAlbums: albumIDs)
        }.value
    }

    func blockReason(for item: IndexedItem) -> BlockReason? {
        evaluator().blockReason(for: item)
    }

    /// Protegge esplicitamente gli elementi: escono dalla lista delle eliminazioni e non possono rientrarci.
    func protect(_ ids: [UUID]) {
        store.setProtection(isProtected: true, override: false, for: ids)
    }

    func removeProtection(_ ids: [UUID]) {
        store.setProtection(isProtected: false, override: false, for: ids)
    }

    /// Sblocca una protezione automatica (preferito, album, cartella, periodo) per un singolo elemento,
    /// su richiesta esplicita dell'utente.
    func unlock(_ id: UUID) {
        store.setProtection(isProtected: false, override: true, for: [id])
    }

    // MARK: - Selezione (nessuna eliminazione)

    /// Applica una scelta a un elemento. Cambia soltanto lo stato di revisione.
    @discardableResult
    func apply(_ choice: SwipeChoice, to id: UUID) -> MarkResult? {
        guard let item = store.item(id) else { return nil }
        let evaluation = SafetyRules.evaluate(choice, on: item, evaluator: evaluator())
        if let status = evaluation.status {
            store.setReviewStatus(status, for: [id])
        }
        return evaluation.result
    }

    /// Propone più elementi per l'eliminazione. Quelli protetti vengono saltati.
    @discardableResult
    func markForDeletion(_ ids: [UUID]) -> (applied: Int, blocked: Int) {
        let protection = self.evaluator()
        var accepted: [UUID] = []
        var blocked = 0
        for id in ids {
            guard let item = store.item(id) else { continue }
            if protection.blockReason(for: item) == nil {
                accepted.append(id)
            } else {
                blocked += 1
            }
        }
        store.setReviewStatus(.markedForDeletion, for: accepted)
        return (accepted.count, blocked)
    }

    func keep(_ ids: [UUID]) {
        store.setReviewStatus(.kept, for: ids)
    }

    /// Toglie gli elementi dalla lista delle eliminazioni, riportandoli a "da rivedere".
    func restore(_ ids: [UUID]) {
        store.setReviewStatus(.unreviewed, for: ids)
    }

    /// Annulla tutte le selezioni in attesa.
    func restoreAll() {
        store.setReviewStatus(.unreviewed, for: store.markedItems().map { $0.id })
    }

    // MARK: - Piano di eliminazione

    /// Prepara l'elenco di ciò che verrebbe eliminato, con gli effetti su iPhone e iCloud.
    /// Prima rilegge dal sistema dimensioni e disponibilità locale degli asset coinvolti.
    /// - Parameter ids: se indicati, il piano comprende solo questi elementi (tra quelli proposti),
    ///   ad esempio le foto scartate di un singolo gruppo; altrimenti tutta la lista di revisione.
    func makePlan(only ids: Set<UUID>? = nil) async -> DeletionPlan {
        let marked = store.markedItems().filter { ids?.contains($0.id) ?? true }
        let libraryItems = marked.filter { $0.source == .photoLibrary }

        if photos.canRead && !libraryItems.isEmpty {
            let identifiers = libraryItems.map { $0.sourceIdentifier }
            let fresh = await Task.detached(priority: .userInitiated) { () -> [String: ResourceInfo] in
                var result: [String: ResourceInfo] = [:]
                for asset in PhotoLibraryService.assets(identifiers) {
                    result[asset.localIdentifier] = PhotoResourceInspector.inspect(asset)
                }
                return result
            }.value

            var infoByID: [UUID: ResourceInfo] = [:]
            for item in libraryItems {
                if let info = fresh[item.sourceIdentifier] {
                    infoByID[item.id] = info
                }
            }
            store.mutateEach(Array(infoByID.keys)) { item in
                guard let info = infoByID[item.id] else { return }
                if let total = info.totalBytes, total > 0 {
                    item.estimatedBytes = total
                    item.bytesAreEstimated = false
                    item.localBytes = info.localBytes
                }
                if info.originalIsLocal == false {
                    item.traits.insert(.cloudOnly)
                } else if info.originalIsLocal == true {
                    item.traits.remove(.cloudOnly)
                }
            }
        }

        return PlanBuilder.build(
            markedItems: store.markedItems().filter { ids?.contains($0.id) ?? true },
            evaluator: evaluator(),
            iCloudPhotos: preferences.values.iCloudPhotosState,
            canAccessPhotos: photos.canRead
        )
    }

    // MARK: - Esecuzione

    /// Esegue un piano confermato. Senza una conferma valida non viene eliminato nulla.
    func execute(
        _ plan: DeletionPlan,
        confirmation: DeletionConfirmation,
        onProgress: @escaping @MainActor (ExecutionProgress) -> Void = { _ in }
    ) async -> CleanupReport {
        var outcomes: [UUID: ItemOutcome] = [:]
        for entry in plan.entries {
            outcomes[entry.itemID] = ItemOutcome(entry: entry)
        }

        do {
            try plan.validate(confirmation)
        } catch {
            let reason = (error as? ConfirmationError)?.message ?? "Conferma non valida."
            return CleanupReport(outcomes: plan.entries.compactMap { outcomes[$0.itemID] }, note: reason)
        }

        func record(_ id: UUID, _ state: OutcomeState, _ message: String?) {
            outcomes[id]?.state = state
            outcomes[id]?.message = message
        }

        let before = DeviceStorage.snapshot()
        let protection = self.evaluator()

        // Ricontrollo: dopo la creazione del piano lo stato degli elementi può essere cambiato.
        var libraryWork: [(entry: PlanEntry, item: IndexedItem)] = []
        var fileWork: [(entry: PlanEntry, item: IndexedItem)] = []
        var vanishedIDs: [UUID] = []
        for entry in plan.entries {
            guard let item = store.item(entry.itemID) else {
                record(entry.itemID, .skipped, BlockReason.missing.message)
                continue
            }
            guard item.reviewStatus.isQueuedForDeletion else {
                record(entry.itemID, .skipped, BlockReason.notMarked.message)
                continue
            }
            if let reason = protection.blockReason(for: item) {
                record(entry.itemID, .skipped, reason.message)
                continue
            }
            switch entry.operation {
            case .deleteLibraryAsset:
                libraryWork.append((entry, item))
            case .removeFile, .removeImportedCopy:
                fileWork.append((entry, item))
            }
        }

        let total = libraryWork.count + fileWork.count
        var completed = 0
        var declinedBySystem = false
        var deletedIDs: [UUID] = []
        var failedIDs: [UUID] = []
        var deletedLibraryIdentifiers: [String] = []

        // Libreria Foto: un'unica richiesta, quindi un'unica conferma di sistema per tutti gli elementi.
        if !libraryWork.isEmpty {
            onProgress(ExecutionProgress(completed: 0, total: total, message: "In attesa della conferma di iOS…"))
            let result = await photos.deleteAssets(identifiers: libraryWork.map { $0.item.sourceIdentifier })
            switch result {
            case .declinedBySystemDialog:
                // Nulla è stato eliminato: gli elementi restano in attesa nella lista di revisione.
                declinedBySystem = true
            case .failed(let message):
                for work in libraryWork {
                    record(work.item.id, .failed, message)
                    failedIDs.append(work.item.id)
                }
            case .completed(let deleted, let alreadyMissing, let failed):
                for work in libraryWork {
                    let identifier = work.item.sourceIdentifier
                    if deleted.contains(identifier) {
                        record(work.item.id, .deleted, "Spostato in Eliminati di recente: recuperabile per 30 giorni.")
                        deletedIDs.append(work.item.id)
                        deletedLibraryIdentifiers.append(identifier)
                    } else if alreadyMissing.contains(identifier) {
                        record(work.item.id, .skipped, "Non era più presente nella libreria.")
                        vanishedIDs.append(work.item.id)
                    } else {
                        record(work.item.id, .failed, failed[identifier] ?? "L'elemento non è stato eliminato.")
                        failedIDs.append(work.item.id)
                    }
                }
            }
            completed += libraryWork.count
            onProgress(ExecutionProgress(completed: completed, total: total, message: "Libreria Foto aggiornata"))
        }

        // File: uno alla volta, ognuno può riuscire o fallire in modo indipendente.
        for work in fileWork {
            onProgress(ExecutionProgress(completed: completed, total: total, message: work.entry.title))
            if let url = folders.url(for: work.item) {
                // Le copie importate vivono nella cartella interna dell'app, che non ha un cestino.
                let allowPermanent = confirmation.allowPermanentFileDeletion
                    || work.entry.operation == .removeImportedCopy
                do {
                    let kind = try await fileOperations.remove(at: url, allowPermanent: allowPermanent)
                    let message = kind == .movedToTrash
                        ? "Spostato in Eliminati di recente dell'app File."
                        : "Eliminato definitivamente."
                    record(work.item.id, .deleted, message)
                    deletedIDs.append(work.item.id)
                } catch FileOperationError.unavailable {
                    record(work.item.id, .skipped, "Non era più presente.")
                    vanishedIDs.append(work.item.id)
                } catch let error as FileOperationError {
                    record(work.item.id, .failed, error.message)
                    failedIDs.append(work.item.id)
                } catch {
                    record(work.item.id, .failed, error.localizedDescription)
                    failedIDs.append(work.item.id)
                }
            } else {
                record(work.item.id, .failed, "La cartella non è più accessibile.")
                failedIDs.append(work.item.id)
            }
            completed += 1
        }
        onProgress(ExecutionProgress(completed: total, total: total, message: "Verifica dei risultati"))

        // L'indice riflette soltanto ciò che è realmente accaduto.
        thumbnails.forget(identifiers: deletedLibraryIdentifiers)
        store.remove(ids: deletedIDs + vanishedIDs)
        if !failedIDs.isEmpty {
            store.setReviewStatus(.deletionFailed, for: failedIDs)
        }

        var note: String?
        if declinedBySystem {
            note = "Hai annullato la conferma di iOS: nessuna foto è stata eliminata."
        } else if !deletedLibraryIdentifiers.isEmpty {
            note = "Foto e video eliminati restano in Eliminati di recente per 30 giorni: lo spazio si libera davvero solo quando quell'album viene svuotato."
        }

        let report = CleanupReport(
            outcomes: plan.entries.compactMap { outcomes[$0.itemID] },
            snapshotBefore: before,
            snapshotAfter: DeviceStorage.snapshot(),
            systemDialogDeclined: declinedBySystem,
            note: note
        )
        if report.deletedCount > 0 || report.failedCount > 0 {
            history.add(report)
        }
        return report
    }
}
