import XCTest
@testable import ClearSpace

/// La scelta dello scatto migliore tra foto simili: i criteri devono essere confrontabili,
/// spiegati con parole semplici e mai più forti delle preferenze espresse dall'utente.
final class ShotQualityTests: XCTestCase {

    private func photo(sharpness: Double, shot: ShotMetrics?) -> IndexedItem {
        var item = TestData.item()
        item.pixelWidth = 4_000
        item.pixelHeight = 3_000
        item.sharpness = sharpness
        item.brightness = 0.45
        item.shot = shot
        return item
    }

    func testOpenEyesBeatASlightlySharperShotWithClosedEyes() {
        let closed = photo(
            sharpness: 0.80,
            shot: ShotMetrics(detailSharpness: 0.85, subjectSharpness: 0.85, faceCount: 1, faceQuality: 0.55, openEyes: 0, smiles: 0)
        )
        let open = photo(
            sharpness: 0.75,
            shot: ShotMetrics(detailSharpness: 0.78, subjectSharpness: 0.80, faceCount: 1, faceQuality: 0.70, openEyes: 1, smiles: 1)
        )

        let suggestion = QualityRanker.suggestion(among: [closed, open])
        XCTAssertEqual(suggestion?.keepID, open.id)
        XCTAssertTrue(suggestion?.reason.contains("occhi aperti") ?? false)
    }

    func testSubjectFocusDecidesWhenThereAreNoFaces() {
        let soft = photo(sharpness: 0.6, shot: ShotMetrics(detailSharpness: 0.60, subjectSharpness: 0.20))
        let crisp = photo(sharpness: 0.6, shot: ShotMetrics(detailSharpness: 0.62, subjectSharpness: 0.80))

        let suggestion = QualityRanker.suggestion(among: [soft, crisp])
        XCTAssertEqual(suggestion?.keepID, crisp.id)
        XCTAssertTrue(suggestion?.reason.contains("soggetto") ?? false)
    }

    func testMembersWithoutShotMetricsAreComparedOnCommonCriteria() {
        // A uno dei due mancano le misure del confronto approfondito: valgono solo i criteri comuni,
        // altrimenti si paragonerebbero numeri calcolati in modo diverso.
        let analyzed = photo(sharpness: 0.3, shot: ShotMetrics(detailSharpness: 0.95, subjectSharpness: 0.95))
        let plain = photo(sharpness: 0.8, shot: nil)

        XCTAssertFalse(QualityRanker.Criteria(members: [analyzed, plain]).usesShotMetrics)
        XCTAssertEqual(QualityRanker.suggestion(among: [analyzed, plain])?.keepID, plain.id)
    }

    func testFavoriteStillWinsOverBetterMetrics() {
        var favorite = photo(sharpness: 0.4, shot: ShotMetrics(detailSharpness: 0.4, subjectSharpness: 0.4))
        favorite.traits.insert(.favorite)
        let better = photo(sharpness: 0.9, shot: ShotMetrics(detailSharpness: 0.6, subjectSharpness: 0.6))

        XCTAssertEqual(QualityRanker.suggestion(among: [favorite, better])?.keepID, favorite.id)
    }

    func testGradeIsQualityAsAPercentage() {
        let perfect = photo(sharpness: 1, shot: ShotMetrics(detailSharpness: 1, subjectSharpness: 1))
        let poor = photo(sharpness: 0, shot: ShotMetrics(detailSharpness: 0, subjectSharpness: 0))

        XCTAssertEqual(QualityRanker.breakdown(perfect).grade, 100)
        XCTAssertLessThan(QualityRanker.breakdown(poor).grade, 50)
    }

    func testHighlightsFlagClosedEyes() {
        let item = photo(
            sharpness: 0.8,
            shot: ShotMetrics(detailSharpness: 0.8, faceCount: 2, faceQuality: 0.6, openEyes: 0.5)
        )
        let texts = QualityRanker.highlights(for: item, rating: QualityRanker.breakdown(item)).map { $0.text }
        XCTAssertTrue(texts.contains("Occhi chiusi"))
        XCTAssertFalse(texts.contains("Occhi aperti"))
    }

    func testShotMetricsAreOptionalAndSurviveARoundTrip() throws {
        var item = TestData.item()
        let plain = try JSONDecoder().decode(IndexedItem.self, from: JSONEncoder().encode(item))
        XCTAssertNil(plain.shot)

        item.shot = ShotMetrics(detailSharpness: 0.7, faceCount: 1, faceQuality: 0.6, openEyes: 1)
        let decoded = try JSONDecoder().decode(IndexedItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.shot, item.shot)
    }

    // MARK: - Nitidezza per regione

