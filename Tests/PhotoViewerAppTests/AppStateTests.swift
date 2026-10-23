import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoViewer
import PhotoViewerCore

final class AppStateTests: XCTestCase {
    @MainActor
    private func fixture() throws -> URL {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-AppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        for name in ["1.png", "2.png", "3.png", ".hidden.png"] {
            let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        return directory
    }

    @MainActor
    private func finishLoading(_ model: BrowserModel) async throws {
        for _ in 0..<300 {
            if !model.loading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Directory request did not finish")
    }

    @MainActor
    func testDirectoryRefreshPreservesSelectionMadeWhileRequestWasRunning() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        model.setSort(.name, ascending: true)
        model.openFolder(folder)
        try await finishLoading(model)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "1.png")
        model.openFolder(folder)
        let last = folder.appendingPathComponent("3.png")
        model.select([last], primary: last)
        try await finishLoading(model)
        XCTAssertEqual(model.currentURL, last)
        XCTAssertEqual(model.selection, [last])
    }

    @MainActor
    func testExplicitHiddenFileOpensButMissingRecentFileDoesNotShowAnotherPhoto() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        let hidden = folder.appendingPathComponent(".hidden.png")
        model.openFile(hidden)
        try await finishLoading(model)
        XCTAssertEqual(model.currentURL, hidden)
        model.openFile(folder.appendingPathComponent("missing.png"))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.currentURL, hidden)
    }

    @MainActor
    func testSelectionPrimaryAndNavigationRemainConsistentAfterSorting() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        model.openFolder(folder)
        try await finishLoading(model)
        let a = folder.appendingPathComponent("1.png"), b = folder.appendingPathComponent("2.png")
        model.select([a, b], primary: b)
        XCTAssertEqual(model.currentURL, b)
        model.setSort(.name, ascending: false)
        XCTAssertEqual(model.selection, [a, b])
        XCTAssertEqual(model.currentURL, b)
        model.navigate(1)
        XCTAssertEqual(model.currentURL, a)
        XCTAssertEqual(model.selection.count, 1)
        model.navigate(1)
        XCTAssertEqual(model.currentURL, a)
    }

    @MainActor
    func testSlideAndFullscreenRemoveSplitDividerFromViewerHierarchy() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        let controller = MainWindowController(model: model)
        defer { controller.window?.close() }
        let window = try XCTUnwrap(controller.window)
        let host = try XCTUnwrap(controller.viewer.view.superview)
        let split = try XCTUnwrap(host.superview as? NSSplitView)
        for width: CGFloat in [1200, 1352, 684, 800] {
            window.setContentSize(NSSize(width: width, height: 800))
            let leftWidth = controller.tree.view.frame.width
            model.slideMode = true
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(controller.viewer.view.superview === window.contentView)
            XCTAssertFalse(controller.viewer.view.superview is NSSplitView)
            XCTAssertTrue(split.isHidden)
            XCTAssertEqual(split.arrangedSubviews.count, 2)
            XCTAssertEqual(controller.viewer.view.frame, window.contentView!.bounds)
            model.slideMode = false
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(controller.viewer.view.superview === host)
            XCTAssertFalse(split.isHidden)
            XCTAssertEqual(controller.tree.view.frame.width, leftWidth, accuracy: 1)
        }
        let event = Notification(name: NSWindow.willEnterFullScreenNotification, object: window)
        controller.windowWillEnterFullScreen(event)
        XCTAssertTrue(controller.viewer.view.superview === window.contentView)
        XCTAssertTrue(split.isHidden)
        controller.windowDidExitFullScreen(event)
        XCTAssertTrue(controller.viewer.view.superview === host)
    }

    @MainActor
    func testBrowserDoubleClickUsesClickedImageAndMatchesViewerDoubleClick() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        for mode in FileViewMode.allCases {
            let model = BrowserModel()
            model.viewMode = mode
            let controller = MainWindowController(model: model)
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            model.openFile(folder.appendingPathComponent("1.png"))
            try await finishLoading(model)
            try await Task.sleep(nanoseconds: 30_000_000)
            let clicked = folder.appendingPathComponent("3.png")
            let index = try XCTUnwrap(model.files.firstIndex { $0.url == clicked })
            controller.browser.activateItem(at: index)
            try await Task.sleep(nanoseconds: 30_000_000)
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(model.currentURL, clicked)
            XCTAssertEqual(model.selection, [clicked])
            XCTAssertTrue(model.slideMode)
            let browserEntryFrame = controller.viewer.view.frame
            controller.viewer.canvas.onDoubleClick?()
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertFalse(model.slideMode)
            controller.viewer.canvas.onDoubleClick?()
            try await Task.sleep(nanoseconds: 30_000_000)
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertTrue(model.slideMode)
            XCTAssertEqual(controller.viewer.view.frame, browserEntryFrame)
            XCTAssertEqual(controller.viewer.view.frame, window.contentView!.bounds)
        }
    }

    @MainActor
    func testBrowserActivationSurvivesResizingAndFullscreenRoundTrips() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        let controller = MainWindowController(model: model)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.setContentSize(NSSize(width: 1200, height: 800))
        model.openFile(folder.appendingPathComponent("2.png"))
        try await finishLoading(model)
        let leftWidth = controller.tree.view.frame.width
        let notification = Notification(name: NSWindow.willEnterFullScreenNotification, object: window)
        for _ in 0..<3 {
            // Screen 2 Enter/double-click activates the selected image.
            model.activateSelection()
            try await Task.sleep(nanoseconds: 30_000_000)
            for size in [NSSize(width: 1600, height: 1000), NSSize(width: 420, height: 340)] {
                window.setContentSize(size)
                window.contentView!.layoutSubtreeIfNeeded()
                XCTAssertEqual(controller.viewer.view.frame, window.contentView!.bounds)
                XCTAssertEqual(controller.tree.view.frame.width, leftWidth, accuracy: 1)
            }
            controller.windowWillEnterFullScreen(notification)
            window.setContentSize(NSSize(width: 1920, height: 1080))
            controller.windowDidEnterFullScreen(notification)
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(controller.viewer.view.frame, window.contentView!.bounds)
            controller.windowWillExitFullScreen(notification)
            window.setContentSize(NSSize(width: 1200, height: 800))
            controller.windowDidExitFullScreen(notification)
            controller.viewer.canvas.onDoubleClick?()
            try await Task.sleep(nanoseconds: 30_000_000)
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertFalse(model.slideMode)
            XCTAssertEqual(controller.tree.view.frame.width, leftWidth, accuracy: 1)
            XCTAssertEqual(controller.viewer.view.frame.width, 1200 - leftWidth - 4, accuracy: 1)
            XCTAssertEqual(model.currentURL?.lastPathComponent, "2.png")
        }
    }

    @MainActor
    func testFullscreenRestoresOriginModeEvenWhenModeChangesInsideFullscreen() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        let controller = MainWindowController(model: model)
        defer { controller.window?.close() }
        let notification = Notification(name: NSWindow.willEnterFullScreenNotification, object: controller.window)
        for originalMode in [false, true] {
            model.slideMode = originalMode
            controller.windowWillEnterFullScreen(notification)
            controller.windowDidEnterFullScreen(notification)
            model.slideMode = !originalMode
            controller.windowWillExitFullScreen(notification)
            controller.windowDidExitFullScreen(notification)
            XCTAssertEqual(model.slideMode, originalMode)
        }
    }

    @MainActor
    func testFullscreenHoverDoesNotResizeCanvasOrChangeFit() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel()
        let controller = MainWindowController(model: model)
        defer { controller.window?.close() }
        model.openFolder(folder)
        try await finishLoading(model)
        for _ in 0..<300 where controller.viewer.canvas.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(controller.viewer.canvas.image)
        try capture(controller.viewer.view, name: "viewer.png")
        controller.viewer.setFullscreen(true)
        controller.viewer.view.layoutSubtreeIfNeeded()
        controller.viewer.updateFullscreenHover(at: nil)
        let frame = controller.viewer.canvas.frame
        let scale = controller.viewer.canvas.scale
        XCTAssertFalse(controller.viewer.isStatusBarVisible)
        controller.viewer.updateFullscreenHover(at: NSPoint(x: 20, y: 10))
        controller.viewer.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.viewer.isStatusBarVisible)
        XCTAssertEqual(controller.viewer.canvas.frame, frame)
        XCTAssertEqual(controller.viewer.canvas.scale, scale)
        try capture(controller.viewer.view, name: "fullscreen-overlay.png")
        controller.viewer.updateFullscreenHover(at: NSPoint(x: 20, y: 200))
        XCTAssertFalse(controller.viewer.isStatusBarVisible)
        XCTAssertEqual(controller.viewer.canvas.frame, frame)
        controller.viewer.setFullscreen(false)
        XCTAssertTrue(controller.viewer.isStatusBarVisible)
    }

    @MainActor
    private func capture(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PHOTOVIEWER_CAPTURE_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return XCTFail("Snapshot bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("Snapshot encoding failed") }
        try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(name))
    }
}
