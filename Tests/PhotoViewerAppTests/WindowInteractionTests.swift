import XCTest
import AppKit
@testable import PhotoViewer

final class WindowInteractionTests: XCTestCase {
    private func key(_ code: UInt16, text: String, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false, window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: window?.windowNumber ?? 0, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: repeating, keyCode: code)!
    }

    @MainActor
    func testPhysicalShortcutsMatchEnglishAndKoreanInput() {
        _ = NSApplication.shared
        for text in ["i", "ㅑ", "I"] {
            XCTAssertEqual(ViewingShortcut.action(for: key(34, text: text), firstResponder: nil), .info)
        }
        for text in ["f", "ㄹ", "F"] {
            XCTAssertEqual(ViewingShortcut.action(for: key(3, text: text), firstResponder: nil), .fullscreen)
        }
        XCTAssertNil(ViewingShortcut.action(for: key(0, text: "i"), firstResponder: nil))
        XCTAssertEqual(ViewingShortcut.action(for: key(3, text: "F", modifiers: .capsLock), firstResponder: nil), .fullscreen)
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            XCTAssertNil(ViewingShortcut.action(for: key(3, text: "ㄹ", modifiers: modifier), firstResponder: nil))
        }
    }

    @MainActor
    func testShortcutsPreserveEditableTextAndAllowMetadataSelection() {
        _ = NSApplication.shared
        let editor = NSTextView()
        let field = NSTextField(string: "100")
        for code: UInt16 in [34, 3] {
            XCTAssertNil(ViewingShortcut.action(for: key(code, text: "ㄹ"), firstResponder: editor))
            XCTAssertNil(ViewingShortcut.action(for: key(code, text: "ㄹ"), firstResponder: field))
        }
        editor.isEditable = false
        XCTAssertEqual(ViewingShortcut.action(for: key(34, text: "ㅑ"), firstResponder: editor), .info)
    }

    @MainActor
    func testShortcutMonitorRejectsOtherWindowsAndConsumesHeldKeysInBothModes() async throws {
        _ = NSApplication.shared
        let controller = MainWindowController(model: BrowserModel())
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: .titled, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close(); controller.window?.close() }
        XCTAssertFalse(controller.handleViewingShortcut(key(3, text: "ㄹ", window: other)))
        for slide in [false, true] {
            controller.model.slideMode = slide
            try await Task.sleep(nanoseconds: 20_000_000)
            // A held F must be consumed without issuing a second fullscreen request.
            XCTAssertTrue(controller.handleViewingShortcut(key(3, text: "ㄹ", repeating: true, window: controller.window)))
        }
    }

    @MainActor
    func testWiderDividersPreserveAllPaneMinimums() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(model: BrowserModel())
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let host = try XCTUnwrap(controller.viewer.view.superview)
        let outer = try XCTUnwrap(host.superview as? NSSplitView)
        let left = try XCTUnwrap(controller.tree.view.superview as? NSSplitView)
        XCTAssertEqual(outer.dividerThickness, 4)
        XCTAssertEqual(left.dividerThickness, 4)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 684, height: 404))
        window.setContentSize(window.contentMinSize)
        XCTAssertEqual(controller.tree.view.frame.width, 280, accuracy: 0.5)
        XCTAssertEqual(controller.viewer.view.frame.width, 400, accuracy: 0.5)
        XCTAssertEqual(controller.tree.view.frame.height, 160, accuracy: 0.5)
        XCTAssertEqual(controller.browser.view.frame.height, 240, accuracy: 0.5)
        XCTAssertEqual(host.frame.minX - left.frame.maxX, 4, accuracy: 0.5)
        XCTAssertEqual(controller.browser.view.frame.minY - controller.tree.view.frame.maxY, 4, accuracy: 0.5)
    }
}
