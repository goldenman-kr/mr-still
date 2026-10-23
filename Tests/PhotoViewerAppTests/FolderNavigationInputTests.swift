import XCTest
import AppKit
@testable import PhotoViewer

private final class SideButtonEvent: NSEvent {
    var targetWindow: NSWindow?
    var number = 3
    var mouseType: NSEvent.EventType = .otherMouseDown
    override var window: NSWindow? { targetWindow }
    override var buttonNumber: Int { number }
    override var type: NSEvent.EventType { mouseType }
}

final class FolderNavigationInputTests: XCTestCase {
    private func key(_ code: UInt16, window: NSWindow? = nil, modifiers: NSEvent.ModifierFlags = .option, repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                        isARepeat: repeating, keyCode: code)!
    }

    @MainActor
    func testOptionArrowsPreserveOtherBindingsAndTextEditing() {
        _ = NSApplication.shared
        XCTAssertEqual(FolderNavigationInput.action(for: key(123), firstResponder: nil), .back)
        XCTAssertEqual(FolderNavigationInput.action(for: key(124, modifiers: [.option, .function, .numericPad]), firstResponder: nil), .forward)
        for flags: NSEvent.ModifierFlags in [[], .command, .control, [.option, .shift], [.option, .command]] {
            XCTAssertNil(FolderNavigationInput.action(for: key(123, modifiers: flags), firstResponder: nil))
        }
        XCTAssertNil(FolderNavigationInput.action(for: key(125), firstResponder: nil))
        let editor = NSTextView()
        XCTAssertNil(FolderNavigationInput.action(for: key(123), firstResponder: editor))
        XCTAssertNil(FolderNavigationInput.action(for: key(124), firstResponder: NSTextField(string: "100")))
        editor.isEditable = false
        XCTAssertEqual(FolderNavigationInput.action(for: key(123), firstResponder: editor), .back)
    }

    @MainActor
    func testNativeSideButtonNumbersAndMiddleButtonExclusion() throws {
        _ = NSApplication.shared
        // Construct in-memory events only; never post input to the user's desktop.
        for number: UInt32 in [2, 3, 4, 5] {
            let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                          mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: number)!))
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(event.buttonNumber, Int(number))
            let expected: FolderNavigationInput? = number == 3 ? .back : number == 4 ? .forward : nil
            XCTAssertEqual(FolderNavigationInput.action(for: event, firstResponder: nil), expected)
        }
    }

    @MainActor
    func testWindowWideNavigationAndHeaderButtonsShareHistory() async throws {
        _ = NSApplication.shared
        let suite = "PhotoViewer-NavigationInput-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let a = root.appendingPathComponent("A", isDirectory: true)
        let b = root.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let model = BrowserModel(defaults: defaults)
        let controller = MainWindowController(model: model)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        model.openFolder(a); try await settle(model)
        model.openFolder(b); try await settle(model)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.tree.view))
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: controller.browser.view))
        let header = try XCTUnwrap(descendant(NSBox.self, in: controller.tree.view))
        let back = try XCTUnwrap(button(named: "폴더 뒤로", in: header))
        let forward = try XCTUnwrap(button(named: "폴더 앞으로", in: header))
        controller.tree.view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(back.frame.maxX, forward.frame.minX)
        let up = try XCTUnwrap(button(named: "폴더 위로", in: header))
        let reload = try XCTUnwrap(button(named: "폴더 새로고침", in: header))
        for button in [back, forward, up, reload] { XCTAssertFalse(button.isBordered) }
        XCTAssertLessThanOrEqual(forward.frame.maxX, up.frame.minX)
        XCTAssertLessThanOrEqual(up.frame.maxX, reload.frame.minX)
        XCTAssertTrue(up.isEnabled)
        XCTAssertTrue(reload.isEnabled)
        XCTAssertTrue(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)
        back.performClick(nil); try await settle(model)
        XCTAssertEqual(model.folder, a)
        XCTAssertFalse(back.isEnabled)
        XCTAssertTrue(forward.isEnabled)
        forward.performClick(nil); try await settle(model)
        XCTAssertEqual(model.folder, b)

        for responder in [outline as NSResponder, collection, controller.viewer.canvas] {
            window.makeFirstResponder(responder)
            XCTAssertTrue(controller.handleFolderNavigation(key(123, window: window)))
            try await settle(model)
            XCTAssertEqual(model.folder, a)
            XCTAssertTrue(controller.handleFolderNavigation(key(124, window: window)))
            try await settle(model)
            XCTAssertEqual(model.folder, b)
        }
        let mouse = SideButtonEvent()
        mouse.targetWindow = window
        for slide in [false, true] {
            model.slideMode = slide
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(controller.handleFolderNavigation(mouse))
            try await settle(model)
            XCTAssertEqual(model.folder, a)
            mouse.mouseType = .otherMouseUp
            XCTAssertTrue(controller.handleFolderNavigation(mouse))
            XCTAssertFalse(model.loading)
            mouse.mouseType = .otherMouseDown; mouse.number = 4
            XCTAssertTrue(controller.handleFolderNavigation(mouse))
            try await settle(model)
            XCTAssertEqual(model.folder, b)
            XCTAssertEqual(model.slideMode, slide)
            mouse.number = 3
        }
        controller.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification, object: window))
        controller.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification, object: window))
        XCTAssertTrue(controller.handleFolderNavigation(key(123, window: window)))
        try await settle(model)
        XCTAssertEqual(model.folder, a)
        // No history in this direction: still consume, preventing photo navigation.
        XCTAssertTrue(controller.handleFolderNavigation(key(123, window: window)))
        XCTAssertFalse(model.loading)
        XCTAssertTrue(controller.handleFolderNavigation(key(124, window: window, repeating: true)))
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.folder, a)
        controller.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        XCTAssertFalse(controller.handleFolderNavigation(key(124)))
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet, completionHandler: nil)
        XCTAssertFalse(controller.handleFolderNavigation(key(124, window: window)))
        window.endSheet(sheet); sheet.close()
    }

    @MainActor
    private func settle(_ model: BrowserModel) async throws {
        for _ in 0..<300 {
            if !model.loading {
                try await Task.sleep(nanoseconds: 20_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Folder load timed out")
    }

    @MainActor
    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
        return nil
    }

    @MainActor
    private func button(named name: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityLabel() == name { return button }
        for child in view.subviews { if let found = button(named: name, in: child) { return found } }
        return nil
    }
}
