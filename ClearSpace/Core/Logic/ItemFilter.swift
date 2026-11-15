import Foundation

enum ItemSort: String, Codable, CaseIterable, Sendable {
    case recoverability
    case sizeDescending
    case oldestFirst
    case newestFirst
    case durationDescending
    case nameAscending

    var title: String {
        switch self {
        case .recoverability: return "Consigliati"
        case .sizeDescending: return "Più pesanti"
        case .oldestFirst: return "Più vecchi"
        case .newestFirst: return "Più recenti"
        case .durationDescending: return "Più lunghi"
        case .nameAscending: return "Nome"
        }
    }
}

/// Filtro combinabile usato dalla pulizia avanzata e dalla ricerca in linguaggio naturale.
struct ItemFilter: Codable, Equatable, Sendable {
    /// Vuoto = tutti i tipi.
    var categories: Set<ContentCategory> = []
    /// Vuoto = tutte le origini.
    var sources: Set<StorageSource> = []
    /// L'elemento deve avere tutti questi tratti.
    var requiredTraits: ItemTraits = []
    /// L'elemento deve avere almeno uno di questi tratti.
    var anyTraits: ItemTraits = []
    var excludedTraits: ItemTraits = []
    var minBytes: Int64?
    var maxBytes: Int64?
    var createdAfter: Date?
    var createdBefore: Date?
    var year: Int?
    var month: Int?
    var minDuration: Double?
    var maxDuration: Double?
    /// Parole (già normalizzate) da cercare nel nome o nel testo riconosciuto.
    var textTokens: [String] = []
    var folderIDs: Set<UUID> = []
    /// Vuoto = qualsiasi stato.
    var reviewStatuses: Set<ReviewStatus> = []
    var onlyDuplicates = false
    var onlySimilar = false
    var includeProtected = true
    var sort: ItemSort = .sizeDescending
    var limit: Int?

    init() {}

    /// Vero se il filtro non restringe nulla.
    var isUnconstrained: Bool {
        var neutral = ItemFilter()
        neutral.sort = sort
        neutral.includeProtected = includeProtected
        return self == neutral
    }

    func matches(
        _ item: IndexedItem,
        evaluator: ProtectionEvaluator? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        if !categories.isEmpty && !categories.contains(item.category) { return false }
        if !sources.isEmpty && !sources.contains(item.source) { return false }
        if !requiredTraits.isEmpty && !item.traits.isSuperset(of: requiredTraits) { return false }
        if !anyTraits.isEmpty && item.traits.isDisjoint(with: anyTraits) { return false }
        if !excludedTraits.isEmpty && !item.traits.isDisjoint(with: excludedTraits) { return false }
        if let minBytes, item.bytes < minBytes { return false }
        if let maxBytes, item.bytes > maxBytes { return false }

        if createdAfter != nil || createdBefore != nil || year != nil || month != nil {
            guard let date = item.createdAt else { return false }
            if let createdAfter, date < createdAfter { return false }
            if let createdBefore, date > createdBefore { return false }
            if let year, calendar.component(.year, from: date) != year { return false }
            if let month, calendar.component(.month, from: date) != month { return false }
        }

        if let minDuration, item.duration < minDuration { return false }
        if let maxDuration, item.duration > maxDuration { return false }

        if !folderIDs.isEmpty {
            guard let folderID = item.folderID, folderIDs.contains(folderID) else { return false }
        }
        if !reviewStatuses.isEmpty && !reviewStatuses.contains(item.reviewStatus) { return false }
        if onlyDuplicates && item.duplicateGroupID == nil { return false }
        if onlySimilar && item.similarityGroupID == nil { return false }
        if !includeProtected, let evaluator, evaluator.isProtected(item) { return false }

        // Il confronto testuale è il più costoso: viene eseguito per ultimo.
        if !textTokens.isEmpty {
            let haystack = item.searchableText
            for token in textTokens where !haystack.contains(token) {
                return false
            }
        }
        return true
    }

    /// Filtra, ordina e limita.
    func apply(
        to items: [IndexedItem],
        evaluator: ProtectionEvaluator? = nil,
        score: ((IndexedItem) -> Double)? = nil,
        calendar: Calendar = .current
    ) -> [IndexedItem] {
        let matched = items.filter { matches($0, evaluator: evaluator, calendar: calendar) }
        let ordered = ItemFilter.sorted(matched, by: sort, score: score)
        if let limit, limit >= 0, limit < ordered.count {
            return Array(ordered.prefix(limit))
        }
        return ordered
    }

    static func sorted(
        _ items: [IndexedItem],
        by order: ItemSort,
        score: ((IndexedItem) -> Double)? = nil
    ) -> [IndexedItem] {
        switch order {
        case .recoverability:
            guard let score else {
                return items.sorted { $0.bytes > $1.bytes }
            }
            let scored = items.map { (item: $0, value: score($0)) }
            return scored.sorted { $0.value > $1.value }.map { $0.item }
        case .sizeDescending:
            return items.sorted { $0.bytes > $1.bytes }
        case .oldestFirst:
            return items.sorted { ($0.createdAt ?? Date.distantFuture) < ($1.createdAt ?? Date.distantFuture) }
        case .newestFirst:
            return items.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        case .durationDescending:
            return items.sorted { $0.duration > $1.duration }
        case .nameAscending:
            return items.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }
    }
}
