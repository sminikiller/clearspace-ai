import XCTest
@testable import ClearSpace

/// Verifica il principio più importante del progetto: nessuna eliminazione senza revisione e conferma.
final class SafetyRulesTests: XCTestCase {

    // MARK: - Swipe e selezione

    func testSwipeTowardsDeletionOnlyChangesReviewStatus() {
        let item = TestData.item()
        let evaluation = SafetyRules.evaluate(.delete, on: item, evaluator: ProtectionEvaluator())

        XCTAssertEqual(evaluation.status, .markedForDeletion)
        XCTAssertEqual(evaluation.result, .applied)
        // La regola è una funzione pura: non modifica e non rimuove l'elemento.
        XCTAssertEqual(item.reviewStatus, .unreviewed)
    }

    func testKeepAndPostponeAreAlwaysAllowed() {
        let favorite = TestData.item(traits: [.favorite])
        let evaluator = ProtectionEvaluator()

        XCTAssertEqual(SafetyRules.evaluate(.keep, on: favorite, evaluator: evaluator).status, .kept)
        XCTAssertEqual(SafetyRules.evaluate(.postpone, on: favorite, evaluator: evaluator).status, .postponed)
    }

    func testFavoritesAreProtectedByDefault() {
        let favorite = TestData.item(traits: [.favorite])
        let evaluation = SafetyRules.evaluate(.delete, on: favorite, evaluator: ProtectionEvaluator())

        XCTAssertNil(evaluation.status)
        XCTAssertEqual(evaluation.result, .blocked(.favorite))
    }

    func testExplicitUnlockAllowsProposingAProtectedFavorite() {
        var favorite = TestData.item(traits: [.favorite])
        favorite.protectionOverride = true
        let evaluation = SafetyRules.evaluate(.delete, on: favorite, evaluator: ProtectionEvaluator())

        XCTAssertEqual(evaluation.status, .markedForDeletion)
    }

    func testUserProtectionAlwaysWins() {
        var item = TestData.item()
        item.isProtected = true
        item.protectionOverride = true
        let evaluation = SafetyRules.evaluate(.delete, on: item, evaluator: ProtectionEvaluator())

        XCTAssertEqual(evaluation.result, .blocked(.userProtected))
    }

    func testSensitiveContentIsFlaggedButNotBlocked() {
        let receipt = TestData.item(traits: [.screenshot, .receipt])
        let evaluation = SafetyRules.evaluate(.delete, on: receipt, evaluator: ProtectionEvaluator())

        XCTAssertEqual(evaluation.status, .markedForDeletion)
        XCTAssertEqual(evaluation.result, .appliedWithCaution)
    }

    func testProtectedAlbumFolderAndPeriodBlockItems() {
        let photo = TestData.item(ageDays: 30)
        var file = TestData.item(source: .iCloudDrive, category: .pdf)
        let folderID = UUID()
        file.folderID = folderID
        let old = TestData.item(ageDays: 400)

        var rules = ProtectionRules()
        rules.protectedFolderIDs = [folderID]
        rules.protectedPeriods = [
            ProtectedPeriod(
                name: "Viaggio",
                start: TestData.now.addingTimeInterval(-410 * 86_400),
                end: TestData.now.addingTimeInterval(-390 * 86_400)
            )
        ]
        let evaluator = ProtectionEvaluator(rules: rules, protectedAlbumMembers: [photo.sourceIdentifier])

        XCTAssertEqual(evaluator.blockReason(for: photo), .protectedAlbum)
        XCTAssertEqual(evaluator.blockReason(for: file), .protectedFolder)
        XCTAssertEqual(evaluator.blockReason(for: old), .protectedPeriod)
        XCTAssertNil(evaluator.blockReason(for: TestData.item(ageDays: 5)))
    }

    // MARK: - Piano di eliminazione

    func testPlanContainsOnlyMarkedAndUnprotectedItems() {
        let marked = TestData.item(status: .markedForDeletion)
        let protectedFavorite = TestData.item(traits: [.favorite], status: .markedForDeletion)
        let untouched = TestData.item()

        let plan = PlanBuilder.build(
            markedItems: [marked, protectedFavorite, untouched],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .disabled,
            canAccessPhotos: true,
            now: TestData.now
        )

        XCTAssertEqual(plan.entries.map { $0.itemID }, [marked.id])
        XCTAssertEqual(Set(plan.exclusions.map { $0.reason }), [.favorite, .notMarked])
    }

    func testCloudOnlyOriginalFreesICloudButNotTheDevice() {
        let item = TestData.item(bytes: 5_000_000, traits: [.cloudOnly], status: .markedForDeletion)
        let plan = PlanBuilder.build(
            markedItems: [item],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .unknown,
            canAccessPhotos: true,
            now: TestData.now
        )

        XCTAssertEqual(plan.deviceBytes, 0)
        XCTAssertEqual(plan.cloudBytes, 5_000_000)
        XCTAssertEqual(plan.conditionalCloudBytes, 0)
        XCTAssertTrue(plan.affectsICloud)
    }

    func testUnknownICloudStateIsReportedAsConditional() {
        let item = TestData.item(bytes: 2_000_000, status: .markedForDeletion)
        let plan = PlanBuilder.build(
            markedItems: [item],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .unknown,
            canAccessPhotos: true,
            now: TestData.now
        )

        XCTAssertEqual(plan.deviceBytes, 2_000_000)
        XCTAssertEqual(plan.cloudBytes, 0)
        XCTAssertEqual(plan.conditionalCloudBytes, 2_000_000)
    }

