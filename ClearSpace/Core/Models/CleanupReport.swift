import Foundation

/// Fotografia dello spazio del dispositivo in un dato momento.
struct StorageSnapshot: Codable, Hashable, Sendable {
    var date: Date
    var totalBytes: Int64
    var availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
}

enum PlannedOperation: String, Codable, Sendable {
    /// Sposta l'asset in "Eliminati di recente" tramite PhotoKit.
    case deleteLibraryAsset
    /// Rimuove un file da una cartella autorizzata.
    case removeFile
    /// Rimuove la copia importata in ClearSpace: l'originale nell'app di origine non viene toccato.
    case removeImportedCopy
}

/// Singola operazione prevista, con gli effetti distinti su iPhone e iCloud.
struct PlanEntry: Identifiable, Codable, Hashable, Sendable {
    let itemID: UUID
    let title: String
    let source: StorageSource
    let category: ContentCategory
    let operation: PlannedOperation
    let deviceBytes: Int64
    let cloudBytes: Int64
    /// `true` quando l'effetto su iCloud dipende da un'impostazione che l'app non può leggere.
    let cloudEffectIsConditional: Bool
    let isSensitive: Bool

    var id: UUID { itemID }
}

struct PlanExclusion: Identifiable, Codable, Hashable, Sendable {
    let itemID: UUID
    let title: String
    let reason: BlockReason

    var id: UUID { itemID }
}

/// Conferma consapevole dell'utente. Può essere creata solo dalla schermata di conferma.
struct DeletionConfirmation: Sendable {
    let planID: UUID
    let confirmedAt: Date
    let acknowledgedICloudEffects: Bool
    let acknowledgedSensitiveItems: Bool
    /// Consente l'eliminazione definitiva dei file quando il cestino non è supportato dal provider.
    let allowPermanentFileDeletion: Bool
}

enum ConfirmationError: Error, Equatable {
    case emptyPlan
    case planMismatch
    case planExpired
    case iCloudNotAcknowledged
    case sensitiveNotAcknowledged

    var message: String {
        switch self {
        case .emptyPlan: return "Non ci sono elementi da eliminare."
        case .planMismatch: return "La conferma non corrisponde all'elenco mostrato."
        case .planExpired: return "L'elenco è cambiato o è troppo vecchio: ricontrollalo prima di confermare."
        case .iCloudNotAcknowledged: return "Conferma di aver compreso gli effetti su iCloud."
        case .sensitiveNotAcknowledged: return "Conferma di aver controllato i contenuti potenzialmente importanti."
        }
    }
}

/// Elenco completo di ciò che verrebbe eliminato, mostrato all'utente prima della conferma.
struct DeletionPlan: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    var entries: [PlanEntry]
    var exclusions: [PlanExclusion]

    /// Un piano resta valido per un tempo limitato: poi va ricreato e ricontrollato.
    static let validity: TimeInterval = 15 * 60

    init(id: UUID = UUID(), createdAt: Date = Date(), entries: [PlanEntry], exclusions: [PlanExclusion]) {
        self.id = id
        self.createdAt = createdAt
        self.entries = entries
        self.exclusions = exclusions
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Spazio che si libererebbe sull'iPhone.
    var deviceBytes: Int64 { entries.reduce(0) { $0 + $1.deviceBytes } }

    /// Spazio che si libererebbe con certezza su iCloud.
    var cloudBytes: Int64 {
        entries.reduce(0) { $0 + ($1.cloudEffectIsConditional ? 0 : $1.cloudBytes) }
    }

    /// Spazio che si libererebbe su iCloud solo se Foto di iCloud è attivo.
    var conditionalCloudBytes: Int64 {
        entries.reduce(0) { $0 + ($1.cloudEffectIsConditional ? $1.cloudBytes : 0) }
    }

    var affectsICloud: Bool { entries.contains { $0.cloudBytes > 0 } }
    var sensitiveCount: Int { entries.filter { $0.isSensitive }.count }
    var libraryCount: Int { entries.filter { $0.operation == .deleteLibraryAsset }.count }
    var fileCount: Int { entries.filter { $0.operation == .removeFile }.count }
    var importCount: Int { entries.filter { $0.operation == .removeImportedCopy }.count }

    /// Verifica che la conferma sia coerente con questo piano. Senza conferma valida nulla viene eliminato.
    func validate(_ confirmation: DeletionConfirmation, now: Date = Date()) throws {
        guard !entries.isEmpty else { throw ConfirmationError.emptyPlan }
        guard confirmation.planID == id else { throw ConfirmationError.planMismatch }
        guard confirmation.confirmedAt >= createdAt, now.timeIntervalSince(createdAt) <= Self.validity else {
            throw ConfirmationError.planExpired
        }
        if affectsICloud && !confirmation.acknowledgedICloudEffects {
            throw ConfirmationError.iCloudNotAcknowledged
        }
        if sensitiveCount > 0 && !confirmation.acknowledgedSensitiveItems {
            throw ConfirmationError.sensitiveNotAcknowledged
        }
    }
}

