import XCTest
@testable import ClearSpace

/// Selezione rapida nella griglia (tocchi e trascinamento) e stella delle migliori.
final class GridSelectionTests: XCTestCase {

    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    // MARK: - Geometria della griglia

    func testColumnsFitTheWidthWithinLimits() {
        let phone = GridMetrics.fitting(width: 378, minimumSide: 100, spacing: 3)
        XCTAssertEqual(phone.columns, 3)
        XCTAssertEqual(phone.cellSide, 124, accuracy: 0.001)

        // Anche su uno schermo stretto restano tre colonne, con celle più piccole.
        let narrow = GridMetrics.fitting(width: 200, minimumSide: 100, spacing: 3)
        XCTAssertEqual(narrow.columns, 3)

        let wide = GridMetrics.fitting(width: 1_000, minimumSide: 100, spacing: 3)
        XCTAssertEqual(wide.columns, 8)

        let unmeasured = GridMetrics.fitting(width: 0, minimumSide: 100, spacing: 3)
        XCTAssertEqual(unmeasured.cellSide, 0)
    }

    func testIndexUnderAPointFollowsRowsAndColumns() {
        let metrics = GridMetrics(columns: 3, spacing: 4, cellSide: 100)
        XCTAssertEqual(metrics.index(at: CGPoint(x: 10, y: 10), count: 10), 0)
        XCTAssertEqual(metrics.index(at: CGPoint(x: 250, y: 10), count: 10), 2)
        XCTAssertEqual(metrics.index(at: CGPoint(x: 150, y: 120), count: 10), 4)
        // Fuori dalla griglia vale la cella più vicina: il trascinamento non si interrompe.
        XCTAssertEqual(metrics.index(at: CGPoint(x: -40, y: -40), count: 10), 0)
        XCTAssertEqual(metrics.index(at: CGPoint(x: 999, y: 999), count: 10), 9)
        // Nell'ultima riga incompleta, a destra dell'ultimo elemento, vale l'ultimo.
        XCTAssertEqual(metrics.index(at: CGPoint(x: 250, y: 320), count: 10), 9)
        XCTAssertNil(metrics.index(at: .zero, count: 0))
        XCTAssertNil(GridMetrics(columns: 3, spacing: 4, cellSide: 0).index(at: .zero, count: 5))
    }

    func testVisibleRowsFollowTheScrollOffset() {
        let metrics = GridMetrics(columns: 3, spacing: 4, cellSide: 100)
        XCTAssertEqual(metrics.rowCount(for: 30), 10)
        XCTAssertEqual(metrics.rowCount(for: 31), 11)
        XCTAssertEqual(metrics.visibleRows(offset: 0, height: 300, count: 30), 0...2)
        XCTAssertEqual(metrics.visibleRows(offset: 520, height: 300, count: 30), 5...7)
        XCTAssertEqual(metrics.visibleRows(offset: 5_000, height: 300, count: 30), 9...9)
        XCTAssertNil(metrics.visibleRows(offset: 0, height: 300, count: 0))
    }

    // MARK: - Trascinamento

    func testDraggingSelectsTheRangeAndGoingBackRestoresIt() throws {
        let all = ids(6)
        let drag = try XCTUnwrap(DragSelection(anchor: 1, ids: all, current: [all[5]]))
        XCTAssertTrue(drag.selects)
        XCTAssertEqual(drag.selection(reaching: 4, ids: all), Set([all[1], all[2], all[3], all[4], all[5]]))
        // Tornando indietro con il dito gli elementi esclusi riprendono lo stato iniziale.
        XCTAssertEqual(drag.selection(reaching: 2, ids: all), Set([all[1], all[2], all[5]]))
        // Anche spostandosi prima del punto di partenza.
        XCTAssertEqual(drag.selection(reaching: 0, ids: all), Set([all[0], all[1], all[5]]))
    }

    func testDraggingFromASelectedItemDeselects() throws {
        let all = ids(4)
        let drag = try XCTUnwrap(DragSelection(anchor: 2, ids: all, current: Set(all)))
        XCTAssertFalse(drag.selects)
        XCTAssertEqual(drag.selection(reaching: 3, ids: all), Set([all[0], all[1]]))
        // Un indice oltre la fine vale come l'ultimo elemento.
        XCTAssertEqual(drag.selection(reaching: 40, ids: all), Set([all[0], all[1]]))
    }

    func testDragSelectionNeedsAValidAnchor() {
        XCTAssertNil(DragSelection(anchor: 3, ids: ids(3), current: []))
        XCTAssertNil(DragSelection(anchor: -1, ids: ids(3), current: []))
    }

    // MARK: - Stella delle migliori

    private func starred(_ item: IndexedItem) -> IndexedItem {
        var copy = item
        copy.setReviewStatus(.kept, at: TestData.now)
        copy.starredAt = TestData.now
        return copy
    }

    func testTheUserStarsWinOverTheSuggestion() {
        let first = starred(TestData.item())
        let second = TestData.item()
        let third = TestData.item()
        let keepers = GroupChoice.preferredKeepers(members: [first, second, third], suggestedID: third.id)
        XCTAssertEqual(keepers, [first.id])

        let choice = GroupChoice.keepOnly(keepers, among: [first.id, second.id, third.id])
        XCTAssertEqual(choice.keep, [first.id])
        XCTAssertEqual(choice.delete, [second.id, third.id])
    }

    func testWithoutStarsTheSuggestionIsKept() {
        let members = [TestData.item(), TestData.item()]
        XCTAssertEqual(GroupChoice.preferredKeepers(members: members, suggestedID: members[1].id), [members[1].id])
        XCTAssertEqual(GroupChoice.preferredKeepers(members: members, suggestedID: nil), [])
        // Un consiglio che non riguarda più i membri del gruppo viene ignorato.
        XCTAssertEqual(GroupChoice.preferredKeepers(members: members, suggestedID: UUID()), [])
    }

    func testAStarOnlyLastsWhileTheItemIsKept() {
        var item = starred(TestData.item())
        XCTAssertTrue(item.isStarred)

        item.setReviewStatus(.kept, at: TestData.now)
        XCTAssertTrue(item.isStarred, "Conservare di nuovo non toglie la stella")

        item.setReviewStatus(.markedForDeletion, at: TestData.now)
        XCTAssertFalse(item.isStarred, "Proporre per l'eliminazione toglie la stella")

        item = starred(item)
        item.setReviewStatus(.postponed, at: TestData.now)
        XCTAssertFalse(item.isStarred, "Rimandare toglie la stella")

        item = starred(item)
        item.setReviewStatus(.unreviewed, at: TestData.now)
        XCTAssertFalse(item.isStarred, "Annullare la decisione toglie la stella")
        XCTAssertNil(item.decidedAt)
    }

    func testItemsSavedBeforeStarsStillDecode() throws {
        let item = starred(TestData.item())
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["starredAt"])
        object.removeValue(forKey: "starredAt")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(IndexedItem.self, from: legacy)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.reviewStatus, .kept)
        XCTAssertFalse(decoded.isStarred)
    }
}
