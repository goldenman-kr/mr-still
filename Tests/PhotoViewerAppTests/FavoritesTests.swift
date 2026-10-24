import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class FavoritesTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let suite = "PhotoViewer-FavoritesTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-Favorites-\(UUID().uuidString)", isDirectory: true)
        for child in ["First", "Second"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(child, isDirectory: true), withIntermediateDirectories: true)
        }
        return root
    }

    @MainActor
    func testFavoritesPersistInOrderWithoutDuplicatesAndRemovalSurvivesReload() async throws {
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        let model = BrowserModel(defaults: defaults)
        model.addFavorite(first)
        model.addFavorite(second)
        model.addFavorite(root.appendingPathComponent("First/../First", isDirectory: true))
        XCTAssertEqual(model.favoriteURLs, [first, second])
        XCTAssertEqual(BrowserModel(defaults: defaults).favoriteURLs, [first, second])
        model.removeFavorite(root.appendingPathComponent("Second/../First", isDirectory: true))
        XCTAssertFalse(model.isFavorite(first))
        XCTAssertEqual(BrowserModel(defaults: defaults).favoriteURLs, [second])
    }

    @MainActor
    func testInvalidAdditionsAreIgnoredButSavedUnavailableFavoritesCanBeRemoved() async throws {
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let unavailable = root.appendingPathComponent("Disconnected", isDirectory: true)
        defaults.set([unavailable.path, unavailable.path, "relative/path"], forKey: "favoritePaths")
        let model = BrowserModel(defaults: defaults)
        XCTAssertEqual(model.favoriteURLs, [unavailable])
        let file = root.appendingPathComponent("ordinary.txt")
        try Data().write(to: file)
        model.addFavorite(file)
        model.addFavorite(root.appendingPathComponent("Missing"))
        model.addFavorite(URL(string: "https://example.com/photos")!)
        XCTAssertEqual(model.favoriteURLs, [unavailable])
        model.removeFavorite(unavailable)
        XCTAssertTrue(BrowserModel(defaults: defaults).favoriteURLs.isEmpty)
    }

    @MainActor
    func testSelectingDuplicateFolderKeepsTheClickedTreeBranch() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        try FileManager.default.createDirectory(at: first.appendingPathComponent("Nested", isDirectory: true), withIntermediateDirectories: true)
        let model = BrowserModel(defaults: defaults)
        model.addFavorite(first)
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        let favorites = controller.outlineView(outline, child: 0, ofItem: nil)
        try await waitUntil { outline.isItemExpanded(home) && controller.outlineView(outline, numberOfChildrenOfItem: favorites) == 1 }
        let homeFirst = controller.outlineView(outline, child: 0, ofItem: home) as AnyObject
        let favoriteFirst = controller.outlineView(outline, child: 0, ofItem: favorites) as AnyObject
        for node in [homeFirst, favoriteFirst, homeFirst] {
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: node)), byExtendingSelection: false)
            try await waitUntil { model.folder == first && !model.loading }
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertTrue((outline.item(atRow: outline.selectedRow) as AnyObject?) === node)
            outline.expandItem(node, expandChildren: false)
            try await waitUntil { controller.outlineView(outline, numberOfChildrenOfItem: node) == 1 }
            let nested = controller.outlineView(outline, child: 0, ofItem: node) as AnyObject
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: nested)), byExtendingSelection: false)
            try await waitUntil { model.folder?.lastPathComponent == "Nested" && !model.loading }
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertTrue((outline.item(atRow: outline.selectedRow) as AnyObject?) === nested)
            model.refreshFolder()
            try await waitUntil { !model.loading }
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertTrue((outline.item(atRow: outline.selectedRow) as AnyObject?) === nested)
        }
    }

    @MainActor
    func testSandboxHomeIsVisibleButDoesNotReadOrPromptUntilUsed() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let access = FileAccessController(defaults: defaults, isSandboxed: true)
        var prompts = 0
        access.chooseDirectory = { requested in
            XCTAssertEqual(requested, root)
            prompts += 1
            return nil
        }
        let model = BrowserModel(defaults: defaults, access: access)
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: nil), 2)
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: home), 0)
        XCTAssertFalse(outline.isItemExpanded(home))
        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(controller.outlineView(outline, shouldExpandItem: home))
        XCTAssertEqual(prompts, 1)
        XCTAssertNil(model.folder)
    }

    @MainActor
    func testHomeButtonGrantsOnceAndExpandsOnlyImmediateHomeChildren() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = try fixture()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("First/Nested", isDirectory: true), withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        var operations = FileAccessController.Operations()
        operations.start = { _ in true }
        operations.stop = { _ in }
        operations.create = { Data($0.path.utf8) }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        var prompts = 0
        access.chooseDirectory = { requested in prompts += 1; return requested }
        let model = BrowserModel(defaults: defaults, access: access)
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        func findHomeButton(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.accessibilityLabel() == L10n.format("Folder navigation: %@", L10n.text("Home")) { return button }
            return view.subviews.lazy.compactMap { findHomeButton($0) }.first
        }
        let button = try XCTUnwrap(findHomeButton(controller.view))
        try await waitUntil { button.isEnabled }
        button.performClick(nil)
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        try await waitUntil { model.folder == root && !model.loading && outline.isItemExpanded(home) }
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: nil), 2, "A home grant must not add a duplicate root")
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: home), 2)
        let child = controller.outlineView(outline, child: 0, ofItem: home)
        XCTAssertFalse(outline.isItemExpanded(child))
        model.openFolder(root.appendingPathComponent("First", isDirectory: true))
        try await waitUntil { !model.loading }
        button.performClick(nil)
        try await waitUntil { model.folder == root && !model.loading }
        XCTAssertEqual(prompts, 1)
        access.stopAll()
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Tree update timed out")
    }

    @MainActor
    func testFavoritesHeadingDoubleClickTogglesWithoutOpeningFolder() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = BrowserModel(defaults: defaults)
        model.addFavorite(root)
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let group = controller.outlineView(outline, child: 0, ofItem: nil)
        try await waitUntil { outline.isItemExpanded(group) }
        controller.toggleDirectory(at: outline.row(forItem: group))
        XCTAssertFalse(outline.isItemExpanded(group))
        controller.toggleDirectory(at: outline.row(forItem: group))
        XCTAssertTrue(outline.isItemExpanded(group))
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: group), 1)
        XCTAssertNil(model.folder)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertFalse(controller.outlineView(outline, shouldSelectItem: group))
    }

    @MainActor
    func testFavoritesHeadingIsFirstAndCannotSelectOrEnumerateFilesystem() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        let controller = DirectoryTreeController(model: model)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let group = try XCTUnwrap(controller.outlineView(outline, child: 0, ofItem: nil) as AnyObject?)
        let cell = controller.outlineView(outline, viewFor: nil, item: group) as? NSTableCellView
        XCTAssertEqual(cell?.textField?.stringValue, L10n.text("Favorites"))
        XCTAssertFalse(controller.outlineView(outline, shouldSelectItem: group))
        XCTAssertFalse(controller.outlineView(outline, isItemExpandable: group))
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: group), 0)
        outline.expandItem(group)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: group), 0)
        controller.toggleDirectory(at: outline.row(forItem: group))
        XCTAssertFalse(outline.isItemExpanded(group))
        XCTAssertNil(model.folder)
    }

    @MainActor
    func testDirectoryContextMenuTargetsRightClickedRowWithoutChangingSelection() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        let controller = DirectoryTreeController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: outline.convert(NSPoint(x: 30, y: outline.rect(ofRow: 1).midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(outline.menu(for: event))
        XCTAssertEqual(menu.items.map(\.title), [L10n.text("Add to Favorites"), L10n.text("Open in Finder")])
        XCTAssertEqual(menu.items.first?.representedObject as? URL, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
        XCTAssertNil(model.folder)
        XCTAssertEqual(outline.selectedRow, -1)
        let favoriteAction = try XCTUnwrap(menu.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(favoriteAction.action), to: favoriteAction.target, from: favoriteAction))
        XCTAssertTrue(model.isFavorite(FileManager.default.homeDirectoryForCurrentUser))
        try await Task.sleep(nanoseconds: 30_000_000)
        let removeMenu = try XCTUnwrap(outline.menu(for: event))
        XCTAssertEqual(removeMenu.items.first?.title, L10n.text("Remove from Favorites"))
        let removeAction = try XCTUnwrap(removeMenu.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(removeAction.action), to: removeAction.target, from: removeAction))
        XCTAssertTrue(model.favoriteURLs.isEmpty)
    }

    @MainActor
    func testFileFinderMenuUsesRightClickedFileInsteadOfPreviouslySelectedFile() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First.png"), second = root.appendingPathComponent("Second.png")
        let model = BrowserModel(defaults: defaults)
        model.viewMode = .list
        model.files = [first, second].map { ImageFile(url: $0, size: 0, modified: .distantPast) }
        model.select([first], primary: first)
        let controller = FileBrowserController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        try await Task.sleep(nanoseconds: 50_000_000)
        controller.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendant(NSTableView.self, in: controller.view))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: table.convert(NSPoint(x: 30, y: table.rect(ofRow: 1).midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(table.menu(for: event))
        let finder = try XCTUnwrap(menu.items.first { $0.title == L10n.text("Open in Finder") })
        XCTAssertEqual(finder.representedObject as? [URL], [second])
        XCTAssertEqual(model.selection, [second])
    }

    @MainActor
    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
        return nil
    }
}
