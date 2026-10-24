import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class ViewerPresentationTests: XCTestCase {
    @MainActor
    func testStatusControlsStayAtRightEdgeAtMinimumAndWideWidths() throws {
        _ = NSApplication.shared
        let viewer = ViewerController(model: BrowserModel())
        viewer.loadViewIfNeeded()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = viewer.view
        defer { window.close() }
        for width in [400.0, 1000.0, 1600.0] {
            window.setContentSize(NSSize(width: width, height: 500))
            viewer.view.layoutSubtreeIfNeeded()
            let buttons = descendants(viewer.view).compactMap { $0 as? NSButton }
            let info = try XCTUnwrap(buttons.first { $0.toolTip == L10n.text("Image Info (I)") })
            let frame = info.convert(info.bounds, to: viewer.view)
            XCTAssertEqual(frame.maxX, width - 8, accuracy: 0.5)
            let slider = try XCTUnwrap(descendants(viewer.view).first { $0 is NSSlider })
            XCTAssertGreaterThanOrEqual(slider.convert(slider.bounds, to: viewer.view).minX, 8)
        }
    }

    @MainActor
    func testDoubleClickReturnsFromSlideButEnterDoesNotToggleAndFullscreenDoesNotChangeMode() {
        _ = NSApplication.shared
        let model = BrowserModel()
        let viewer = ViewerController(model: model)
        viewer.loadViewIfNeeded()
        model.slideMode = true
        viewer.canvas.onEnter?()
        XCTAssertTrue(model.slideMode)
        viewer.canvas.onDoubleClick?()
        XCTAssertFalse(model.slideMode)
        for originalMode in [false, true] {
            model.slideMode = originalMode
            viewer.setFullscreen(true)
            viewer.canvas.onDoubleClick?()
            viewer.canvas.onEnter?()
            XCTAssertEqual(model.slideMode, originalMode)
            viewer.setFullscreen(false)
        }
    }

    @MainActor
    func testMetadataTableRetainsEveryEntryAndShowsCompleteLongSelectedValue() {
        _ = NSApplication.shared
        let controller = MetadataInfoController()
        let longValue = String(repeating: "긴 설명과 EXIF 값\n", count: 200)
        let entries = [MetadataEntry(key: "File / Name", value: "photo.jpg"),
                       MetadataEntry(key: "Image / {Exif} / UserComment", value: longValue),
                       MetadataEntry(key: "Image / {GPS} / Latitude", value: "37.5")]
        controller.setEntries(entries)
        XCTAssertEqual(controller.table.numberOfRows, entries.count)
        XCTAssertEqual(controller.table.tableColumns.map(\.title), [L10n.text("Group"), L10n.text("Item"), L10n.text("Value")])
        XCTAssertEqual(controller.rows[1].group, "Image / {Exif}")
        XCTAssertEqual(controller.rows[1].item, "UserComment")
        XCTAssertEqual(controller.rows[1].value, longValue)
        controller.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(controller.valueText.string, longValue)
        XCTAssertFalse(controller.valueText.isEditable)
        XCTAssertTrue(controller.valueText.isSelectable)
        controller.setEntries([])
        XCTAssertEqual(controller.table.numberOfRows, 0)
        XCTAssertEqual(controller.valueText.string, "")
    }

    @MainActor
    func testImageMenuAndClipboardUseImagePixelsAndPlainPath() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a photo.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        let model = BrowserModel()
        let viewer = ViewerController(model: model)
        viewer.loadViewIfNeeded()
        XCTAssertNil(viewer.imageContextMenu())
        model.currentURL = url
        for _ in 0..<200 {
            if viewer.canCopyImage { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let menu = try XCTUnwrap(viewer.imageContextMenu())
        XCTAssertEqual(menu.items.map(\.title), [L10n.text("Copy Image"), L10n.text("Copy File Path"), L10n.text("Open With")])
        XCTAssertEqual(menu.items.first?.keyEquivalent, "c")
        XCTAssertNotNil(menu.items.last?.submenu)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        viewer.copyFilePath(to: clipboard)
        XCTAssertEqual(clipboard.string(forType: .string), url.path)
        XCTAssertNil(clipboard.data(forType: .fileURL))
        viewer.canvas.scale = 0.1
        viewer.copyImage(to: clipboard)
        for _ in 0..<200 {
            if clipboard.availableType(from: [.tiff, .png]) != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let copied = try XCTUnwrap(NSImage(pasteboard: clipboard))
        let pixels = try XCTUnwrap(copied.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(pixels.width, 32)
        XCTAssertEqual(pixels.height, 18)
        XCTAssertNil(clipboard.data(forType: .fileURL))
    }

    @MainActor
    func testOriginalSizeImageStaysOnBackingPixelsThroughResizeAndPan() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let canvas = ImageCanvasView()
        window.contentView!.addSubview(canvas)
        canvas.pixelSize = CGSize(width: 612, height: 1061)
        canvas.scale = 1
        for width in [701.0, 702.0, 702.25, 703.5] {
            for height in [799.0, 800.0, 800.25] {
                canvas.frame = NSRect(x: 0.25, y: 0.25, width: width, height: height)
                for pan in [CGPoint.zero, CGPoint(x: 0.17, y: -0.23)] {
                    canvas.pan = pan
                    let pixels = canvas.convertToBacking(canvas.imageRect)
                    XCTAssertEqual(pixels.minX, pixels.minX.rounded(), accuracy: 0.00001)
                    XCTAssertEqual(pixels.minY, pixels.minY.rounded(), accuracy: 0.00001)
                    XCTAssertEqual(pixels.width, 612, accuracy: 0.00001)
                    XCTAssertEqual(pixels.height, 1061, accuracy: 0.00001)
                }
            }
        }
        XCTAssertEqual(canvas.layerContentsRedrawPolicy, .duringViewResize)
        XCTAssertEqual(canvas.layerContentsPlacement, .center)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}
