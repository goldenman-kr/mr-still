import XCTest
import AppKit
@testable import PhotoViewer

final class PrintTests: XCTestCase {
    @MainActor
    private func image() throws -> CGImage {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8,
                                             bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        return try XCTUnwrap(context.makeImage())
    }

    @MainActor
    private func printInfo(paper: NSSize = NSSize(width: 600, height: 800)) -> NSPrintInfo {
        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = paper
        info.leftMargin = 20
        info.rightMargin = 20
        info.topMargin = 40
        info.bottomMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        return info
    }

    @MainActor
    func testSinglePageRecalculatesWhenPaperAndMarginsChange() async throws {
        let previousOperation = NSPrintOperation.current
        NSPrintOperation.current = nil
        defer { NSPrintOperation.current = previousOperation }
        let info = printInfo()
        let view = PrintedPhotoView(image: try image(), printInfo: info)
        var range = NSRange(location: 0, length: 0)
        XCTAssertTrue(view.knowsPageRange(&range))
        XCTAssertEqual(range, NSRange(location: 1, length: 1))
        XCTAssertEqual(view.rectForPage(1).size, NSSize(width: 560, height: 720))

        info.orientation = .landscape
        info.paperSize = NSSize(width: 900, height: 650)
        info.leftMargin = 35
        info.rightMargin = 45
        info.topMargin = 25
        info.bottomMargin = 55
        XCTAssertTrue(view.knowsPageRange(&range))
        XCTAssertEqual(range, NSRange(location: 1, length: 1))
        XCTAssertEqual(view.frame.size, NSSize(width: 820, height: 570))
        XCTAssertEqual(view.rectForPage(1), view.bounds)
    }

    @MainActor
    func testFinalOperationSettingsOverrideInitialViewSettings() async throws {
        let previousOperation = NSPrintOperation.current
        NSPrintOperation.current = nil
        defer { NSPrintOperation.current = previousOperation }
        let original = printInfo()
        let view = PrintedPhotoView(image: try image(), printInfo: original)
        let operation = NSPrintOperation(view: view, printInfo: original)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        NSPrintOperation.current = operation
        operation.printInfo.paperSize = NSSize(width: 1000, height: 700)
        operation.printInfo.leftMargin = 60
        operation.printInfo.rightMargin = 70
        operation.printInfo.topMargin = 30
        operation.printInfo.bottomMargin = 50
        var range = NSRange()
        XCTAssertTrue(view.knowsPageRange(&range))
        XCTAssertEqual(range, NSRange(location: 1, length: 1))
        XCTAssertEqual(view.rectForPage(1).size, NSSize(width: 870, height: 620))
        XCTAssertEqual(original.paperSize, NSSize(width: 600, height: 800))
    }

    @MainActor
    func testPortraitAndLandscapeSaveOneCenteredAspectFitPDFPage() async throws {
        let previousOperation = NSPrintOperation.current
        NSPrintOperation.current = nil
        defer { NSPrintOperation.current = previousOperation }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-PrintTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try image()

        for (name, paper) in [("portrait", NSSize(width: 600, height: 800)), ("landscape", NSSize(width: 800, height: 600))] {
            NSPrintOperation.current = nil
            // Build with the initial portrait settings, then change the operation's
            // copied settings exactly as a print panel does before rendering.
            let initial = printInfo()
            let view = PrintedPhotoView(image: source, printInfo: initial)
            let operation = NSPrintOperation(view: view, printInfo: initial)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            let final = operation.printInfo
            final.orientation = name == "landscape" ? .landscape : .portrait
            final.paperSize = paper
            final.jobDisposition = .save
            let output = directory.appendingPathComponent("\(name).pdf")
            final.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
            XCTAssertTrue(operation.run(), "PDF save failed for \(name)")

            let document = try XCTUnwrap(CGPDFDocument(output as CFURL))
            XCTAssertEqual(document.numberOfPages, 1)
            let page = try XCTUnwrap(document.page(at: 1))
            let media = page.getBoxRect(.mediaBox)
            XCTAssertEqual(media.width, paper.width, accuracy: 0.5)
            XCTAssertEqual(media.height, paper.height, accuracy: 0.5)
            let colored = try coloredBounds(on: page, media: media)
            let available = NSSize(width: paper.width - 40, height: paper.height - 80)
            let fit = min(available.width / 400, available.height / 200)
            XCTAssertEqual(colored.width, 400 * fit, accuracy: 3, "Photo should maximally fit the selected paper")
            XCTAssertEqual(colored.height, 200 * fit, accuracy: 3, "Photo aspect must stay 2:1")
            XCTAssertEqual(colored.midX, paper.width / 2, accuracy: 2)
            XCTAssertEqual(colored.midY, paper.height / 2, accuracy: 2)
        }
    }

    private func coloredBounds(on page: CGPDFPage, media: CGRect) throws -> CGRect {
        let width = Int(media.width), height = Int(media.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(media)
        context.drawPDFPage(page)
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var left = width, right = -1, bottom = height, top = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = y * context.bytesPerRow + x * 4
                if bytes[index] > 180 && bytes[index + 1] < 80 && bytes[index + 2] < 80 {
                    left = min(left, x); right = max(right, x)
                    bottom = min(bottom, y); top = max(top, y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(right, left, "PDF must contain the photo")
        return CGRect(x: left, y: bottom, width: max(0, right - left + 1), height: max(0, top - bottom + 1))
    }
}
