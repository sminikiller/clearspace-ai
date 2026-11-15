import Foundation

/// Conteggi di una categoria: totale e parte ancora da rivedere (non protetta e non decisa).
struct CollectionStat: Equatable, Sendable {
    var count = 0
    var bytes: Int64 = 0
    var reviewableCount = 0
    var reviewableBytes: Int64 = 0

    mutating func add(_ item: IndexedItem, reviewable: Bool) {
        count += 1
        bytes += item.bytes
        if reviewable {
            reviewableCount += 1
            reviewableBytes += item.bytes
        }
    }
}

/// Spazio potenzialmente recuperabile, suddiviso come nella dashboard.
/// È una stima sui contenuti analizzati, non spazio già liberato.
struct PotentialBreakdown: Equatable, Sendable {
    var photoDuplicatesAndSimilar: Int64 = 0
    var bulkyVideos: Int64 = 0
    var screenshotsAndDocuments: Int64 = 0

    var total: Int64 {
        photoDuplicatesAndSimilar + bulkyVideos + screenshotsAndDocuments
    }
}

/// Riepilogo dell'indice, ricalcolato fuori dal thread principale dopo scansioni e decisioni.
struct CatalogSummary: Sendable {
    var totalCount = 0
    var totalBytes: Int64 = 0
    var collections: [SmartCollection: CollectionStat] = [:]
    var sources: [StorageSource: CollectionStat] = [:]
    var years: [Int: CollectionStat] = [:]
    var analysis: [AnalysisStatus: Int] = [:]
    var review: [ReviewStatus: Int] = [:]
    var potential = PotentialBreakdown()
    var protectedCount = 0
    var markedCount = 0
    var markedBytes: Int64 = 0
    var markedDeviceBytes: Int64 = 0
    /// Dimensione degli elementi della libreria Foto analizzati.
    var libraryBytes: Int64 = 0
    /// Parte della libreria il cui originale risulta presente solo su iCloud.
    var cloudOnlyLibraryBytes: Int64 = 0

    static let empty = CatalogSummary()

    func stat(_ collection: SmartCollection) -> CollectionStat {
        collections[collection] ?? CollectionStat()
    }

    func stat(_ source: StorageSource) -> CollectionStat {
        sources[source] ?? CollectionStat()
    }

    /// Anni presenti nell'indice, dal più recente.
    var sortedYears: [Int] {
        years.keys.sorted(by: >)
    }

    /// Quota degli elementi per cui l'analisi delle anteprime è stata completata.
    var analysisProgress: Double {
        guard totalCount > 0 else { return 0 }
        let pending = analysis[.metadataOnly] ?? 0
        return Double(totalCount - pending) / Double(totalCount)
    }

    static func compute(
        items: [IndexedItem],
        groups: [ItemGroup],
        evaluator: ProtectionEvaluator,
        context: CollectionContext,
        calendar: Calendar = .current
    ) -> CatalogSummary {
        var summary = CatalogSummary()
        let allCollections = SmartCollection.allCases
        var itemsByID: [UUID: IndexedItem] = [:]
        itemsByID.reserveCapacity(items.count)
        var reviewableIDs = Set<UUID>()

        for item in items {
            itemsByID[item.id] = item
            let blocked = evaluator.blockReason(for: item) != nil
            let reviewable = item.isPendingReview && !blocked
            if reviewable { reviewableIDs.insert(item.id) }
            if blocked { summary.protectedCount += 1 }

            summary.totalCount += 1
            summary.totalBytes += item.bytes
            summary.sources[item.source, default: CollectionStat()].add(item, reviewable: reviewable)
            summary.analysis[item.analysisStatus, default: 0] += 1
            summary.review[item.reviewStatus, default: 0] += 1

            if let date = item.createdAt {
                let year = calendar.component(.year, from: date)
                summary.years[year, default: CollectionStat()].add(item, reviewable: reviewable)
            }

            for collection in allCollections where collection.contains(item, context: context) {
                summary.collections[collection, default: CollectionStat()].add(item, reviewable: reviewable)
            }

            if item.reviewStatus.isQueuedForDeletion {
                summary.markedCount += 1
                summary.markedBytes += item.bytes
                summary.markedDeviceBytes += item.deviceBytes
            }

            if item.source == .photoLibrary {
                summary.libraryBytes += item.bytes
                if item.traits.contains(.cloudOnly) {
                    summary.cloudOnlyLibraryBytes += item.bytes
                }
            }
        }

        // Potenziale di recupero: ogni elemento viene contato una sola volta.
        var counted = Set<UUID>()

        for group in groups {
            let members = group.memberIDs.compactMap { itemsByID[$0] }
            guard members.count >= 2 else { continue }
            let keepID = group.suggestedKeepID ?? members.max(by: { $0.bytes < $1.bytes })?.id
            for member in members where member.id != keepID {
                guard reviewableIDs.contains(member.id), !counted.contains(member.id) else { continue }
                counted.insert(member.id)
                switch member.category {
                case .photo:
                    summary.potential.photoDuplicatesAndSimilar += member.bytes
                case .video:
                    summary.potential.bulkyVideos += member.bytes
                default:
                    summary.potential.screenshotsAndDocuments += member.bytes
                }
            }
        }

        for item in items {
            guard reviewableIDs.contains(item.id), !counted.contains(item.id) else { continue }
            if SmartCollection.largeVideos.contains(item, context: context)
                || SmartCollection.screenRecordings.contains(item, context: context) {
                counted.insert(item.id)
                summary.potential.bulkyVideos += item.bytes
            } else if SmartCollection.oldScreenshots.contains(item, context: context) {
                counted.insert(item.id)
                summary.potential.screenshotsAndDocuments += item.bytes
            }
        }

        return summary
    }
}
