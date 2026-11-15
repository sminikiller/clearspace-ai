import XCTest
@testable import ClearSpace

final class RecoverabilityScorerTests: XCTestCase {

    func testAgeAloneDoesNotMakeAnItemASuggestion() {
        let scorer = RecoverabilityScorer(now: TestData.now)
        let oldPhoto = TestData.item(bytes: 2_000_000, ageDays: 5 * 365)

        // Una foto vecchia, senza altri segnali, resta in fondo alle priorità.
        XCTAssertLessThan(scorer.score(oldPhoto), 30)
    }

    func testVerifiedDuplicateCopyRanksHighAndTheKeptCopyDoesNot() {
        var original = TestData.item(category: .video, bytes: 50_000_000)
        var copy = TestData.item(category: .video, bytes: 50_000_000)
        let group = ItemGroup(
            kind: .exactDuplicate,
            scope: .photoLibrary,
            memberIDs: [original.id, copy.id],
            suggestedKeepID: original.id
        )
        original.duplicateGroupID = group.id
        copy.duplicateGroupID = group.id
        let scorer = RecoverabilityScorer(now: TestData.now, groups: [group])

        XCTAssertGreaterThan(scorer.score(copy), 50)
        XCTAssertLessThan(scorer.score(original), scorer.score(copy))
    }

    func testSensitiveContentIsPushedDown() {
        let scorer = RecoverabilityScorer(now: TestData.now)
        let plain = TestData.item(bytes: 8_000_000, traits: [.screenshot])
        let receipt = TestData.item(bytes: 8_000_000, traits: [.screenshot, .receipt])

        XCTAssertLessThan(scorer.score(receipt), scorer.score(plain))
    }

    func testLearnerOnlyShiftsPriorities() {
        var learner = PreferenceLearner()
        XCTAssertEqual(learner.affinity(.screenshot), 0.5, accuracy: 0.0001)

        for _ in 0..<8 {
            learner.record(.delete, bucket: .screenshot)
        }
        XCTAssertEqual(learner.affinity(.screenshot), 0.9, accuracy: 0.0001)

        learner.revert(.delete, bucket: .screenshot)
        XCTAssertEqual(learner.decisions(.screenshot), 7)

        let screenshot = TestData.item(traits: [.screenshot])
        let neutral = RecoverabilityScorer(now: TestData.now)
        let trained = RecoverabilityScorer(now: TestData.now, learner: learner)
        XCTAssertGreaterThan(trained.score(screenshot), neutral.score(screenshot))
    }
}

final class CleanupPlannerTests: XCTestCase {

    private struct Fixture {
        let original: IndexedItem
        let duplicate: IndexedItem
        let largeVideo: IndexedItem
        let protectedVideo: IndexedItem
        let oldScreenshot: IndexedItem
        let recentScreenshot: IndexedItem
        let group: ItemGroup

        var items: [IndexedItem] {
            [original, duplicate, largeVideo, protectedVideo, oldScreenshot, recentScreenshot]
        }
    }

    private func makeFixture() -> Fixture {
        var original = TestData.item(bytes: 4_000_000, ageDays: 300)
        var duplicate = TestData.item(bytes: 4_000_000, ageDays: 100)
        let group = ItemGroup(
            kind: .exactDuplicate,
            scope: .photoLibrary,
            memberIDs: [original.id, duplicate.id],
            suggestedKeepID: original.id
        )
        original.duplicateGroupID = group.id
        duplicate.duplicateGroupID = group.id

        return Fixture(
            original: original,
            duplicate: duplicate,
            largeVideo: TestData.item(category: .video, bytes: 200_000_000),
            protectedVideo: TestData.item(category: .video, bytes: 900_000_000, traits: [.favorite]),
            oldScreenshot: TestData.item(bytes: 1_000_000, ageDays: 400, traits: [.screenshot]),
            recentScreenshot: TestData.item(bytes: 1_000_000, ageDays: 20, traits: [.screenshot]),
            group: group
        )
    }

