import XCTest
@testable import ClearSpace

/// Galleria di un gruppo (proposta iniziale e scelte a mano), trascinamento sulle griglie e
/// pagine dell'anteprima a tutto schermo.
final class GroupDecisionTests: XCTestCase {

    // MARK: - Proposta della galleria

    func testTheBestStaysAndTheOthersAreProposed() {
        let best = TestData.item()
        let second = TestData.item()
        let third = TestData.item()
        let proposal = GroupProposal.initialDeletion(
            members: [best, second, third],
            suggestedID: best.id,
            isLocked: { _ in false }
        )
        XCTAssertEqual(proposal, [second.id, third.id])
    }

    func testStarsWinOverTheSuggestion() {
        var starred = TestData.item(status: .kept)
        starred.starredAt = TestData.now
        let suggested = TestData.item()
        let other = TestData.item()
        let proposal = GroupProposal.initialDeletion(
            members: [starred, suggested, other],
            suggestedID: suggested.id,
            isLocked: { _ in false }
        )
        // Con una stella resta quella: anche la consigliata è proposta.
        XCTAssertEqual(proposal, [suggested.id, other.id])
    }

    func testEarlierDecisionsAndLockedItemsAreRespected() {
        let suggested = TestData.item()
        let kept = TestData.item(status: .kept)
        let marked = TestData.item(status: .markedForDeletion)
        let locked = TestData.item()
        let proposal = GroupProposal.initialDeletion(
            members: [suggested, kept, marked, locked],
            suggestedID: suggested.id,
            isLocked: { $0.id == locked.id }
        )
        // Conservata resta, proposta resta proposta, la protetta non si tocca.
        XCTAssertEqual(proposal, [marked.id])
    }

    func testWithoutStarsOrSuggestionNothingIsProposed() {
        let first = TestData.item()
        let second = TestData.item(status: .postponed)
        let proposal = GroupProposal.initialDeletion(members: [first, second], suggestedID: nil, isLocked: { _ in false })
        XCTAssertTrue(proposal.isEmpty)
    }

    func testManualChoicesRoundTrip() {
        let ids = (0..<4).map { _ in UUID() }
        let proposal: Set<UUID> = [ids[1], ids[2], ids[3]]
        let locked: Set<UUID> = [ids[3]]
        // L'utente tiene la seconda e vuole eliminare la prima.
        let wanted: Set<UUID> = [ids[0], ids[2]]
        let overrides = GroupProposal.overrides(for: wanted, proposal: proposal, memberIDs: ids, locked: locked)
        XCTAssertEqual(overrides, [ids[0]: true, ids[1]: false])
        XCTAssertEqual(GroupProposal.deletion(proposal: proposal, overrides: overrides, locked: locked), wanted)
        // Senza scelte a mano vale la proposta, ma la bloccata resta comunque fuori.
        XCTAssertEqual(GroupProposal.deletion(proposal: proposal, overrides: [:], locked: locked), [ids[1], ids[2]])
    }

    func testSplitKeepsTheGroupOrder() {
        let ids = (0..<4).map { _ in UUID() }
        let split = GroupProposal.split(memberIDs: ids, deletion: [ids[3], ids[1]])
        XCTAssertEqual(split.keep, [ids[0], ids[2]])
        XCTAssertEqual(split.delete, [ids[1], ids[3]])
    }

    // MARK: - Trascinamento sulle griglie

    func testVerticalAndDiagonalDragsScroll() {
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: CGSize(width: 3, height: 14), contentMoved: 0), .scrolling)
        // Un pollice storto: parecchio di lato, ma più in verticale.
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: CGSize(width: 14, height: 9), contentMoved: 0), .scrolling)
    }

    func testOnlyAClearlyHorizontalDragOnAStillGridSelects() {
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: CGSize(width: -16, height: 4), contentMoved: 0), .painting)
        // La griglia si sta ancora muovendo: è uno scorrimento, anche se il dito va di lato.
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: CGSize(width: 16, height: 2), contentMoved: 40), .scrolling)
    }

    func testAShortMovementIsStillUndecided() {
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: CGSize(width: 8, height: 2), contentMoved: 0), .undecided)
        XCTAssertEqual(GridDragIntent.decide(screenTranslation: .zero, contentMoved: 0), .undecided)
    }

    // MARK: - Pagine a tutto schermo

    func testThePagerShowsAWindowAroundTheOpenedItem() {
        let ids = (0..<1_000).map { _ in UUID() }
        let window = ItemPreviewScreen.window(ids, around: ids[500], radius: 10)
        XCTAssertEqual(window.count, 21)
        XCTAssertEqual(window.first, ids[490])
        XCTAssertEqual(window.last, ids[510])
        XCTAssertEqual(ItemPreviewScreen.window(ids, around: ids[2], radius: 10).first, ids[0])
        XCTAssertEqual(ItemPreviewScreen.window(ids, around: UUID(), radius: 10).count, 1)
    }
}
