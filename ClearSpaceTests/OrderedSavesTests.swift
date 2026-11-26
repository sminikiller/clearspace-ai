import XCTest
@testable import ClearSpace

/// I salvataggi di uno stesso file non devono mai lasciare sul disco una copia più vecchia di quella
/// già scritta, anche se due salvataggi partono quasi insieme.
final class OrderedSavesTests: XCTestCase {

    func testAnOlderSnapshotNeverOverwritesANewerOne() {
        let saves = OrderedSaves()
        var disk: [String] = []
        let older = saves.ticket()
        let newer = saves.ticket()

        XCTAssertTrue(saves.perform(ticket: newer) { disk.append("newer") })
        XCTAssertFalse(saves.perform(ticket: older) { disk.append("older") })
        XCTAssertEqual(disk, ["newer"])
    }

    func testSnapshotsInOrderAreAllWritten() {
        let saves = OrderedSaves()
        var disk: [Int] = []
        for value in 1...3 {
            let ticket = saves.ticket()
            saves.perform(ticket: ticket) { disk.append(value) }
        }
        XCTAssertEqual(disk, [1, 2, 3])
    }

    func testConcurrentSavesKeepTheNewestSnapshot() {
        let saves = OrderedSaves()
        let tickets = (0..<50).map { _ in saves.ticket() }
        let lock = NSLock()
        var written: [UInt64] = []
        DispatchQueue.concurrentPerform(iterations: tickets.count) { index in
            let ticket = tickets[index]
            saves.perform(ticket: ticket) {
                lock.lock()
                written.append(ticket)
                lock.unlock()
            }
        }
        // Qualunque sia l'ordine di arrivo, l'ultima scrittura è sempre l'istantanea più recente.
        XCTAssertEqual(written.last, tickets.last)
        XCTAssertEqual(written, written.sorted())
    }
}
