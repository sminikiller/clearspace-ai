import XCTest
@testable import ClearSpace

final class CleanupSessionTests: XCTestCase {

    func testRecordingAdvancesAndUndoRestoresThePreviousItem() {
        let ids = [UUID(), UUID(), UUID()]
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)

        session.record(.delete, previousStatus: .unreviewed, bytes: 10)
        session.record(.keep, previousStatus: .unreviewed, bytes: 20)

        XCTAssertEqual(session.cursor, 2)
        XCTAssertEqual(session.currentItemID, ids[2])
        XCTAssertEqual(session.markedCount, 1)
        XCTAssertEqual(session.keptCount, 1)
        XCTAssertEqual(session.markedBytes, 10)

        let undone = session.undoLast()
        XCTAssertEqual(undone?.itemID, ids[1])
        XCTAssertEqual(undone?.previousStatus, .unreviewed)
        XCTAssertEqual(session.cursor, 1)
        XCTAssertEqual(session.keptCount, 0)
        XCTAssertEqual(session.currentItemID, ids[1])
    }

    func testUndoOnAnEmptySessionDoesNothing() {
        var session = CleanupSession(title: "Prova", mode: .quick, queue: [UUID()], now: TestData.now)
        XCTAssertNil(session.undoLast())
        XCTAssertEqual(session.cursor, 0)
    }

    func testPostponedItemsCanBeReviewedAgain() {
        let ids = [UUID(), UUID()]
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)
        session.record(.postpone, previousStatus: .unreviewed, bytes: 5)
        session.record(.keep, previousStatus: .unreviewed, bytes: 5)

        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.postponedIDs, [ids[0]])

        session.requeuePostponed()
        XCTAssertFalse(session.isFinished)
        XCTAssertEqual(session.currentItemID, ids[0])
        XCTAssertEqual(session.postponedCount, 0)
    }

    func testGoalProgressFollowsTheSpaceOfProposedItems() {
        var session = CleanupSession(
            title: "Obiettivo",
            mode: .goal(targetBytes: 100),
            queue: [UUID(), UUID(), UUID()],
            goalBytes: 100,
            now: TestData.now
        )
        session.record(.delete, previousStatus: .unreviewed, bytes: 40)
        XCTAssertEqual(session.goalProgress ?? 0, 0.4, accuracy: 0.001)
        XCTAssertFalse(session.goalReached)

        session.record(.keep, previousStatus: .unreviewed, bytes: 500)
        session.record(.delete, previousStatus: .unreviewed, bytes: 70)
        XCTAssertTrue(session.goalReached)
    }

    func testSessionSurvivesSavingAndLoading() throws {
        var session = CleanupSession(
            title: "Pulizia annuale 2022",
            mode: .annual(year: 2022),
            queue: [UUID(), UUID()],
            now: TestData.now
        )
        session.record(.delete, previousStatus: .postponed, bytes: 123, at: TestData.now)

        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(CleanupSession.self, from: data)
        XCTAssertEqual(restored, session)
    }
}

final class NaturalLanguageQueryParserTests: XCTestCase {

    private var parser: NaturalLanguageQueryParser {
        NaturalLanguageQueryParser(now: TestData.now, calendar: TestData.utcCalendar)
    }

    func testOldScreenshotsWithText() {
        let parsed = parser.parse("Mostrami tutti gli screenshot più vecchi di un anno che contengono testo.")

        XCTAssertEqual(parsed.filter.categories, [.photo])
        XCTAssertTrue(parsed.filter.requiredTraits.contains(.screenshot))
        XCTAssertTrue(parsed.filter.requiredTraits.contains(.hasText))
        XCTAssertEqual(
            parsed.filter.createdBefore,
            TestData.utcCalendar.date(byAdding: .year, value: -1, to: TestData.now)
        )
        XCTAssertTrue(parsed.filter.textTokens.isEmpty)
        XCTAssertTrue(parsed.understoodSomething)
    }

