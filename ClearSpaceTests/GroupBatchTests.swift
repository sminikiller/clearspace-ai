import XCTest
@testable import ClearSpace

/// Più gruppi decisi insieme, elenchi che non si riordinano sotto il dito, la regola che separa lo
/// scorrimento dalla selezione e lo scorrimento automatico vicino ai bordi.
final class GroupBatchTests: XCTestCase {

    // MARK: - Tutti i gruppi in una volta

    func testEachGroupKeepsItsBestAndProposesTheOthers() throws {
        let best = TestData.item(bytes: 3_000_000)
        let second = TestData.item(bytes: 2_000_000)
        let third = TestData.item(bytes: 1_000_000)
        let groupID = UUID()
        let plans = GroupBatch.plans(
            for: [GroupBatch.Candidate(groupID: groupID, members: [best, second, third], suggestedID: best.id)],
            isLocked: { _ in false }
        )
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.groupID, groupID)
        XCTAssertEqual(plan.keep, [best.id])
        XCTAssertEqual(plan.delete, [second.id, third.id])
        XCTAssertEqual(plan.deleteBytes, 3_000_000)
    }

    func testStarsWinAndLockedItemsAreNeverDeleted() throws {
        var starred = TestData.item(status: .kept)
        starred.starredAt = TestData.now
        let suggested = TestData.item()
        let locked = TestData.item()
        let plans = GroupBatch.plans(
            for: [GroupBatch.Candidate(groupID: UUID(), members: [starred, suggested, locked], suggestedID: suggested.id)],
            isLocked: { $0.id == locked.id }
        )
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.delete, [suggested.id], "Con una stella resta quella; la protetta non si tocca")
        XCTAssertEqual(Set(plan.keep), [starred.id, locked.id])
    }

    func testGroupsWithoutAChoiceOrAlreadyDecidedAreLeftOut() {
        // Senza stelle e senza consiglio la scelta va fatta a mano.
        let noAdvice = GroupBatch.Candidate(groupID: UUID(), members: [TestData.item(), TestData.item()], suggestedID: nil)
        // Già deciso: nulla da fare.
        let kept = TestData.item(status: .kept)
        let marked = TestData.item(status: .markedForDeletion)
        let decided = GroupBatch.Candidate(groupID: UUID(), members: [kept, marked], suggestedID: kept.id)
        // Un solo membro non è un gruppo.
        let lonely = TestData.item()
        let single = GroupBatch.Candidate(groupID: UUID(), members: [lonely], suggestedID: lonely.id)
        XCTAssertTrue(GroupBatch.plans(for: [noAdvice, decided, single], isLocked: { _ in false }).isEmpty)
    }

    func testAGroupIsNeverEmptiedCompletely() {
        // Il consiglio era già stato proposto per l'eliminazione: la proposta eliminerebbe tutto.
        let suggested = TestData.item(status: .markedForDeletion)
        let other = TestData.item()
        let candidate = GroupBatch.Candidate(groupID: UUID(), members: [suggested, other], suggestedID: other.id)
        let plans = GroupBatch.plans(for: [candidate], isLocked: { _ in false })
        XCTAssertEqual(plans.first?.keep, [other.id])

        let alone = TestData.item(status: .markedForDeletion)
        let pending = TestData.item()
        let everything = GroupBatch.Candidate(groupID: UUID(), members: [alone, pending], suggestedID: alone.id)
        XCTAssertTrue(GroupBatch.plans(for: [everything], isLocked: { _ in false }).allSatisfy { !$0.keep.isEmpty })
    }

    func testTotalsSkipExcludedGroups() {
        let first = GroupBatch.Plan(groupID: UUID(), keep: [UUID()], delete: [UUID(), UUID()], deleteBytes: 500)
        let second = GroupBatch.Plan(groupID: UUID(), keep: [UUID()], delete: [UUID()], deleteBytes: 200)
        XCTAssertEqual(GroupBatch.totals([first, second], excluding: []), GroupBatch.Totals(groups: 2, items: 3, bytes: 700))
        XCTAssertEqual(GroupBatch.totals([first, second], excluding: [first.groupID]), GroupBatch.Totals(groups: 1, items: 1, bytes: 200))
    }

    // MARK: - Elenchi stabili

    func testTheShownOrderSurvivesAnUpdate() {
        let shown = ["a", "b", "c"]
        // L'analisi ha cambiato l'ordine, tolto «b» e aggiunto «d» ed «e».
        let fresh = ["e", "c", "a", "d"]
        XCTAssertEqual(StableOrder.merge(fresh, keeping: shown, id: { $0 }), ["a", "c", "e", "d"])
        // Al primo caricamento vale l'ordine ricevuto.
        XCTAssertEqual(StableOrder.merge(fresh, keeping: [String](), id: { $0 }), fresh)
    }

    func testListsRefreshAtMostEveryFewSecondsDuringAScan() {
        let last = TestData.now
        XCTAssertEqual(ScanThrottle.wait(since: last, now: last.addingTimeInterval(1)), ScanThrottle.interval - 1, accuracy: 0.001)
        XCTAssertEqual(ScanThrottle.wait(since: last, now: last.addingTimeInterval(60)), 0)
    }

    // MARK: - Scorrere o selezionare

    func testOnlyAClearlySidewaysMoveOnAStillGridSelects() {
        XCTAssertTrue(GridDragIntent.startsSelection(translation: CGSize(width: 11, height: 3), contentIsMoving: false))
        XCTAssertTrue(GridDragIntent.startsSelection(translation: CGSize(width: -11, height: -2), contentIsMoving: false))
        // Pollice che scorre: anche molto storto, resta più verticale che orizzontale.
        XCTAssertFalse(GridDragIntent.startsSelection(translation: CGSize(width: 6, height: 9), contentIsMoving: false))
        XCTAssertFalse(GridDragIntent.startsSelection(translation: CGSize(width: 10, height: 6), contentIsMoving: false))
        // La griglia si sta ancora muovendo: si scorre.
        XCTAssertFalse(GridDragIntent.startsSelection(translation: CGSize(width: 12, height: 0), contentIsMoving: true))
        XCTAssertFalse(GridDragIntent.startsSelection(translation: .zero, contentIsMoving: false))
    }

    func testAutoScrollSpeedsUpNearTheEdges() {
        let top: CGFloat = 100
        let bottom: CGFloat = 700
        XCTAssertEqual(GridAutoScroll.speed(finger: 400, top: top, bottom: bottom), 0)
        let nearTop = GridAutoScroll.speed(finger: top + 10, top: top, bottom: bottom)
        let atTop = GridAutoScroll.speed(finger: top - 20, top: top, bottom: bottom)
        XCTAssertLessThan(nearTop, 0)
        XCTAssertLessThan(atTop, nearTop, "Più il dito è vicino al bordo, più si scorre veloci")
        XCTAssertEqual(atTop, -GridAutoScroll.maximumSpeed)
        let nearBottom = GridAutoScroll.speed(finger: bottom - 10, top: top, bottom: bottom)
        XCTAssertGreaterThan(nearBottom, GridAutoScroll.minimumSpeed - 1)
        XCTAssertEqual(GridAutoScroll.speed(finger: bottom + 50, top: top, bottom: bottom), GridAutoScroll.maximumSpeed)
        XCTAssertEqual(GridAutoScroll.speed(finger: 400, top: 500, bottom: 300), 0)
    }

    // MARK: - Esito dell'eliminazione diretta

    func testTheOutcomeSentenceMatchesWhatHappened() {
        var result = DirectDeletionResult(outcome: .deleted, deletedCount: 3)
        XCTAssertEqual(result.summary(isImage: true, isVideo: false), "Eliminate 3 foto.")
        result.deletedCount = 1
        XCTAssertEqual(result.summary(isImage: false, isVideo: true), "Eliminato 1 video.")
        result.deletedCount = 2
        result.failedCount = 1
        result.blockedCount = 2
        let sentence = result.summary(isImage: false, isVideo: false)
        XCTAssertTrue(sentence.hasPrefix("Eliminati 2 elementi."))
        XCTAssertTrue(sentence.contains("Revisione"))
        XCTAssertTrue(sentence.contains("protetti"))
    }
}
