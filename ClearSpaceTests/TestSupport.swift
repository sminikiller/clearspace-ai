import Foundation
@testable import ClearSpace

/// Dati di prova condivisi dai test.
enum TestData {

    /// Istante fisso (15 gennaio 2027, UTC): i test non dipendono dalla data di esecuzione.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }

    static func item(
        source: StorageSource = .photoLibrary,
        category: ContentCategory = .photo,
        bytes: Int64 = 2_000_000,
        ageDays: Double = 10,
        traits: ItemTraits = [],
        status: ReviewStatus = .unreviewed,
        filename: String? = nil
    ) -> IndexedItem {
        var item = IndexedItem(
            sourceIdentifier: UUID().uuidString,
            source: source,
            category: category,
            filename: filename,
            createdAt: now.addingTimeInterval(-ageDays * 86_400),
            estimatedBytes: bytes,
            traits: traits
        )
        item.reviewStatus = status
        return item
    }

    static func context(largeVideoBytes: Int64 = 100_000_000) -> CollectionContext {
        CollectionContext(now: now, largeVideoBytes: largeVideoBytes)
    }

    static func plannerInput(
        items: [IndexedItem],
        groups: [ItemGroup] = [],
        rules: ProtectionRules = ProtectionRules()
    ) -> PlannerInput {
        PlannerInput(
            items: items,
            groups: groups,
            evaluator: ProtectionEvaluator(rules: rules),
            scorer: RecoverabilityScorer(now: now, largeVideoBytes: 100_000_000, groups: groups),
            context: context()
        )
    }
}
