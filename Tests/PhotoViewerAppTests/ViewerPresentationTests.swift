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
            let info = try XCTUnwrap(buttons.first { $0.toolTip == "이미지 정보 (I)" })
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
        XCTAssertEqual(controller.table.tableColumns.map(\.title), ["그룹", "항목", "값"])
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
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}
