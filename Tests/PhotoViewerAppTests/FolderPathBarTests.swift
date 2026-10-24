import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class FolderPathBarTests: XCTestCase {
    @MainActor
    func testBreadcrumbsStartAtHomeAndRetainIntermediateURLs() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let folder = home.appendingPathComponent("Downloads/folder2", isDirectory: true)
        let parts = FolderPathBar.components(for: folder, home: home)
        XCTAssertEqual(parts.map(\.title), [L10n.text("Home"), "Downloads", "folder2"])
        XCTAssertEqual(parts.map { $0.url.path }, [home.path, home.path + "/Downloads", folder.path])
        XCTAssertEqual(FolderPathBar.components(for: URL(fileURLWithPath: "/Users/example-other/Album"), home: home).map(\.title), ["/", "Users", "example-other", "Album"])
    }

    @MainActor
    func testPathBarContainsOnlyReadOnlyBreadcrumbs() throws {
        _ = NSApplication.shared
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let bar = FolderPathBar(homeURL: home)
        bar.update(home.appendingPathComponent("Downloads"))
        let crumbs = try XCTUnwrap(bar.subviews.first as? NSPathControl)
        XCTAssertEqual(bar.subviews.count, 1)
        XCTAssertFalse(crumbs.isEditable)
        XCTAssertNil(crumbs.doubleAction)
        XCTAssertEqual(crumbs.pathItems.map(\.title), [L10n.text("Home"), "Downloads"])
        XCTAssertTrue(bar.subviews.compactMap { $0 as? NSTextField }.isEmpty)
    }
}