    func testQuickQueueProposesDuplicatesLargeVideosAndOldScreenshots() {
        let fixture = makeFixture()
        let input = TestData.plannerInput(items: fixture.items, groups: [fixture.group])
        let queue = Set(CleanupPlanner.quickQueue(input, limit: 50))

        XCTAssertEqual(queue, [fixture.duplicate.id, fixture.largeVideo.id, fixture.oldScreenshot.id])
    }

    func testQuickQueueRespectsTheSessionLimit() {
        let fixture = makeFixture()
        let input = TestData.plannerInput(items: fixture.items, groups: [fixture.group])

        XCTAssertEqual(CleanupPlanner.quickQueue(input, limit: 2).count, 2)
    }

    func testDecidedItemsAreNotProposedAgain() {
        var fixture = makeFixture()
        var kept = fixture.largeVideo
        kept.reviewStatus = .kept
        fixture = Fixture(
            original: fixture.original,
            duplicate: fixture.duplicate,
            largeVideo: kept,
            protectedVideo: fixture.protectedVideo,
            oldScreenshot: fixture.oldScreenshot,
            recentScreenshot: fixture.recentScreenshot,
            group: fixture.group
        )
        let input = TestData.plannerInput(items: fixture.items, groups: [fixture.group])

        XCTAssertFalse(CleanupPlanner.quickQueue(input, limit: 50).contains(kept.id))
    }

    func testCollectionQueueSkipsProtectedItems() {
        let fixture = makeFixture()
        let input = TestData.plannerInput(items: fixture.items, groups: [fixture.group])
        let queue = CleanupPlanner.queue(for: .allVideos, input, sort: .sizeDescending)

        XCTAssertEqual(queue, [fixture.largeVideo.id])
    }

    func testAnnualQueueIsChronological() {
        let march = TestData.item(ageDays: 300)
        let july = TestData.item(ageDays: 190)
        let previousYear = TestData.item(ageDays: 600)
        let input = TestData.plannerInput(items: [july, previousYear, march])
        let queue = CleanupPlanner.annualQueue(year: 2026, input, calendar: TestData.utcCalendar)

        XCTAssertEqual(queue, [march.id, july.id])
    }

    func testGoalQueueStopsAfterCoveringTheTargetWithMargin() {
        let items = (0..<10).map { _ in TestData.item(category: .video, bytes: 100_000_000) }
        let input = TestData.plannerInput(items: items)
        let queue = CleanupPlanner.goalQueue(targetBytes: 150_000_000, input)

        // Il margine è il doppio dell'obiettivo: 300 MB, cioè tre video da 100 MB.
        XCTAssertEqual(queue.count, 3)
    }

    func testGuidedStepsWithoutSwipeHaveNoQueue() {
        let fixture = makeFixture()
        let input = TestData.plannerInput(items: fixture.items, groups: [fixture.group])

        XCTAssertTrue(CleanupPlanner.guidedQueue(.otherApps, input).isEmpty)
        XCTAssertTrue(CleanupPlanner.guidedQueue(.iCloud, input).isEmpty)
        XCTAssertEqual(
            Set(CleanupPlanner.guidedQueue(.screenshots, input)),
            [fixture.oldScreenshot.id, fixture.recentScreenshot.id]
        )
    }
}

final class CatalogSummaryTests: XCTestCase {

    func testCollectionsSeparateOldAndRecentScreenshots() {
        let old = TestData.item(ageDays: 400, traits: [.screenshot])
        let recent = TestData.item(ageDays: 20, traits: [.screenshot])
        let context = TestData.context()

        XCTAssertTrue(SmartCollection.oldScreenshots.contains(old, context: context))
        XCTAssertFalse(SmartCollection.oldScreenshots.contains(recent, context: context))
        XCTAssertTrue(SmartCollection.recentScreenshots.contains(recent, context: context))
        XCTAssertTrue(SmartCollection.screenshots.contains(old, context: context))
    }