    func testDisabledICloudPhotosMeansNoCloudEffect() {
        let item = TestData.item(status: .markedForDeletion)
        let plan = PlanBuilder.build(
            markedItems: [item],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .disabled,
            canAccessPhotos: true,
            now: TestData.now
        )

        XCTAssertFalse(plan.affectsICloud)
        XCTAssertEqual(plan.cloudBytes + plan.conditionalCloudBytes, 0)
    }

    func testRevokedPhotoAccessExcludesLibraryItems() {
        let photo = TestData.item(status: .markedForDeletion)
        let file = TestData.item(source: .localFiles, category: .archive, status: .markedForDeletion)
        let plan = PlanBuilder.build(
            markedItems: [photo, file],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .enabled,
            canAccessPhotos: false,
            now: TestData.now
        )

        XCTAssertEqual(plan.entries.map { $0.itemID }, [file.id])
        XCTAssertEqual(plan.exclusions.first?.reason, .accessRevoked)
    }

    // MARK: - Conferma

    private func confirmation(
        for plan: DeletionPlan,
        iCloud: Bool = true,
        sensitive: Bool = true
    ) -> DeletionConfirmation {
        DeletionConfirmation(
            planID: plan.id,
            confirmedAt: TestData.now,
            acknowledgedICloudEffects: iCloud,
            acknowledgedSensitiveItems: sensitive,
            allowPermanentFileDeletion: false
        )
    }

    private func samplePlan(traits: ItemTraits = []) -> DeletionPlan {
        PlanBuilder.build(
            markedItems: [TestData.item(traits: traits, status: .markedForDeletion)],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .enabled,
            canAccessPhotos: true,
            now: TestData.now
        )
    }

    func testValidConfirmationIsAccepted() {
        let plan = samplePlan()
        XCTAssertNoThrow(try plan.validate(confirmation(for: plan), now: TestData.now))
    }

    func testConfirmationRequiresICloudAcknowledgement() {
        let plan = samplePlan()
        XCTAssertThrowsError(try plan.validate(confirmation(for: plan, iCloud: false), now: TestData.now)) { error in
            XCTAssertEqual(error as? ConfirmationError, .iCloudNotAcknowledged)
        }
    }

    func testConfirmationRequiresSensitiveAcknowledgement() {
        let plan = samplePlan(traits: [.documentLike])
        XCTAssertThrowsError(try plan.validate(confirmation(for: plan, sensitive: false), now: TestData.now)) { error in
            XCTAssertEqual(error as? ConfirmationError, .sensitiveNotAcknowledged)
        }
    }

    func testConfirmationOfAnotherPlanIsRejected() {
        let plan = samplePlan()
        let other = samplePlan()
        XCTAssertThrowsError(try plan.validate(confirmation(for: other), now: TestData.now)) { error in
            XCTAssertEqual(error as? ConfirmationError, .planMismatch)
        }
    }

    func testExpiredPlanIsRejected() {
        let plan = samplePlan()
        let later = TestData.now.addingTimeInterval(DeletionPlan.validity + 60)
        XCTAssertThrowsError(try plan.validate(confirmation(for: plan), now: later)) { error in
            XCTAssertEqual(error as? ConfirmationError, .planExpired)
        }
    }

    func testEmptyPlanCannotBeConfirmed() {
        let plan = DeletionPlan(createdAt: TestData.now, entries: [], exclusions: [])
        XCTAssertThrowsError(try plan.validate(confirmation(for: plan), now: TestData.now)) { error in
            XCTAssertEqual(error as? ConfirmationError, .emptyPlan)
        }
    }

    // MARK: - Resoconto

    func testReportCountsOnlyWhatWasActuallyDeleted() {
        let first = TestData.item(bytes: 1_000_000, status: .markedForDeletion)
        let second = TestData.item(bytes: 3_000_000, status: .markedForDeletion)
        let plan = PlanBuilder.build(
            markedItems: [first, second],
            evaluator: ProtectionEvaluator(),
            iCloudPhotos: .enabled,
            canAccessPhotos: true,
            now: TestData.now
        )
        var outcomes = plan.entries.map { ItemOutcome(entry: $0) }
        outcomes[0].state = .deleted
        outcomes[1].state = .failed
        let report = CleanupReport(outcomes: outcomes)

        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.pendingCount, 0)
        // iPhone e iCloud restano separati: gli stessi byte non vengono sommati due volte.
        XCTAssertEqual(report.deviceBytesFreed, 1_000_000)
        XCTAssertEqual(report.cloudBytesFreed, 1_000_000)
    }

    // MARK: - Aggiornamento dei metadati

    func testMetadataRefreshKeepsDecisionsAndAnalysis() {
        var existing = TestData.item(traits: [.screenshot])
        existing.reviewStatus = .kept
        existing.isProtected = true
        existing.traits.insert(.hasText)
        existing.perceptualHash = 42

        var fresh = existing
        fresh.traits = [.screenshot, .favorite]
        existing.applyMetadata(from: fresh)

        XCTAssertEqual(existing.reviewStatus, .kept)
        XCTAssertTrue(existing.isProtected)
        XCTAssertTrue(existing.traits.contains(.hasText))
        XCTAssertTrue(existing.traits.contains(.favorite))
        XCTAssertEqual(existing.perceptualHash, 42)
    }

    func testChangedContentResetsAnalysisButNotDecisions() {
        var existing = TestData.item()
        existing.reviewStatus = .markedForDeletion
        existing.contentHash = "abc"
        existing.traits.insert(.blurry)

        var fresh = existing
        fresh.modifiedAt = TestData.now
        fresh.traits = []
        existing.applyMetadata(from: fresh)

        XCTAssertNil(existing.contentHash)
        XCTAssertFalse(existing.traits.contains(.blurry))
        XCTAssertEqual(existing.analysisStatus, .metadataOnly)
        XCTAssertEqual(existing.reviewStatus, .markedForDeletion)
    }
}