    func testRegionSharpnessIgnoresDetailOutsideTheRegion() throws {
        // Metà sinistra a scacchi (ricca di dettaglio), metà destra uniforme.
        var pixels: [UInt8] = []
        for y in 0..<20 {
            for x in 0..<40 {
                pixels.append(x < 20 ? ((x + y) % 2 == 0 ? 255 : 0) : 128)
            }
        }
        let image = try XCTUnwrap(GrayImage(width: 40, height: 20, pixels: pixels))

        let detailed = PixelRegion(minX: 0, minY: 0, maxX: 20, maxY: 20)
        let uniform = PixelRegion(minX: 22, minY: 0, maxX: 40, maxY: 20)
        XCTAssertGreaterThan(ImageMetrics.laplacianVariance(image, region: detailed), 1_000)
        XCTAssertEqual(ImageMetrics.laplacianVariance(image, region: uniform), 0, accuracy: 0.0001)
        // Una regione vuota o fuori dall'immagine non produce valori casuali.
        XCTAssertEqual(ImageMetrics.laplacianVariance(image, region: PixelRegion(minX: 30, minY: 5, maxX: 30, maxY: 5)), 0)
    }

    func testNormalizedRegionsAreFlippedVertically() throws {
        let image = try XCTUnwrap(GrayImage(width: 100, height: 200, pixels: [UInt8](repeating: 0, count: 20_000)))
        // Quarto in basso a sinistra nelle coordinate di Vision, che hanno l'origine in basso.
        let region = ImageMetrics.region(normalizedX: 0, y: 0, width: 0.5, height: 0.25, in: image)
        XCTAssertEqual(region, PixelRegion(minX: 0, minY: 150, maxX: 50, maxY: 200))
    }

    // MARK: - Scelte di gruppo nella sessione

    func testGroupDecisionIsUndoneInOneMove() {
        let ids = (0..<5).map { _ in UUID() }
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)
        session.record(.keep, previousStatus: .unreviewed, bytes: 1)

        // Sulla seconda carta: "tieni solo la migliore" su un gruppo di tre scatti.
        session.recordBatch([
            BatchChoice(itemID: ids[2], choice: .keep, previousStatus: .unreviewed, bytes: 10),
            BatchChoice(itemID: ids[1], choice: .delete, previousStatus: .unreviewed, bytes: 20),
            BatchChoice(itemID: ids[4], choice: .delete, previousStatus: .unreviewed, bytes: 30)
        ])
        XCTAssertEqual(session.cursor, 1)
        XCTAssertEqual(session.markedCount, 2)
        XCTAssertEqual(session.markedBytes, 50)

        // Gli elementi già decisi vengono saltati quando arriva il loro turno.
        session.skipCurrent()
        session.skipCurrent()
        XCTAssertEqual(session.currentItemID, ids[3])

        let undone = session.undoLastMove()
        XCTAssertEqual(undone.count, 3)
        XCTAssertEqual(session.cursor, 1)
        XCTAssertEqual(session.decisions.count, 1)

