import Foundation

/// Categoria che conviene rivedere per prima.
struct Recommendation: Identifiable, Hashable, Sendable {
    let collection: SmartCollection
    let count: Int
    let bytes: Int64
    let priority: Double

    var id: String { collection.rawValue }
}

/// Sceglie le categorie con maggiore potenziale. Propone soltanto: non seleziona né elimina nulla.
enum RecommendationEngine {

    private struct Candidate {
        let collection: SmartCollection
        let bucket: LearningBucket
        /// Moltiplicatore legato alla certezza: i duplicati verificati valgono più delle somiglianze.
        let boost: Double
    }

    private static let candidates: [Candidate] = [
        Candidate(collection: .duplicatePhotos, bucket: .duplicate, boost: 1.5),
        Candidate(collection: .duplicateVideos, bucket: .duplicate, boost: 1.5),
        Candidate(collection: .duplicateFiles, bucket: .duplicate, boost: 1.5),
        Candidate(collection: .oldScreenshots, bucket: .screenshot, boost: 1.2),
        Candidate(collection: .largeVideos, bucket: .largeVideo, boost: 1.1),
        Candidate(collection: .screenRecordings, bucket: .video, boost: 1.1),
        Candidate(collection: .similarPhotos, bucket: .similar, boost: 1.0),
        Candidate(collection: .blurryPhotos, bucket: .lowQuality, boost: 1.0),
        Candidate(collection: .largeFiles, bucket: .document, boost: 0.8)
    ]

    static func recommendations(
        summary: CatalogSummary,
        learner: PreferenceLearner,
        limit: Int = 4
    ) -> [Recommendation] {
        let megabyte = Double(AppConfiguration.Thresholds.megabyte)
        var result: [Recommendation] = []

        for candidate in candidates {
            let stat = summary.stat(candidate.collection)
            guard stat.reviewableCount > 0 else { continue }
            // La priorità cresce con lo spazio (in scala logaritmica) e con le abitudini dell'utente.
            let megabytes = max(1, Double(stat.reviewableBytes) / megabyte)
            let spaceFactor = log10(megabytes + 1)
            let habitFactor = 0.5 + learner.affinity(candidate.bucket)
            let priority = spaceFactor * habitFactor * candidate.boost
            result.append(Recommendation(
                collection: candidate.collection,
                count: stat.reviewableCount,
                bytes: stat.reviewableBytes,
                priority: priority
            ))
        }

        return Array(result.sorted { $0.priority > $1.priority }.prefix(max(0, limit)))
    }

    /// Frase mostrata nella Home, es. "Ti consiglio di cominciare con 800 screenshot vecchi e 24 video grandi…".
    static func headline(for recommendations: [Recommendation], hasIndexedContent: Bool) -> String {
        guard hasIndexedContent else {
            return "Avvia un'analisi per ricevere suggerimenti su cosa rivedere per primo."
        }
        guard let first = recommendations.first else {
            return "Al momento nessuna categoria richiede una revisione urgente."
        }
        let firstPhrase = phrase(for: first.collection, count: first.count)
        guard recommendations.count > 1 else {
            return "Ti consiglio di cominciare con \(firstPhrase), perché è la categoria che merita maggiormente una revisione."
        }
        let secondPhrase = phrase(for: recommendations[1].collection, count: recommendations[1].count)
        return "Ti consiglio di cominciare con \(firstPhrase) e \(secondPhrase), perché sono le categorie che meritano maggiormente una revisione."
    }

    static func phrase(for collection: SmartCollection, count: Int) -> String {
        let number = Format.count(count)
        let one = count == 1
        switch collection {
        case .duplicatePhotos: return one ? "1 foto duplicata" : "\(number) foto duplicate"
        case .duplicateVideos: return one ? "1 video duplicato" : "\(number) video duplicati"
        case .duplicateFiles: return one ? "1 file duplicato" : "\(number) file duplicati"
        case .oldScreenshots: return one ? "1 screenshot vecchio" : "\(number) screenshot vecchi"
        case .screenshots: return "\(number) screenshot"
        case .largeVideos: return one ? "1 video grande" : "\(number) video grandi"
        case .screenRecordings: return one ? "1 registrazione dello schermo" : "\(number) registrazioni dello schermo"
        case .similarPhotos: return one ? "1 foto simile" : "\(number) foto simili"
        case .blurryPhotos: return one ? "1 foto sfocata" : "\(number) foto sfocate"
        case .largeFiles: return one ? "1 file pesante" : "\(number) file pesanti"
        default: return one ? "1 elemento in \(collection.title)" : "\(number) elementi in \(collection.title)"
        }
    }
}
