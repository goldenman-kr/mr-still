import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class FolderBrowsingTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-Folders-\(UUID().uuidString)", isDirectory: true)
        for child in ["Albums/Nested/Deep", "Trips", "disguised.jpg", ".hidden"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(child, isDirectory: true), withIntermediateDirectories: true)
        }
        for name in ["a.png", "z.png", "Albums/nested.png", "Albums/Nested/deep.png", "ignore.txt"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        return root
    }

    @MainActor
    private func model() -> BrowserModel {
        let suite = "PhotoViewer-FolderTests-\(UUID().uuidString)"
        suites.append(suite)
        return BrowserModel(defaults: UserDefaults(suiteName: suite)!)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Asynchronous browser operation did not finish")
    }

    func testFolderFirstGroupingSurvivesEverySortKeyAndDirection() {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let entries = [
            ImageFile(url: root.appendingPathComponent("a.png"), size: 1, modified: .distantPast),
            ImageFile(url: root.appendingPathComponent("ZFolder", isDirectory: true), size: 0, modified: .distantFuture, isDirectory: true),
            ImageFile(url: root.appendingPathComponent("z.png"), size: 100, modified: .distantFuture),
            ImageFile(url: root.appendingPathComponent("AFolder", isDirectory: true), size: 0, modified: .distantPast, isDirectory: true)
        ]
        for key in FileSortKey.allCases {
            for ascending in [true, false] {
                let result = FileOrdering.sorted(entries, by: key, ascending: ascending)
                XCTAssertEqual(result.map(\.isDirectory), [true, true, false, false])
            }
        }
    }

    @MainActor
    func testFoldersAreListedFirstButInitialSelectionAndViewerNavigationUseImages() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        model.openFolder(root)
        try await waitUntil { !model.loading }
        XCTAssertEqual(model.files.map(\.name), ["Albums", "disguised.jpg", "Trips", "a.png", "z.png"])
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.png")
        model.navigate(1)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "z.png")
        model.navigate(-1)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.png")
        model.navigate(-1)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.png")
        model.setSort(.name, ascending: false)
        XCTAssertEqual(model.files.map(\.name), ["Trips", "disguised.jpg", "Albums", "z.png", "a.png"])
        model.navigate(-1)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "z.png")
    }

    @MainActor
    func testFolderPrimaryClearsViewerAndActivationNavigatesWithoutSlideOrRecursiveFileOperations() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        model.openFolder(root)
        try await waitUntil { !model.loading }
        let album = try XCTUnwrap(model.files.first { $0.name == "Albums" })
        let photo = try XCTUnwrap(model.currentURL)
        model.select([album.url, photo], primary: album.url)
        XCTAssertNil(model.currentURL)
        XCTAssertNil(model.currentFile)
        XCTAssertEqual(model.selectedImageCount, 1)
        XCTAssertEqual(model.primarySelectionURL, album.url)
        XCTAssertFalse(model.canModifySelection)
        model.copySelection()
        XCTAssertEqual(model.statusMessage, L10n.text("Select image files to copy"))
        model.trashSelection()
        XCTAssertFalse(model.working)
        XCTAssertTrue(FileManager.default.fileExists(atPath: album.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path))
        model.activateSelection()
        try await waitUntil { !model.loading }
        XCTAssertEqual(model.folder, album.url)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "nested.png")
        XCTAssertFalse(model.slideMode)
        model.activateSelection()
        XCTAssertTrue(model.slideMode)
    }

    @MainActor
    func testFolderOnlyDirectorySelectsFirstFolderAndNavigationNeverSelectsItAsImage() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let albums = root.appendingPathComponent("Albums/Nested/Deep", isDirectory: true)
        let child = albums.appendingPathComponent("OnlyChild", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        model.openFolder(albums)
        try await waitUntil { !model.loading }
        XCTAssertEqual(model.primarySelectionURL, child)
        XCTAssertNil(model.currentURL)
        model.navigate(1)
        XCTAssertNil(model.currentURL)
        model.activateSelection()
        try await waitUntil { !model.loading }
        XCTAssertEqual(model.folder, child)
        XCTAssertTrue(model.files.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
    }

    @MainActor
    func testHomeStartsOneLevelDeepAndExplicitNestedOpenRevealsOnlyRequiredAncestors() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        try await waitUntil { outline.isItemExpanded(home) }
        XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: home), 3)
        for index in 0..<3 {
            let child = controller.outlineView(outline, child: index, ofItem: home)
            XCTAssertFalse(outline.isItemExpanded(child))
            XCTAssertEqual(controller.outlineView(outline, numberOfChildrenOfItem: child), 0)
        }
        XCTAssertNil(model.folder)
        let header = try XCTUnwrap(descendant(NSBox.self, in: controller.view))
        XCTAssertEqual(header.identifier?.rawValue, "DirectoryPathHeader")
        XCTAssertNotEqual(header.fillColor, NSColor.controlBackgroundColor)
        let nested = root.appendingPathComponent("Albums/Nested", isDirectory: true)
        model.openFile(nested.appendingPathComponent("deep.png"))
        try await waitUntil { !model.loading && outline.selectedRow >= 0 }
        let selected = try XCTUnwrap(outline.item(atRow: outline.selectedRow))
        let cell = controller.outlineView(outline, viewFor: nil, item: selected) as? NSTableCellView
        XCTAssertEqual(cell?.textField?.stringValue, "Nested")
        XCTAssertFalse(outline.isItemExpanded(selected))
        XCTAssertEqual(model.currentURL?.lastPathComponent, "deep.png")
    }

    @MainActor
    func testListColumnsCenterDetailsAndSortDescriptorsKeepToolbarAndSelectionInSync() async throws {
        _ = NSApplication.shared
        let model = model()
        model.viewMode = .list
        let a = ImageFile(url: URL(fileURLWithPath: "/tmp/a.png"), size: 300, modified: Date(timeIntervalSince1970: 20))
        let b = ImageFile(url: URL(fileURLWithPath: "/tmp/b.png"), size: 100, modified: Date(timeIntervalSince1970: 10))
        model.files = [a, b]
        model.select([a.url], primary: a.url)
        let controller = FileBrowserController(model: model)
        let table = try XCTUnwrap(descendant(NSTableView.self, in: controller.view))
        for column in table.tableColumns {
            let prototype = try XCTUnwrap(column.sortDescriptorPrototype)
            XCTAssertEqual(prototype.key, column.identifier.rawValue)
            XCTAssertTrue(prototype.ascending, "A newly selected column starts ascending")
            let cell = try XCTUnwrap(controller.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
            cell.frame = NSRect(x: 0, y: 0, width: column.width, height: table.rowHeight)
            cell.layoutSubtreeIfNeeded()
            let label = try XCTUnwrap(cell.textField)
            XCTAssertEqual(label.frame.midY, cell.bounds.midY, accuracy: 0.5)
        }
        for key in [FileSortKey.size, .date, .name] {
            for ascending in [true, false] {
                table.sortDescriptors = [NSSortDescriptor(key: key.rawValue, ascending: ascending)]
                XCTAssertEqual(model.sortKey, key)
                XCTAssertEqual(model.ascending, ascending)
                XCTAssertEqual(model.files, FileOrdering.sorted([a, b], by: key, ascending: ascending))
                XCTAssertEqual(model.selection, [a.url])
                XCTAssertEqual(model.currentURL, a.url)
            }
        }
        // The popup and direction button also update the native header indicator.
        model.setSort(.size, ascending: false)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(table.sortDescriptors.first?.key, "size")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
        let popup = try XCTUnwrap(descendant(NSPopUpButton.self, in: controller.view))
        XCTAssertEqual(popup.indexOfSelectedItem, FileSortKey.allCases.firstIndex(of: .size))
        model.select([], primary: nil)
        table.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        XCTAssertEqual(model.sortKey, .date)
        XCTAssertTrue(model.ascending)
        XCTAssertTrue(model.selection.isEmpty)
    }

    @MainActor
    func testSortControlsWorkWithEmptySelectionAndEmptyFolder() async throws {
        _ = NSApplication.shared
        let model = model()
        let controller = FileBrowserController(model: model)
        let popup = try XCTUnwrap(descendant(NSPopUpButton.self, in: controller.view))
        for mode in FileViewMode.allCases {
            model.viewMode = mode
            model.files = [ImageFile(url: URL(fileURLWithPath: "/tmp/z.png"), size: 1, modified: .distantPast),
                           ImageFile(url: URL(fileURLWithPath: "/tmp/a.png"), size: 2, modified: .now)]
            model.select([], primary: nil)
            for item in popup.itemArray {
                XCTAssertTrue(controller.validateMenuItem(item), "Sort options must not require selected files")
            }
            popup.selectItem(at: FileSortKey.allCases.firstIndex(of: .size)!)
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup))
            XCTAssertEqual(model.sortKey, .size)
            XCTAssertTrue(model.selection.isEmpty)
        }
        model.files = []
        for item in popup.itemArray { XCTAssertTrue(controller.validateMenuItem(item)) }
        let direction = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSButton }.first { $0.toolTip == L10n.text("Ascending — click for descending") || $0.toolTip == L10n.text("Descending — click for ascending") })
        let ascending = model.ascending
        direction.performClick(nil)
        XCTAssertEqual(model.ascending, !ascending)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.files.isEmpty)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }

    @MainActor
    func testDirectoryDoubleClickTogglesOnlyClickedBranchAndIgnoresLeaves() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        XCTAssertTrue(outline.target === controller)
        XCTAssertNotNil(outline.doubleAction)
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        try await waitUntil { outline.isItemExpanded(home) }
        let album = controller.outlineView(outline, child: 0, ofItem: home)
        controller.toggleDirectory(at: outline.row(forItem: album))
        try await waitUntil { controller.outlineView(outline, numberOfChildrenOfItem: album) > 0 }
        XCTAssertTrue(outline.isItemExpanded(album))
        let nested = controller.outlineView(outline, child: 0, ofItem: album)
        XCTAssertFalse(outline.isItemExpanded(nested), "Only one level should expand")
        controller.toggleDirectory(at: outline.row(forItem: album))
        XCTAssertFalse(outline.isItemExpanded(album))
        controller.toggleDirectory(at: outline.row(forItem: album))
        XCTAssertTrue(outline.isItemExpanded(album))
        let leaf = controller.outlineView(outline, child: 1, ofItem: home)
        controller.toggleDirectory(at: outline.row(forItem: leaf))
        try await waitUntil { !outline.isExpandable(leaf) }
        controller.toggleDirectory(at: outline.row(forItem: leaf))
        XCTAssertFalse(outline.isItemExpanded(leaf))
        controller.toggleDirectory(at: -1)
        controller.toggleDirectory(at: outline.numberOfRows + 1)
        controller.toggleDirectory(at: 0)
        XCTAssertTrue(outline.isItemExpanded(album))
        XCTAssertNil(model.folder, "Disclosure alone must not navigate to a different folder")
    }

    @MainActor
    func testExpandCapabilityQueriesAndPendingLoadsDoNotForceDisclosureOpen() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model()
        let controller = DirectoryTreeController(model: model, homeURL: root)
        let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: controller.view))
        let home = controller.outlineView(outline, child: 1, ofItem: nil)
        try await waitUntil { outline.isItemExpanded(home) }
        let album = controller.outlineView(outline, child: 0, ofItem: home)
        XCTAssertTrue(controller.outlineView(outline, shouldExpandItem: album))
        try await waitUntil { controller.outlineView(outline, numberOfChildrenOfItem: album) > 0 }
        XCTAssertFalse(outline.isItemExpanded(album), "A delegate capability query must not expand a folder")
        outline.expandItem(album, expandChildren: false)
        XCTAssertTrue(outline.isItemExpanded(album))
        let nested = controller.outlineView(outline, child: 0, ofItem: album)
        outline.expandItem(nested, expandChildren: false)
        XCTAssertTrue(outline.isItemExpanded(nested))
        outline.collapseItem(nested, collapseChildren: true)
        try await waitUntil { controller.outlineView(outline, numberOfChildrenOfItem: nested) > 0 }
        XCTAssertFalse(outline.isItemExpanded(nested), "A completed directory load must respect an intervening collapse")
    }

    @MainActor
    func testEnterOpensSelectedFolderInEveryBrowserDisplayModeAndSynchronizesTree() async throws {
        _ = NSApplication.shared
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for mode in FileViewMode.allCases {
            let model = model()
            model.viewMode = mode
            let tree = DirectoryTreeController(model: model, homeURL: root)
            let outline = try XCTUnwrap(descendant(NSOutlineView.self, in: tree.view))
            let browser = FileBrowserController(model: model)
            _ = browser.view
            model.openFolder(root)
            try await waitUntil { !model.loading }
            let album = try XCTUnwrap(model.files.first { $0.name == "Albums" })
            model.select([album.url], primary: album.url)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            if mode == .list {
                try XCTUnwrap(descendant(NSTableView.self, in: browser.view)).keyDown(with: event)
            } else {
                try XCTUnwrap(descendant(NSCollectionView.self, in: browser.view)).keyDown(with: event)
            }
            try await waitUntil { !model.loading && model.folder == album.url && outline.selectedRow >= 0 }
            XCTAssertFalse(model.slideMode)
            XCTAssertEqual(model.folder, album.url)
            try await waitUntil {
                guard let selected = outline.item(atRow: outline.selectedRow),
                      let cell = tree.outlineView(outline, viewFor: nil, item: selected) as? NSTableCellView else { return false }
                return cell.textField?.stringValue == "Albums"
            }
        }
    }

    @MainActor
    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
        return nil
    }
}
