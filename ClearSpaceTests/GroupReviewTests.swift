import XCTest
@testable import ClearSpace

/// Revisione gruppo per gruppo, sensibilità delle foto simili, promemoria di Eliminati di recente
/// e calcolo in parallelo delle analisi.
final class GroupReviewTests: XCTestCase {

    private let evaluator = ProtectionEvaluator()

    // MARK: - Gruppi da decidere

    func testSummaryCountsOnlyPendingAndUnprotectedMembers() {
        let best = TestData.item(bytes: 3_000_000)
        let unseen = TestData.item(bytes: 2_000_000)
        let postponed = TestData.item(bytes: 1_000_000, status: .postponed)
        let kept = TestData.item(bytes: 4_000_000, status: .kept)
        let marked = TestData.item(bytes: 5_000_000, status: .markedForDeletion)
        var protected = TestData.item(bytes: 6_000_000)
        protected.isProtected = true

        let summary = GroupReview.summary(
            members: [best, unseen, postponed, kept, marked, protected],
            suggestedID: best.id,
            evaluator: evaluator
        )
        // Da decidere: la consigliata, quella mai vista e quella rimandata.
        XCTAssertEqual(summary.pendingCount, 3)
        // Si libererebbero solo le due da decidere diverse dalla consigliata.
        XCTAssertEqual(summary.potentialBytes, 3_000_000)
        XCTAssertFalse(summary.isDecided)
    }

    func testStarsReplaceTheSuggestionInThePotential() {
        var starred = TestData.item(bytes: 1_000_000, status: .kept)
        starred.starredAt = TestData.now
        let suggested = TestData.item(bytes: 2_000_000)
        let other = TestData.item(bytes: 3_000_000)

        let summary = GroupReview.summary(
            members: [starred, suggested, other],
            suggestedID: suggested.id,
            evaluator: evaluator
        )
        // Con una stella si tiene quella: anche la consigliata verrebbe proposta.
        XCTAssertEqual(summary.pendingCount, 2)
        XCTAssertEqual(summary.potentialBytes, 5_000_000)
    }

    func testAGroupIsDecidedWhenNothingIsLeftToReview() {
        let kept = TestData.item(status: .kept)
        let marked = TestData.item(status: .markedForDeletion)
        // I preferiti sono protetti: non restano «da decidere».
        let favorite = TestData.item(traits: [.favorite])

        let summary = GroupReview.summary(members: [kept, marked, favorite], suggestedID: kept.id, evaluator: evaluator)
        XCTAssertEqual(summary.pendingCount, 0)
        XCTAssertEqual(summary.potentialBytes, 0)
        XCTAssertTrue(summary.isDecided)
    }

    func testPendingGroupsComeFirstFromTheLargestSaving() {
        let values: [(name: String, summary: GroupReviewSummary)] = [
            ("deciso", GroupReviewSummary(pendingCount: 0, potentialBytes: 0)),
            ("piccolo", GroupReviewSummary(pendingCount: 2, potentialBytes: 100)),
            ("grande", GroupReviewSummary(pendingCount: 1, potentialBytes: 900)),
            ("piccolo-bis", GroupReviewSummary(pendingCount: 3, potentialBytes: 100)),
            ("deciso-bis", GroupReviewSummary(pendingCount: 0, potentialBytes: 0))
        ]
        let ordered = GroupReview.ordered(values) { $0.summary }.map { $0.name }
        // A parità di spazio resta l'ordine di partenza; i decisi vanno in fondo.
        XCTAssertEqual(ordered, ["grande", "piccolo", "piccolo-bis", "deciso", "deciso-bis"])
    }

    func testTheSequenceProposesPendingGroupsOrAllWhenEverythingIsDecided() {
        let pending = GroupReviewSummary(pendingCount: 1, potentialBytes: 10)
        let decided = GroupReviewSummary(pendingCount: 0, potentialBytes: 0)

        let mixed = GroupReview.sequence([("a", decided), ("b", pending), ("c", pending)]) { $0.1 }
        XCTAssertEqual(mixed.map { $0.0 }, ["b", "c"])

        // Tutti decisi: si possono ricontrollare tutti.
        let allDecided = GroupReview.sequence([("a", decided), ("b", decided)]) { $0.1 }
        XCTAssertEqual(allDecided.map { $0.0 }, ["a", "b"])

        XCTAssertTrue(GroupReview.sequence([(String, GroupReviewSummary)]()) { $0.1 }.isEmpty)
    }

    func testNextAvailableSkipsGroupsThatNoLongerExist() {
        let available: Set<Int> = [2, 4]
        XCTAssertEqual(GroupReview.nextAvailable(from: 0, count: 6) { available.contains($0) }, 2)
        XCTAssertEqual(GroupReview.nextAvailable(from: 3, count: 6) { available.contains($0) }, 4)
        // Nessuno dopo: si arriva alla fine.
        XCTAssertEqual(GroupReview.nextAvailable(from: 5, count: 6) { available.contains($0) }, 6)
        XCTAssertEqual(GroupReview.nextAvailable(from: 9, count: 6) { _ in true }, 6)
        XCTAssertEqual(GroupReview.nextAvailable(from: -3, count: 6) { _ in true }, 0)
    }

