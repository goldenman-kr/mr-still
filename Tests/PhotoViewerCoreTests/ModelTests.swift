import XCTest
import CoreGraphics
@testable import PhotoViewerCore

final class ModelTests: XCTestCase {
    func testFilenameSortUsesFinderStyleNumericOrderInBothDirections() {
        let files = [file("photo10.jpg"), file("photo2.jpg"), file("photo1.jpg")]
        XCTAssertEqual(FileOrdering.sorted(files, by: .name, ascending: true).map(\.name), ["photo1.jpg", "photo2.jpg", "photo10.jpg"])
        XCTAssertEqual(FileOrdering.sorted(files, by: .name, ascending: false).map(\.name), ["photo10.jpg", "photo2.jpg", "photo1.jpg"])
    }

    func testDateAndSizeTiesProduceRepeatableNaturalOrderAfterFolderRefresh() {
        let first = file("photo2.jpg", size: 100, seconds: 1)
        let second = file("photo10.jpg", size: 100, seconds: 1)
        let last = file("photo1.jpg", size: 200, seconds: 2)
        for key in [FileSortKey.date, .size] {
            for snapshot in [[last, second, first], [first, last, second], [second, first, last]] {
                XCTAssertEqual(FileOrdering.sorted(snapshot, by: key, ascending: true), [first, second, last])
                XCTAssertEqual(FileOrdering.sorted(snapshot, by: key, ascending: false), [last, second, first])
            }
        }
    }

    func testSameNameFromDifferentPathsHasDeterministicTieBreak() {
        let a = file("a/photo.jpg")
        let b = file("b/photo.jpg")
        for key in FileSortKey.allCases {
            XCTAssertEqual(FileOrdering.sorted([b, a], by: key, ascending: true), [a, b])
            XCTAssertEqual(FileOrdering.sorted([a, b], by: key, ascending: false), [b, a])
        }
    }

    func testFitUsesBackingPixelsAndNeverUpscalesSmallImages() {
        let viewport = CGSize(width: 800, height: 600)
        let large = CGSize(width: 2400, height: 1200)
        XCTAssertEqual(ZoomMath.fit(image: large, viewport: viewport, backingScale: 1), 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(ZoomMath.fit(image: large, viewport: viewport, backingScale: 2), 2.0 / 3.0, accuracy: 1e-12)
        for backingScale in [CGFloat(1), CGFloat(2)] {
            XCTAssertEqual(ZoomMath.fit(image: CGSize(width: 200, height: 100), viewport: viewport, backingScale: backingScale), 1)
        }
    }

    func testPortraitOrientationFitsHeightAfterDimensionsAreRotated() {
        let viewport = CGSize(width: 800, height: 600)
        let portrait = CGSize(width: 1200, height: 2400)
        XCTAssertEqual(ZoomMath.fit(image: portrait, viewport: viewport, backingScale: 1), 0.25)
        XCTAssertEqual(ZoomMath.fit(image: portrait, viewport: viewport, backingScale: 2), 0.5)
    }

    func testHugePanoramaFitsBelowOnePercentWithoutBeingClamped() {
        let scale = ZoomMath.fit(image: CGSize(width: 1_000_000, height: 10_000), viewport: CGSize(width: 500, height: 400), backingScale: 2)
        XCTAssertEqual(scale, 0.001, accuracy: 1e-12)
        XCTAssertEqual(ZoomMath.percentText(scale), "0.1")
    }

    func testManualPercentAcceptsFractionsWhitespaceAndOptionalSuffix() throws {
        for (input, expected) in [("12.5", 0.125), (" 12.5%\n", 0.125), ("0.001 %", 0.00001), ("300", 3.0), ("0.00000001", 1e-10)] {
            XCTAssertEqual(try XCTUnwrap(ZoomMath.parsePercent(input), input), expected, accuracy: expected * 1e-12)
        }
    }

    func testInvalidPercentCannotSetZeroNegativeNonfiniteOrOversizedZoom() {
        for input in ["", " ", "%", "0", "-1", "300.0001", "NaN", "nan", "inf", "-inf", "1e309", "12%5", "25%%", "%25", "1.2.3", "5e-324"] {
            XCTAssertNil(ZoomMath.parsePercent(input), "Unexpectedly accepted \(input)")
        }
    }

    func testDisplayedPercentUsesAtMostTwoDecimalsWithoutRoundingInternalScale() throws {
        XCTAssertEqual(ZoomMath.percentText(1), "100")
        XCTAssertEqual(ZoomMath.percentText(3), "300")
        XCTAssertEqual(ZoomMath.percentText(0.125), "12.5")
        XCTAssertEqual(ZoomMath.percentText(1.0 / 3), "33.33")
        XCTAssertEqual(ZoomMath.percentText(0.123456), "12.35")
        XCTAssertEqual(ZoomMath.percentText(0.0001), "0.01")
        XCTAssertEqual(ZoomMath.percentText(0.000001), "<0.01")
        XCTAssertEqual(try XCTUnwrap(ZoomMath.parsePercent("12.3456")), 0.123456, accuracy: 1e-12)
    }

    func testWindowResizeConsumesViewerSpaceBeforeReducingLeftPane() {
        let unchanged = LayoutMath.leftWidth(total: 1000, previous: 360)
        XCTAssertEqual(unchanged, 360)
        let atViewerMinimum = LayoutMath.leftWidth(total: 761, previous: unchanged)
        XCTAssertEqual(atViewerMinimum, 360)
        let shrinkingLeft = LayoutMath.leftWidth(total: 721, previous: atViewerMinimum)
        XCTAssertEqual(shrinkingLeft, 320)
        XCTAssertEqual(721 - shrinkingLeft - 1, LayoutMath.rightMinimum)
        let atBothMinima = LayoutMath.leftWidth(total: 681, previous: shrinkingLeft)
        XCTAssertEqual(atBothMinima, LayoutMath.leftMinimum)
        XCTAssertEqual(LayoutMath.leftWidth(total: 1200, previous: atBothMinima), LayoutMath.leftMinimum)
    }

    func testDividerThicknessAndStaleSavedWidthRespectPaneMinimum() {
        XCTAssertEqual(LayoutMath.leftWidth(total: 686, previous: 360, divider: 6), 280)
        XCTAssertEqual(LayoutMath.leftWidth(total: 1000, previous: 200), 280)
    }

    private func file(_ path: String, size: Int64 = 100, seconds: TimeInterval = 1) -> ImageFile {
        ImageFile(url: URL(fileURLWithPath: "/photos").appendingPathComponent(path), size: size, modified: Date(timeIntervalSince1970: seconds))
    }
}