/// I tre stati mostrati nella revisione: in attesa, eliminato correttamente, operazione non riuscita.
enum OutcomeState: String, Codable, Sendable {
    case pending
    case deleted
    case failed
    case skipped

    var title: String {
        switch self {
        case .pending: return "In attesa"
        case .deleted: return "Eliminato correttamente"
        case .failed: return "Operazione non riuscita"
        case .skipped: return "Escluso"
        }
    }
}

struct ItemOutcome: Identifiable, Codable, Hashable, Sendable {
    let itemID: UUID
    let title: String
    let source: StorageSource
    let category: ContentCategory
    var state: OutcomeState
    var message: String?
    let deviceBytes: Int64
    let cloudBytes: Int64
    let cloudEffectIsConditional: Bool

    var id: UUID { itemID }

    init(entry: PlanEntry, state: OutcomeState = .pending, message: String? = nil) {
        self.itemID = entry.itemID
        self.title = entry.title
        self.source = entry.source
        self.category = entry.category
        self.state = state
        self.message = message
        self.deviceBytes = entry.deviceBytes
        self.cloudBytes = entry.cloudBytes
        self.cloudEffectIsConditional = entry.cloudEffectIsConditional
    }
}

/// Resoconto di un'operazione eseguita: riporta solo ciò che è stato realmente completato.
struct CleanupReport: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    var outcomes: [ItemOutcome]
    var snapshotBefore: StorageSnapshot?
    var snapshotAfter: StorageSnapshot?
    /// L'utente ha rifiutato la conferma di sistema di iOS.
    var systemDialogDeclined: Bool
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        outcomes: [ItemOutcome],
        snapshotBefore: StorageSnapshot? = nil,
        snapshotAfter: StorageSnapshot? = nil,
        systemDialogDeclined: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.outcomes = outcomes
        self.snapshotBefore = snapshotBefore
        self.snapshotAfter = snapshotAfter
        self.systemDialogDeclined = systemDialogDeclined
        self.note = note
    }

    private func count(_ state: OutcomeState) -> Int {
        outcomes.reduce(0) { $0 + ($1.state == state ? 1 : 0) }
    }

    var deletedCount: Int { count(.deleted) }
    var failedCount: Int { count(.failed) }
    var pendingCount: Int { count(.pending) }
    var skippedCount: Int { count(.skipped) }

    /// Foto e video spostati in Eliminati di recente: occupano ancora spazio finché quell'album
    /// dell'app Foto non viene svuotato (o finché non passano 30 giorni).
    var recentlyDeletedCount: Int {
        outcomes.reduce(0) { $0 + ($1.state == .deleted && $1.source == .photoLibrary ? 1 : 0) }
    }

    /// Spazio sull'iPhone che si libera davvero solo svuotando Eliminati di recente.
    var recentlyDeletedDeviceBytes: Int64 {
        outcomes.reduce(0) { $0 + ($1.state == .deleted && $1.source == .photoLibrary ? $1.deviceBytes : 0) }
    }

    /// Spazio liberato sull'iPhone dagli elementi effettivamente eliminati.
    var deviceBytesFreed: Int64 {
        outcomes.reduce(0) { $0 + ($1.state == .deleted ? $1.deviceBytes : 0) }
    }

    /// Spazio liberato con certezza su iCloud. Non va sommato a quello dell'iPhone:
    /// si tratta degli stessi contenuti visti da due posizioni diverse.
    var cloudBytesFreed: Int64 {
        outcomes.reduce(0) { $0 + ($1.state == .deleted && !$1.cloudEffectIsConditional ? $1.cloudBytes : 0) }
    }

    var conditionalCloudBytes: Int64 {
        outcomes.reduce(0) { $0 + ($1.state == .deleted && $1.cloudEffectIsConditional ? $1.cloudBytes : 0) }
    }

    /// Differenza di spazio libero misurata dal sistema tra prima e dopo.
    var measuredDeviceDelta: Int64? {
        guard let before = snapshotBefore, let after = snapshotAfter else { return nil }
        return after.availableBytes - before.availableBytes
    }
}