    func testPotentialSpaceNeverCountsAnItemTwice() {
        var original = TestData.item(category: .video, bytes: 200_000_000)
        var copy = TestData.item(category: .video, bytes: 200_000_000)
        let group = ItemGroup(
            kind: .exactDuplicate,
            scope: .photoLibrary,
            memberIDs: [original.id, copy.id],
            suggestedKeepID: original.id
        )
        original.duplicateGroupID = group.id
        copy.duplicateGroupID = group.id

        // La copia è sia un duplicato sia un video grande; l'originale è un video grande.
        let summary = CatalogSummary.compute(
            items: [original, copy],
            groups: [group],
            evaluator: ProtectionEvaluator(),
            context: TestData.context(),
            calendar: TestData.utcCalendar
        )

        XCTAssertEqual(summary.potential.total, 400_000_000)
        XCTAssertEqual(summary.potential.bulkyVideos, 400_000_000)
        XCTAssertEqual(summary.stat(.duplicateVideos).count, 2)
        XCTAssertEqual(summary.totalBytes, 400_000_000)
    }

    func testProtectedAndDecidedItemsAreNotPotentialSpace() {
        let favorite = TestData.item(category: .video, bytes: 500_000_000, traits: [.favorite])
        let kept = TestData.item(category: .video, bytes: 300_000_000, status: .kept)
        let marked = TestData.item(category: .video, bytes: 150_000_000, status: .markedForDeletion)
        let summary = CatalogSummary.compute(
            items: [favorite, kept, marked],
            groups: [],
            evaluator: ProtectionEvaluator(),
            context: TestData.context(),
            calendar: TestData.utcCalendar
        )

        XCTAssertEqual(summary.potential.total, 0)
        XCTAssertEqual(summary.protectedCount, 1)
        XCTAssertEqual(summary.markedCount, 1)
        XCTAssertEqual(summary.markedBytes, 150_000_000)
        XCTAssertEqual(summary.stat(.allVideos).reviewableCount, 0)
    }

    func testRecommendationHeadline() {
        XCTAssertTrue(
            RecommendationEngine.headline(for: [], hasIndexedContent: false).contains("analisi")
        )

        let screenshots = (0..<12).map { _ in TestData.item(bytes: 3_000_000, ageDays: 500, traits: [.screenshot]) }
        let videos = (0..<3).map { _ in TestData.item(category: .video, bytes: 400_000_000) }
        let summary = CatalogSummary.compute(
            items: screenshots + videos,
            groups: [],
            evaluator: ProtectionEvaluator(),
            context: TestData.context(),
            calendar: TestData.utcCalendar
        )
        let recommendations = RecommendationEngine.recommendations(summary: summary, learner: PreferenceLearner())
        let headline = RecommendationEngine.headline(for: recommendations, hasIndexedContent: true)

        XCTAssertEqual(Set(recommendations.map { $0.collection }), [.oldScreenshots, .largeVideos])
        XCTAssertTrue(headline.contains("12 screenshot vecchi"))
        XCTAssertTrue(headline.contains("3 video grandi"))
    }
}

final class TripDetectorTests: XCTestCase {

    func testTripFarFromHomeIsDetected() {
        var items: [IndexedItem] = []
        // Trenta foto nella zona abituale, distribuite in molti mesi.
        for index in 0..<30 {
            var item = TestData.item(ageDays: 400 - Double(index) * 3)
            item.latitude = 42.46
            item.longitude = 14.21
            items.append(item)
        }
        // Quindici foto scattate in tre giorni a circa 500 km di distanza.
        var tripIDs = Set<UUID>()
        for index in 0..<15 {
            var item = TestData.item(ageDays: 100 - Double(index) * 0.2)
            item.latitude = 45.46
            item.longitude = 9.19
            items.append(item)
            tripIDs.insert(item.id)
        }

        let trips = TripDetector.detect(items: items)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(Set(trips.first?.itemIDs ?? []), tripIDs)
        XCTAssertGreaterThan(trips.first?.distanceFromHomeKm ?? 0, 300)
    }

    func testNoLocationMeansNoTrips() {
        let items = (0..<20).map { index in TestData.item(ageDays: Double(index)) }
        XCTAssertTrue(TripDetector.detect(items: items).isEmpty)
    }

    func testDistanceBetweenKnownCities() {
        // Tra i due punti la formula dell'emisenoverso dà circa 522 km.
        let distance = TripDetector.distanceKm(latitude1: 42.46, longitude1: 14.21, latitude2: 45.46, longitude2: 9.19)
        XCTAssertEqual(distance, 522, accuracy: 15)
    }
}
