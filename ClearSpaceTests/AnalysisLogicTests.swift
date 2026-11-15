import XCTest
@testable import ClearSpace

final class TextSimilarityTests: XCTestCase {

    private let contract = """
    Contratto di locazione ad uso abitativo. Il locatore concede in locazione al conduttore \
    l'immobile sito in Pescara, composto da tre vani oltre accessori, per la durata di quattro anni \
    con decorrenza dal primo gennaio. Il canone annuo è convenuto in euro seimila da pagarsi in rate mensili.
    """

    func testIdenticalTextsAreFullySimilar() {
        XCTAssertEqual(TextSimilarity.similarity(contract, contract), 1, accuracy: 0.0001)
    }

    func testLayoutAndPunctuationDifferencesAreIgnored() {
        let first = "Contratto di LOCAZIONE, art. 1: il canone è mensile."
        let second = "contratto   di locazione art 1 il canone e mensile"
        XCTAssertEqual(TextSimilarity.tokens(first), TextSimilarity.tokens(second))
    }

    func testUnrelatedTextsAreNotSimilar() {
        let other = "Ricetta della torta di mele: farina, zucchero, burro, uova, lievito e tre mele renette tagliate a fette sottili."
        XCTAssertLessThan(TextSimilarity.similarity(contract, other), 0.1)
    }

    func testSmallEditKeepsHighSimilarity() {
        let edited = contract.replacingOccurrences(of: "seimila", with: "settemila")
        XCTAssertGreaterThan(TextSimilarity.similarity(contract, edited), 0.7)
        XCTAssertLessThan(TextSimilarity.similarity(contract, edited), 1)
    }

    func testMinHashApproximatesTheRealSimilarity() {
        let first = Set((0..<400).map { UInt64($0) &* 2_654_435_761 })
        let second = Set((200..<600).map { UInt64($0) &* 2_654_435_761 })
        let exact = TextSimilarity.jaccard(first, second)
        let estimate = TextSimilarity.estimatedSimilarity(
            TextSimilarity.minHashSignature(first),
            TextSimilarity.minHashSignature(second)
        )
        XCTAssertEqual(exact, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(estimate, exact, accuracy: 0.2)
    }

    func testVersionSuffixesAreRemovedFromFileNames() {
        XCTAssertEqual(TextSimilarity.normalizedBaseName("Contratto (1).pdf"), "contratto")
        XCTAssertEqual(TextSimilarity.normalizedBaseName("contratto_v2.pdf"), "contratto")
        XCTAssertEqual(TextSimilarity.normalizedBaseName("Contratto copia.pdf"), "contratto")
        XCTAssertEqual(TextSimilarity.normalizedBaseName("Relazione finale 2.docx"), "relazione")
    }

    func testDifferenceDescriptionMentionsExtraPage() {
        let description = TextSimilarity.describeDifference(
            pagesOfFirst: ["prima pagina del documento", "seconda pagina"],
            pagesOfSecond: ["prima pagina del documento"]
        )
        XCTAssertTrue(description.contains("1 pagina in più"))
    }
}

final class TextClassifierTests: XCTestCase {

    func testReceiptIsRecognised() {
        let lines = ["SCONTRINO FISCALE", "Pane 2,50", "Latte 1,20", "TOTALE 3,70", "IVA 4%"]
        let result = TextClassifier.classify(lines: lines, coverage: 0.2, isScreenshot: false)

        XCTAssertTrue(result.traits.contains(.receipt))
        XCTAssertTrue(result.traits.contains(.hasText))
    }

    func testWordsContainingKeywordsDoNotTriggerFalsePositives() {
        let lines = ["Sono arrivato in stazione e ho attivato il biglietto digitale del privato"]
        let result = TextClassifier.classify(lines: lines, coverage: 0.1, isScreenshot: true)

        XCTAssertFalse(result.traits.contains(.receipt))
        XCTAssertFalse(result.traits.contains(.sensitiveText))
    }

    func testConversationScreenshotIsRecognised() {
        let lines = ["Marco", "online", "Ciao!", "10:31", "Come stai?", "10:32", "Bene, tu?", "10:35"]
        let result = TextClassifier.classify(lines: lines, coverage: 0.3, isScreenshot: true)

        XCTAssertTrue(result.traits.contains(.conversation))
    }

    func testSensitiveCodesAreFlagged() {
        let iban = TextClassifier.classify(lines: ["IT60X0542811101000000123456"], coverage: 0.05, isScreenshot: true)
        XCTAssertTrue(iban.traits.contains(.sensitiveText))

        let fiscalCode = TextClassifier.classify(lines: ["Codice: RSSMRA85T10A562S"], coverage: 0.05, isScreenshot: false)
        XCTAssertTrue(fiscalCode.traits.contains(.sensitiveText))

        let password = TextClassifier.classify(lines: ["La tua password temporanea"], coverage: 0.05, isScreenshot: true)
        XCTAssertTrue(password.traits.contains(.sensitiveText))
    }

    func testEmptyTextHasNoTraits() {
        let result = TextClassifier.classify(lines: ["  ", ""], coverage: 0, isScreenshot: true)
        XCTAssertTrue(result.traits.isEmpty)
        XCTAssertEqual(result.characterCount, 0)
    }
}

final class ImageMetricsTests: XCTestCase {