    func testHeaviestVideosOfAYear() {
        let parsed = parser.parse("Trova i video più pesanti girati nel 2024.")

        XCTAssertEqual(parsed.filter.categories, [.video])
        XCTAssertEqual(parsed.filter.year, 2024)
        XCTAssertEqual(parsed.filter.sort, .sizeDescending)
        XCTAssertTrue(parsed.filter.textTokens.isEmpty)
    }

    func testLimitAndSize() {
        let limited = parser.parse("I 20 video più pesanti")
        XCTAssertEqual(limited.filter.limit, 20)
        XCTAssertEqual(limited.filter.categories, [.video])

        let sized = parser.parse("PDF oltre 10 MB")
        XCTAssertEqual(sized.filter.categories, [.pdf])
        XCTAssertEqual(sized.filter.minBytes, 10_000_000)
    }

    func testRecentPeriodAndQualityTraits() {
        let parsed = parser.parse("Foto sfocate degli ultimi 6 mesi")

        XCTAssertEqual(parsed.filter.categories, [.photo])
        XCTAssertTrue(parsed.filter.anyTraits.contains(.blurry))
        XCTAssertEqual(
            parsed.filter.createdAfter,
            TestData.utcCalendar.date(byAdding: .month, value: -6, to: TestData.now)
        )
    }

    func testUnknownWordsBecomeTextSearch() {
        let parsed = parser.parse("riunione di gennaio")

        XCTAssertEqual(parsed.filter.month, 1)
        XCTAssertEqual(parsed.filter.textTokens, ["riunione"])
    }

    func testQuotedPhraseIsSearchedLiterally() {
        let parsed = parser.parse("documenti con \"codice cliente\"")

        XCTAssertTrue(parsed.filter.textTokens.contains("codice cliente"))
        XCTAssertTrue(parsed.filter.categories.contains(.pdf))
    }

    func testAudioRecordingsAreNotConfusedWithScreenRecordings() {
        let audio = parser.parse("registrazioni audio di gennaio")
        XCTAssertEqual(audio.filter.categories, [.audio])

        let screen = parser.parse("registrazioni dello schermo")
        XCTAssertEqual(screen.filter.categories, [.video])
        XCTAssertTrue(screen.filter.requiredTraits.contains(.screenRecording))
    }
}

final class ItemFilterTests: XCTestCase {

    func testFilterCombinesSizeYearAndText() {
        var screenshot = TestData.item(bytes: 3_000_000, ageDays: 200, traits: [.screenshot, .hasText])
        screenshot.textContent = "Totale ordine 42"
        let small = TestData.item(bytes: 100_000, ageDays: 200)
        let other = TestData.item(bytes: 3_000_000, ageDays: 600)

        var filter = ItemFilter()
        filter.minBytes = 1_000_000
        filter.year = 2026
        filter.textTokens = ["ordine"]

        let calendar = TestData.utcCalendar
        XCTAssertTrue(filter.matches(screenshot, calendar: calendar))
        XCTAssertFalse(filter.matches(small, calendar: calendar))
        XCTAssertFalse(filter.matches(other, calendar: calendar))
    }

    func testProtectedItemsCanBeExcluded() {
        let favorite = TestData.item(traits: [.favorite])
        var filter = ItemFilter()
        filter.includeProtected = false

        XCTAssertFalse(filter.matches(favorite, evaluator: ProtectionEvaluator()))
        filter.includeProtected = true
        XCTAssertTrue(filter.matches(favorite, evaluator: ProtectionEvaluator()))
    }

    func testSortingAndLimit() {
        let items = [
            TestData.item(bytes: 10),
            TestData.item(bytes: 30),
            TestData.item(bytes: 20)
        ]
        var filter = ItemFilter()
        filter.sort = .sizeDescending
        filter.limit = 2

        XCTAssertEqual(filter.apply(to: items).map { $0.bytes }, [30, 20])
    }
}