    // MARK: - Sensibilità delle foto simili

    func testSensitivityWidensOrNarrowsEveryThreshold() {
        let strict = SimilaritySensitivity.strict.thresholds
        let standard = SimilaritySensitivity.standard.thresholds
        let broad = SimilaritySensitivity.broad.thresholds

        XCTAssertEqual(standard, SimilarityThresholds.standard)
        XCTAssertEqual(standard.featureDistance, AppConfiguration.Thresholds.similarFeatureDistance)
        XCTAssertEqual(standard.timeWindow, AppConfiguration.Thresholds.similarTimeWindow)

        XCTAssertLessThan(strict.featureDistance, standard.featureDistance)
        XCTAssertLessThan(strict.screenshotDistance, standard.screenshotDistance)
        XCTAssertLessThan(strict.timeWindow, standard.timeWindow)
        XCTAssertLessThan(strict.hashDistance, standard.hashDistance)
        XCTAssertGreaterThan(strict.hashDistance, 0)

        XCTAssertGreaterThan(broad.featureDistance, standard.featureDistance)
        XCTAssertGreaterThan(broad.screenshotDistance, standard.screenshotDistance)
        XCTAssertGreaterThan(broad.timeWindow, standard.timeWindow)
        XCTAssertGreaterThan(broad.hashDistance, standard.hashDistance)
        // Anche «Ampia» resta lontana da immagini del tutto diverse.
        XCTAssertLessThan(broad.featureDistance, 0.8)

        for sensitivity in SimilaritySensitivity.allCases {
            XCTAssertFalse(sensitivity.title.isEmpty)
            XCTAssertFalse(sensitivity.detail.isEmpty)
        }
    }

    func testSensitivityIsSavedAndOlderPreferencesStillLoad() throws {
        var preferences = UserPreferences()
        XCTAssertEqual(preferences.similaritySensitivity, .standard)
        preferences.similaritySensitivity = .broad
        preferences.quickSessionSize = 100
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(UserPreferences.self, from: data).similaritySensitivity, .broad)

        // Preferenze salvate prima di questa impostazione, oppure con un valore sconosciuto:
        // si usa «Normale» e le altre impostazioni restano.
        let parsed = try JSONSerialization.jsonObject(with: data)
        var object = try XCTUnwrap(parsed as? [String: Any])
        object["similaritySensitivity"] = "sconosciuta"
        let unknown = try JSONDecoder().decode(
            UserPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(unknown.similaritySensitivity, .standard)
        XCTAssertEqual(unknown.quickSessionSize, 100)

        object.removeValue(forKey: "similaritySensitivity")
        let older = try JSONDecoder().decode(
            UserPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(older.similaritySensitivity, .standard)
        XCTAssertEqual(older.quickSessionSize, 100)
    }

    // MARK: - Eliminati di recente

    func testRecentlyDeletedCountsOnlyLibraryItemsReallyDeleted() {
        func outcome(_ source: StorageSource, _ state: OutcomeState, bytes: Int64) -> ItemOutcome {
            let entry = PlanEntry(
                itemID: UUID(), title: "Elemento", source: source, category: .photo,
                operation: source == .photoLibrary ? .deleteLibraryAsset : .removeFile,
                deviceBytes: bytes, cloudBytes: 0, cloudEffectIsConditional: false, isSensitive: false
            )
            return ItemOutcome(entry: entry, state: state)
        }
        let report = CleanupReport(outcomes: [
            outcome(.photoLibrary, .deleted, bytes: 100),
            outcome(.photoLibrary, .deleted, bytes: 50),
            outcome(.photoLibrary, .failed, bytes: 1_000),
            outcome(.photoLibrary, .skipped, bytes: 1_000),
            outcome(.localFiles, .deleted, bytes: 7)
        ])
        XCTAssertEqual(report.recentlyDeletedCount, 2)
        XCTAssertEqual(report.recentlyDeletedDeviceBytes, 150)
        XCTAssertEqual(report.deletedCount, 3)

        XCTAssertEqual(CleanupReport(outcomes: [outcome(.iCloudDrive, .deleted, bytes: 9)]).recentlyDeletedCount, 0)
    }

    // MARK: - Calcolo in parallelo

    func testConcurrentResultsKeepTheOrderOfPositions() {
        let squares = PhotoAnalysisPipeline.concurrentResults(count: 200) { (index: Int) -> Int? in
            index.isMultiple(of: 7) ? nil : index * index
        }
        XCTAssertEqual(squares.count, 200)
        for (index, value) in squares.enumerated() {
            XCTAssertEqual(value, index.isMultiple(of: 7) ? nil : index * index, "posizione \(index)")
        }
        XCTAssertEqual(PhotoAnalysisPipeline.concurrentResults(count: 1) { (index: Int) -> Int? in index + 5 }, [5])
        XCTAssertTrue(PhotoAnalysisPipeline.concurrentResults(count: 0) { (index: Int) -> Int? in index }.isEmpty)
        XCTAssertGreaterThanOrEqual(PhotoAnalysisPipeline.parallelWorkers, 2)
        XCTAssertLessThanOrEqual(PhotoAnalysisPipeline.parallelWorkers, 4)
    }
}
