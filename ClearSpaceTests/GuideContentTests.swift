import XCTest
@testable import ClearSpace

/// La guida completa e i tutorial: niente capitoli vuoti, ogni categoria spiegata, esercizi coerenti
/// e collegati a un'azione reale dell'app o segnabili a mano.
final class GuideContentTests: XCTestCase {

    func testEveryCategoryIsExplainedInTheGuide() throws {
        let chapter = try XCTUnwrap(GuideBook.chapter("categories"))
        let text = chapter.searchableText
        for collection in SmartCollection.allCases {
            XCTAssertFalse(GuideBook.explanation(of: collection).isEmpty, "\(collection)")
            XCTAssertTrue(text.contains(collection.title), "Nella guida manca la categoria «\(collection.title)»")
        }
    }

    func testChaptersAreCompleteAndUnique() {
        let ids = GuideBook.chapters.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Capitoli con lo stesso identificativo")
        XCTAssertGreaterThanOrEqual(GuideBook.chapters.count, 25)
        for chapter in GuideBook.chapters {
            XCTAssertFalse(chapter.sections.isEmpty, chapter.id)
            for section in chapter.sections {
                XCTAssertFalse(
                    section.paragraphs.isEmpty && section.points.isEmpty,
                    "Sezione vuota: \(chapter.id) / \(section.title)"
                )
            }
            if let tutorialID = chapter.tutorialID {
                XCTAssertNotNil(TutorialCatalog.tutorial(tutorialID), "\(chapter.id) rimanda a un tutorial inesistente")
            }
        }
    }

    func testTutorialsAreConsistent() {
        let ids = TutorialCatalog.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        var taskIDs = Set<String>()
        for tutorial in TutorialCatalog.all {
            XCTAssertNotNil(GuideBook.chapter(tutorial.chapterID), "\(tutorial.id) rimanda a un capitolo inesistente")
            XCTAssertFalse(tutorial.tasks.isEmpty, tutorial.id)
            for task in tutorial.tasks {
                XCTAssertTrue(taskIDs.insert(task.id).inserted, "Esercizio ripetuto: \(task.id)")
                XCTAssertFalse(task.howTo.isEmpty, task.id)
                XCTAssertFalse(task.check.isEmpty, task.id)
            }
        }
    }

    func testEveryRecordedActionBelongsToAnExercise() {
        let used = Set(TutorialCatalog.all.flatMap { tutorial in tutorial.tasks.compactMap { $0.event } })
        // La lettura della guida viene registrata ma non è un esercizio.
        let unused = Set(TutorialEvent.allCases).subtracting(used).subtracting([.readGuide])
        XCTAssertTrue(unused.isEmpty, "Azioni registrate che nessun esercizio usa: \(unused.map { $0.rawValue })")
    }

    func testStorageKeysDoNotCollide() {
        let eventKeys = TutorialEvent.allCases.map { $0.storageID }
        let manualKeys = TutorialCatalog.all.flatMap { tutorial in tutorial.tasks.map { $0.manualStorageID } }
        XCTAssertEqual(Set(eventKeys).count, eventKeys.count)
        XCTAssertEqual(Set(manualKeys).count, manualKeys.count)
        XCTAssertTrue(Set(eventKeys).isDisjoint(with: manualKeys))
        // Non si confondono con le spunte della pulizia guidata («guided.…») e dell'assistente app.
        XCTAssertTrue((eventKeys + manualKeys).allSatisfy { $0.hasPrefix("tutorial.") })
    }

    func testOnlyTabsOpenByChangingTab() {
        XCTAssertTrue(GuideDestination.reviewTab.isTab)
        XCTAssertFalse(GuideDestination.similarGroups.isTab)
        XCTAssertFalse(GuideDestination.allPhotos.title.isEmpty)
    }
}
