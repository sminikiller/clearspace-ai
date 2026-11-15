import Foundation

/// Categorie su cui l'app impara le abitudini dell'utente.
enum LearningBucket: String, Codable, CaseIterable, Sendable {
    case screenshot
    case duplicate
    case similar
    case largeVideo
    case video
    case lowQuality
    case document
    case audio
    case photo

    static func bucket(for item: IndexedItem, largeVideoBytes: Int64) -> LearningBucket {
        if item.duplicateGroupID != nil { return .duplicate }
        switch item.category {
        case .photo:
            if item.traits.contains(.screenshot) { return .screenshot }
            if item.similarityGroupID != nil { return .similar }
            if item.isLowQuality { return .lowQuality }
            return .photo
        case .video:
            return item.bytes >= largeVideoBytes ? .largeVideo : .video
        case .audio:
            return .audio
        case .pdf, .office, .archive, .otherDocument, .unknown:
            return .document
        }
    }
}

/// Impara quali categorie l'utente tende a rivedere ed eliminare.
/// Serve solo a ordinare i suggerimenti: non autorizza mai un'eliminazione.
struct PreferenceLearner: Codable, Equatable, Sendable {
    private(set) var kept: [String: Int] = [:]
    private(set) var deleted: [String: Int] = [:]

    init() {}

    mutating func record(_ choice: SwipeChoice, bucket: LearningBucket) {
        switch choice {
        case .keep: kept[bucket.rawValue, default: 0] += 1
        case .delete: deleted[bucket.rawValue, default: 0] += 1
        case .postpone: break
        }
    }

    mutating func revert(_ choice: SwipeChoice, bucket: LearningBucket) {
        switch choice {
        case .keep: kept[bucket.rawValue] = max(0, (kept[bucket.rawValue] ?? 0) - 1)
        case .delete: deleted[bucket.rawValue] = max(0, (deleted[bucket.rawValue] ?? 0) - 1)
        case .postpone: break
        }
    }

    /// Propensione a eliminare gli elementi della categoria: 0…1, 0,5 = neutro.
    func affinity(_ bucket: LearningBucket) -> Double {
        let removed = Double(deleted[bucket.rawValue] ?? 0)
        let retained = Double(kept[bucket.rawValue] ?? 0)
        return (removed + 1) / (removed + retained + 2)
    }

    func decisions(_ bucket: LearningBucket) -> Int {
        (deleted[bucket.rawValue] ?? 0) + (kept[bucket.rawValue] ?? 0)
    }
}

struct ScoreComponents: Equatable, Sendable {
    var space = 0.0
    var certainty = 0.0
    var age = 0.0
    var quality = 0.0
    var risk = 0.0
    var preference = 0.5
}

/// Punteggio interno di recuperabilità (0…100): stabilisce cosa conviene rivedere per primo.
/// L'età pesa poco: la data di un file non prova mai che sia inutile.
struct RecoverabilityScorer: Sendable {
    var now: Date
    var largeVideoBytes: Int64
    var learner: PreferenceLearner
    private var groupKinds: [UUID: GroupKind]
    private var suggestedKeepIDs: Set<UUID>

    static let spaceWeight = 0.30
    static let certaintyWeight = 0.30
    static let ageWeight = 0.08
    static let qualityWeight = 0.14
    static let preferenceWeight = 0.18
    static let riskWeight = 0.35

    init(
        now: Date = Date(),
        largeVideoBytes: Int64 = 100 * AppConfiguration.Thresholds.megabyte,
        learner: PreferenceLearner = PreferenceLearner(),
        groups: [ItemGroup] = []
    ) {
        self.now = now
        self.largeVideoBytes = largeVideoBytes
        self.learner = learner
        var kinds: [UUID: GroupKind] = [:]
        var keeps = Set<UUID>()
        for group in groups {
            kinds[group.id] = group.kind
            if let keep = group.suggestedKeepID { keeps.insert(keep) }
        }
        self.groupKinds = kinds
        self.suggestedKeepIDs = keeps
    }

    func components(_ item: IndexedItem) -> ScoreComponents {
        var result = ScoreComponents()

        // Spazio: scala logaritmica tra 100 KB e 2 GB.
        let floorBytes = 100_000.0
        let ceilingBytes = 2.0 * Double(AppConfiguration.Thresholds.gigabyte)
        let size = Double(max(item.bytes, 1))
        if size > floorBytes {
            result.space = min(1, log10(size / floorBytes) / log10(ceilingBytes / floorBytes))
        }

        // Certezza della duplicazione: conta solo per le copie in più, non per il candidato da conservare.
        if !suggestedKeepIDs.contains(item.id) {
            if let groupID = item.duplicateGroupID, let kind = groupKinds[groupID] {
                result.certainty = kind == .exactDuplicate ? 1.0 : 0.8
            } else if let groupID = item.similarityGroupID, groupKinds[groupID] != nil {
                result.certainty = 0.45
            }
        }

        if let age = item.age(at: now), age > 0 {
            result.age = min(1, age / (3 * 365 * 86_400))
        }

        if item.traits.contains(.blank) {
            result.quality = 1.0
        } else if item.traits.contains(.blurry) {
            result.quality = 0.8
        } else if item.traits.contains(.dark) {
            result.quality = 0.7
        } else if item.traits.contains(.lowResolution) {
            result.quality = 0.4
        }

        if item.isSensitive || item.traits.contains(.favorite) {
            result.risk = 1.0
        } else if item.traits.contains(.hidden) {
            result.risk = 0.6
        } else if item.traits.contains(.edited) {
            result.risk = 0.4
        }

        let bucket = LearningBucket.bucket(for: item, largeVideoBytes: largeVideoBytes)
        result.preference = learner.affinity(bucket)
        return result
    }

    func score(_ item: IndexedItem) -> Double {
        let parts = components(item)
        let raw = Self.spaceWeight * parts.space
            + Self.certaintyWeight * parts.certainty
            + Self.ageWeight * parts.age
            + Self.qualityWeight * parts.quality
            + Self.preferenceWeight * parts.preference
            - Self.riskWeight * parts.risk
        return min(1, max(0, raw)) * 100
    }
}
