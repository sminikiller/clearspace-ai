import XCTest
@testable import ClearSpace

/// Le dimensioni devono seguire le convenzioni italiane qualunque sia la lingua del dispositivo
/// e non devono mai presentare come vuoto ciò che occupa spazio.
final class FormatTests: XCTestCase {

    func testEmptyOrInvalidSizesAreShownAsZero() {
        XCTAssertEqual(Format.bytes(0), "0 KB")
        XCTAssertEqual(Format.bytes(nil), "0 KB")
        XCTAssertEqual(Format.bytes(-5), "0 KB")
        XCTAssertEqual(Format.bytesOrUnknown(nil), "—")
    }

    func testANonEmptySizeNeverLooksEmpty() {
        XCTAssertEqual(Format.bytes(1), "1 KB")
        XCTAssertEqual(Format.bytes(300), "1 KB")
    }

    func testSizesUseTheDecimalCommaAndDropTrailingZeros() {
        XCTAssertEqual(Format.bytes(512_000), "512 KB")
        XCTAssertEqual(Format.bytes(2_800_000), "2,8 MB")
        XCTAssertEqual(Format.bytes(5_000_000), "5 MB")
        XCTAssertEqual(Format.bytes(1_250_000_000), "1,25 GB")
        XCTAssertEqual(Format.bytes(46_310_000_000), "46,3 GB")
        XCTAssertEqual(Format.bytes(1_050_000_000_000), "1,05 TB")
    }

    func testValuesThatWouldRoundToOneThousandMoveToTheNextUnit() {
        XCTAssertEqual(Format.bytes(999_400), "999 KB")
        XCTAssertEqual(Format.bytes(999_700), "1 MB")
        XCTAssertEqual(Format.bytes(999_970_000), "1 GB")
    }

    func testHighlightedValuesAdaptBelowOneGigabyte() {
        // Una libreria piccola non deve comparire come "0,0 GB".
        XCTAssertEqual(Format.gigabytes(12_900_000), "12,9 MB")
        XCTAssertEqual(Format.gigabytes(0), "0 KB")
        XCTAssertEqual(Format.gigabytes(296_400_000_000), "296,4 GB")
        XCTAssertEqual(Format.gigabytes(64_000_000_000), "64 GB")
    }

    func testMegapixelsUseTheDecimalComma() {
        XCTAssertEqual(Format.megapixels(width: 4288, height: 2848), "4288 × 2848 (12,2 MP)")
        XCTAssertEqual(Format.megapixels(width: 0, height: 100), "—")
    }
}