        // La mossa precedente era una scelta singola: si annulla da sola.
        XCTAssertEqual(session.undoLastMove().map { $0.itemID }, [ids[0]])
        XCTAssertEqual(session.cursor, 0)
        XCTAssertTrue(session.undoLastMove().isEmpty)
    }

    func testUndoingAGroupDecisionOnItemsAheadDoesNotMoveTheCursor() {
        let ids = (0..<4).map { _ in UUID() }
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)
        session.recordBatch([
            BatchChoice(itemID: ids[2], choice: .keep, previousStatus: .unreviewed, bytes: 1),
            BatchChoice(itemID: ids[3], choice: .delete, previousStatus: .unreviewed, bytes: 1)
        ])

        XCTAssertEqual(session.undoLastMove().count, 2)
        XCTAssertEqual(session.cursor, 0)
        XCTAssertTrue(session.decisions.isEmpty)
    }

    // MARK: - Elementi scelti dalla striscia

    func testBringingAnItemToFrontMakesItCurrentWithoutLosingTheOthers() {
        let ids = (0..<4).map { _ in UUID() }
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)
        session.record(.keep, previousStatus: .unreviewed, bytes: 1)

        // Si tocca il quarto nella striscia: passa davanti, gli altri restano in coda dietro di lui.
        session.bringToFront(ids[3])
        XCTAssertEqual(session.currentItemID, ids[3])
        XCTAssertEqual(session.focusedItemID, ids[3])
        XCTAssertEqual(session.queue, [ids[0], ids[3], ids[1], ids[2]])

        session.record(.delete, previousStatus: .unreviewed, bytes: 7)
        XCTAssertNil(session.focusedItemID)
        XCTAssertEqual(session.currentItemID, ids[1])
    }

    func testAnItemAlreadyDecidedCanBeReconsideredAndCountsOnce() {
        let ids = (0..<3).map { _ in UUID() }
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)
        session.record(.delete, previousStatus: .unreviewed, bytes: 50)

        // Lo si riguarda e si cambia idea: da scartato a conservato.
        session.bringToFront(ids[0])
        XCTAssertEqual(session.currentItemID, ids[0])
        session.record(.keep, previousStatus: .markedForDeletion, bytes: 50)

        XCTAssertEqual(session.markedCount, 0)
        XCTAssertEqual(session.keptCount, 1)
        XCTAssertEqual(session.markedBytes, 0)
        XCTAssertEqual(session.examinedCount, 1)
        XCTAssertEqual(session.currentItemID, ids[1])

        // Annullando torna in vigore la scelta precedente.
        let undone = session.undoLastMove()
        XCTAssertEqual(undone.first?.previousStatus, .markedForDeletion)
        XCTAssertEqual(session.markedCount, 1)
        XCTAssertEqual(session.keptCount, 0)
    }

    func testBringingTheCurrentItemToFrontOnlyPinsIt() {
        let ids = (0..<2).map { _ in UUID() }
        var session = CleanupSession(title: "Prova", mode: .quick, queue: ids, now: TestData.now)

        session.bringToFront(ids[0])
        XCTAssertEqual(session.queue, ids)
        XCTAssertEqual(session.cursor, 0)
        XCTAssertEqual(session.focusedItemID, ids[0])
    }

    func testDecisionsSavedBeforeGroupMovesStillDecode() throws {
        let json = """
        {"itemID":"\(UUID().uuidString)","choice":"keep","previousStatus":"unreviewed","bytes":5,"date":0}
        """
        let decision = try JSONDecoder().decode(SwipeDecision.self, from: Data(json.utf8))
        XCTAssertNil(decision.batchID)
        XCTAssertEqual(decision.choice, .keep)
    }

    // MARK: - Gruppi sovrapposti

    func testCopiesInsideASimilarGroupAreShownWithTheWholeGroup() {
        let sharp = UUID()
        let dark = UUID()
        let blurred = UUID()
        // Nitida e scura risultano copie tra loro; tutte e tre sono scatti simili.
        let duplicates = ItemGroup(kind: .visualDuplicate, scope: .photoLibrary, memberIDs: [sharp, dark])
        let similar = ItemGroup(kind: .similar, scope: .photoLibrary, memberIDs: [sharp, blurred, dark])

        // Si mostra l'insieme più ampio: così non si decide due volte sulle stesse foto.
        XCTAssertEqual(ItemGroup.preferred(duplicate: duplicates, similar: similar)?.id, similar.id)
        XCTAssertEqual(ItemGroup.preferred(duplicate: duplicates, similar: nil)?.id, duplicates.id)
        XCTAssertEqual(ItemGroup.preferred(duplicate: nil, similar: similar)?.id, similar.id)
        XCTAssertNil(ItemGroup.preferred(duplicate: nil, similar: nil))
    }

    func testCopiesOutsideTheSimilarGroupKeepTheirOwnGroup() {
        let first = UUID()
        let copyElsewhere = UUID()
        let neighbour = UUID()
        // La copia non è tra gli scatti simili: nasconderla dietro quel gruppo la farebbe perdere di vista.
        let duplicates = ItemGroup(kind: .exactDuplicate, scope: .photoLibrary, memberIDs: [first, copyElsewhere])
        let similar = ItemGroup(kind: .similar, scope: .photoLibrary, memberIDs: [first, neighbour])

        XCTAssertEqual(ItemGroup.preferred(duplicate: duplicates, similar: similar)?.id, duplicates.id)
    }

    // MARK: - Ordine della coda

    func testQueueKeepsGroupMembersTogetherWithTheSuggestedShotFirst() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let e = UUID()
        let group = ItemGroup(kind: .similar, scope: .photoLibrary, memberIDs: [b, d, e], suggestedKeepID: d)

        let clustered = CleanupPlanner.clusteredByGroup([a, b, c, d, e]) { id in
            [b, d, e].contains(id) ? group : nil
        }
        XCTAssertEqual(clustered, [a, d, b, e, c])
    }

    func testClusteringNeverAddsItemsThatWereNotInTheQueue() {
        let b = UUID()
        let d = UUID()
        let e = UUID()
        // Lo scatto consigliato non è in coda (succede nella pulizia guidata): non deve comparire.
        let group = ItemGroup(kind: .similar, scope: .photoLibrary, memberIDs: [b, d, e], suggestedKeepID: d)

        let clustered = CleanupPlanner.clusteredByGroup([e, b]) { _ in group }
        XCTAssertEqual(clustered, [b, e])
    }
}