/// Costruisce il piano di eliminazione a partire dagli elementi selezionati. Funzione pura.
enum PlanBuilder {

    static func build(
        markedItems: [IndexedItem],
        evaluator: ProtectionEvaluator,
        iCloudPhotos: ICloudPhotosState,
        canAccessPhotos: Bool,
        now: Date = Date()
    ) -> DeletionPlan {
        var entries: [PlanEntry] = []
        var exclusions: [PlanExclusion] = []

        for item in markedItems {
            guard item.reviewStatus.isQueuedForDeletion else {
                exclusions.append(PlanExclusion(itemID: item.id, title: item.displayTitle, reason: .notMarked))
                continue
            }
            if let reason = evaluator.blockReason(for: item) {
                exclusions.append(PlanExclusion(itemID: item.id, title: item.displayTitle, reason: reason))
                continue
            }

            let sensitive = evaluator.needsCaution(item)
            switch item.source {
            case .photoLibrary:
                guard canAccessPhotos else {
                    exclusions.append(PlanExclusion(itemID: item.id, title: item.displayTitle, reason: .accessRevoked))
                    continue
                }
                // Un originale presente solo online dimostra che Foto di iCloud è attivo.
                let state: ICloudPhotosState = item.traits.contains(.cloudOnly) ? .enabled : iCloudPhotos
                let cloudBytes: Int64
                let conditional: Bool
                switch state {
                case .enabled:
                    cloudBytes = item.bytes
                    conditional = false
                case .disabled:
                    cloudBytes = 0
                    conditional = false
                case .unknown:
                    cloudBytes = item.bytes
                    conditional = true
                }
                entries.append(PlanEntry(
                    itemID: item.id, title: item.displayTitle, source: item.source, category: item.category,
                    operation: .deleteLibraryAsset, deviceBytes: item.deviceBytes, cloudBytes: cloudBytes,
                    cloudEffectIsConditional: conditional, isSensitive: sensitive
                ))
            case .iCloudDrive:
                entries.append(PlanEntry(
                    itemID: item.id, title: item.displayTitle, source: item.source, category: item.category,
                    operation: .removeFile, deviceBytes: item.deviceBytes, cloudBytes: item.bytes,
                    cloudEffectIsConditional: false, isSensitive: sensitive
                ))
            case .localFiles:
                entries.append(PlanEntry(
                    itemID: item.id, title: item.displayTitle, source: item.source, category: item.category,
                    operation: .removeFile, deviceBytes: item.bytes, cloudBytes: 0,
                    cloudEffectIsConditional: false, isSensitive: sensitive
                ))
            case .appImports:
                entries.append(PlanEntry(
                    itemID: item.id, title: item.displayTitle, source: item.source, category: item.category,
                    operation: .removeImportedCopy, deviceBytes: item.bytes, cloudBytes: 0,
                    cloudEffectIsConditional: false, isSensitive: sensitive
                ))
            }
        }

        return DeletionPlan(createdAt: now, entries: entries, exclusions: exclusions)
    }
}

/// Esito di un tentativo di selezione.
enum MarkResult: Equatable, Sendable {
    case applied
    /// Applicato, ma il contenuto è potenzialmente importante e verrà evidenziato nella revisione.
    case appliedWithCaution
    case blocked(BlockReason)
}

/// Regole di sicurezza indipendenti dall'interfaccia.
enum SafetyRules {

    /// Traduce una scelta nello stato di revisione corrispondente.
    /// Uno swipe cambia soltanto questo stato: nessun file viene eliminato in questa fase.
    static func evaluate(
        _ choice: SwipeChoice,
        on item: IndexedItem,
        evaluator: ProtectionEvaluator
    ) -> (status: ReviewStatus?, result: MarkResult) {
        switch choice {
        case .keep:
            return (.kept, .applied)
        case .postpone:
            return (.postponed, .applied)
        case .delete:
            if let reason = evaluator.blockReason(for: item) {
                return (nil, .blocked(reason))
            }
            let result: MarkResult = evaluator.needsCaution(item) ? .appliedWithCaution : .applied
            return (.markedForDeletion, result)
        }
    }
}