    private func image(width: Int, height: Int, _ pixel: (Int, Int) -> UInt8) -> GrayImage {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(pixel(x, y))
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)!
    }

    func testInvalidBuffersAreRejected() {
        XCTAssertNil(GrayImage(width: 4, height: 4, pixels: [0, 1, 2]))
        XCTAssertNil(GrayImage(width: 0, height: 4, pixels: []))
    }

    func testDifferenceHashFollowsHorizontalGradients() {
        let darkening = image(width: 9, height: 8) { x, _ in UInt8(200 - x * 20) }
        let brightening = image(width: 9, height: 8) { x, _ in UInt8(x * 20) }

        XCTAssertEqual(ImageMetrics.differenceHash(darkening), UInt64.max)
        XCTAssertEqual(ImageMetrics.differenceHash(brightening), 0)
        XCTAssertNil(ImageMetrics.differenceHash(image(width: 8, height: 8) { _, _ in 0 }))
    }

    func testHammingDistance() {
        XCTAssertEqual(ImageMetrics.hammingDistance(0b1011, 0b0001), 2)
        XCTAssertEqual(ImageMetrics.hammingDistance(7, 7), 0)
    }

    func testUniformHashesAreNotInformative() {
        XCTAssertFalse(ImageMetrics.isInformative(hash: 0))
        XCTAssertFalse(ImageMetrics.isInformative(hash: UInt64.max))
        XCTAssertTrue(ImageMetrics.isInformative(hash: 0x00FF_00FF_00FF_00FF))
    }

    func testSharpImagesHaveHigherLaplacianVariance() {
        let flat = image(width: 32, height: 32) { _, _ in 128 }
        let checkerboard = image(width: 32, height: 32) { x, y in (x + y) % 2 == 0 ? 255 : 0 }

        XCTAssertEqual(ImageMetrics.laplacianVariance(flat), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(ImageMetrics.laplacianVariance(checkerboard), 1_000)
        XCTAssertEqual(ImageMetrics.sharpnessScore(variance: 0), 0)
        XCTAssertEqual(ImageMetrics.sharpnessScore(variance: 1_000_000), 1)
    }

    func testLuminance() {
        let white = image(width: 4, height: 4) { _, _ in 255 }
        let stats = ImageMetrics.luminance(white)
        XCTAssertEqual(stats.mean, 1, accuracy: 0.0001)
        XCTAssertEqual(stats.deviation, 0, accuracy: 0.0001)
    }

    func testNearPairsFindsHashesThatDifferByFewBits() {
        let pairs = ImageMetrics.nearPairs([0, 1, UInt64.max, 0b111])
        let found = Set(pairs.map { "\($0.0)-\($0.1)" })

        XCTAssertTrue(found.contains("0-1"))
        XCTAssertTrue(found.contains("0-3"))
        XCTAssertTrue(found.contains("1-3"))
        XCTAssertFalse(found.contains("0-2"))
        XCTAssertEqual(pairs.count, 3)
    }
}

final class QualityRankerTests: XCTestCase {

    func testSharperHigherResolutionPhotoIsSuggested() {
        var soft = TestData.item()
        soft.pixelWidth = 2_000
        soft.pixelHeight = 1_500
        soft.sharpness = 0.2
        var sharp = TestData.item()
        sharp.pixelWidth = 4_000
        sharp.pixelHeight = 3_000
        sharp.sharpness = 0.8

        let suggestion = QualityRanker.suggestion(among: [soft, sharp])
        XCTAssertEqual(suggestion?.keepID, sharp.id)
        XCTAssertTrue(suggestion?.reason.contains("nitida") ?? false)
        XCTAssertTrue(suggestion?.reason.contains("risoluzione") ?? false)
    }

    func testFavoriteWinsAmongEquivalentPhotos() {
        let plain = TestData.item()
        let favorite = TestData.item(traits: [.favorite])
        XCTAssertEqual(QualityRanker.suggestion(among: [plain, favorite])?.keepID, favorite.id)
    }

    func testOldestCopyIsTreatedAsTheOriginal() {
        let recent = TestData.item(ageDays: 5)
        let original = TestData.item(ageDays: 500)
        XCTAssertEqual(QualityRanker.originalSuggestion(among: [recent, original])?.keepID, original.id)
    }

    func testSingleItemHasNoSuggestion() {
        XCTAssertNil(QualityRanker.suggestion(among: [TestData.item()]))
        XCTAssertNil(QualityRanker.originalSuggestion(among: [TestData.item()]))
    }

    func testReasonsAreJoinedInNaturalItalian() {
        XCTAssertEqual(QualityRanker.join(["a"]), "a")
        XCTAssertEqual(QualityRanker.join(["a", "b"]), "a e b")
        XCTAssertEqual(QualityRanker.join(["a", "b", "c"]), "a, b e c")
    }
}

final class DisjointSetTests: XCTestCase {

    func testLinkedElementsEndUpInTheSameGroup() {
        var sets = DisjointSet(count: 5)
        sets.union(0, 1)
        sets.union(1, 2)
        let groups = sets.groups().map { Set($0) }

        XCTAssertTrue(groups.contains([0, 1, 2]))
        XCTAssertTrue(groups.contains([3]))
        XCTAssertTrue(groups.contains([4]))
        XCTAssertEqual(groups.count, 3)
    }
}
