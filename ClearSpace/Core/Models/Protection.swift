import Foundation

/// Motivo per cui un elemento non può essere proposto per l'eliminazione o viene escluso da un piano.
enum BlockReason: String, Codable, Sendable, Equatable {
    case userProtected
    case favorite
    case hidden
    case protectedAlbum
    case protectedFolder
    case protectedPeriod
    case accessRevoked
    case notMarked
    case missing

    var message: String {
        switch self {
        case .userProtected: return "Elemento protetto da te."
        case .favorite: return "È tra i preferiti, protetti per impostazione predefinita."
        case .hidden: return "È una foto nascosta, protetta per impostazione predefinita."
        case .protectedAlbum: return "Appartiene a un album protetto."
        case .protectedFolder: return "Si trova in una cartella protetta."
        case .protectedPeriod: return "Appartiene a un periodo protetto."
        case .accessRevoked: return "L'accesso a questo contenuto non è più autorizzato."
        case .notMarked: return "Non è più selezionato per l'eliminazione."
        case .missing: return "L'elemento non è più disponibile."
        }
    }

    /// Le protezioni automatiche possono essere sbloccate dall'utente, elemento per elemento.
    var canBeOverridden: Bool {
        switch self {
        case .favorite, .hidden, .protectedAlbum, .protectedFolder, .protectedPeriod: return true
        case .userProtected, .accessRevoked, .notMarked, .missing: return false
        }
    }
}

struct ProtectedPeriod: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var start: Date
    var end: Date

    init(id: UUID = UUID(), name: String, start: Date, end: Date) {
        self.id = id
        self.name = name
        self.start = min(start, end)
        self.end = max(start, end)
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

/// Regole di protezione scelte dall'utente.
struct ProtectionRules: Codable, Equatable, Sendable {
    var protectFavorites = true
    var protectHidden = true
    /// Evidenzia i contenuti potenzialmente importanti e richiede una conferma dedicata.
    var cautionForSensitive = true
    var protectedAlbumIDs: Set<String> = []
    var protectedFolderIDs: Set<UUID> = []
    var protectedPeriods: [ProtectedPeriod] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protectFavorites = try container.decodeIfPresent(Bool.self, forKey: .protectFavorites) ?? true
        protectHidden = try container.decodeIfPresent(Bool.self, forKey: .protectHidden) ?? true
        cautionForSensitive = try container.decodeIfPresent(Bool.self, forKey: .cautionForSensitive) ?? true
        protectedAlbumIDs = try container.decodeIfPresent(Set<String>.self, forKey: .protectedAlbumIDs) ?? []
        protectedFolderIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .protectedFolderIDs) ?? []
        protectedPeriods = try container.decodeIfPresent([ProtectedPeriod].self, forKey: .protectedPeriods) ?? []
    }
}

/// Valuta se un elemento è protetto. È un valore puro: può essere usato anche fuori dal thread principale.
struct ProtectionEvaluator: Sendable {
    var rules: ProtectionRules
    /// Identificativi degli asset contenuti negli album protetti.
    var protectedAlbumMembers: Set<String>

    init(rules: ProtectionRules = ProtectionRules(), protectedAlbumMembers: Set<String> = []) {
        self.rules = rules
        self.protectedAlbumMembers = protectedAlbumMembers
    }

    /// Restituisce il motivo del blocco, oppure `nil` se l'elemento può essere proposto per la revisione.
    func blockReason(for item: IndexedItem) -> BlockReason? {
        if item.isProtected { return .userProtected }
        if item.protectionOverride { return nil }
        if rules.protectFavorites && item.traits.contains(.favorite) { return .favorite }
        if rules.protectHidden && item.traits.contains(.hidden) { return .hidden }
        if item.source == .photoLibrary && protectedAlbumMembers.contains(item.sourceIdentifier) {
            return .protectedAlbum
        }
        if let folderID = item.folderID, rules.protectedFolderIDs.contains(folderID) {
            return .protectedFolder
        }
        if let date = item.createdAt, rules.protectedPeriods.contains(where: { $0.contains(date) }) {
            return .protectedPeriod
        }
        return nil
    }

    func isProtected(_ item: IndexedItem) -> Bool {
        blockReason(for: item) != nil
    }

    /// Contenuto potenzialmente importante: non è bloccato, ma va evidenziato e confermato a parte.
    func needsCaution(_ item: IndexedItem) -> Bool {
        rules.cautionForSensitive && item.isSensitive
    }

    /// Elemento ancora da decidere e non protetto: può entrare in una sessione di pulizia.
    func isReviewable(_ item: IndexedItem) -> Bool {
        item.isPendingReview && blockReason(for: item) == nil
    }
}
