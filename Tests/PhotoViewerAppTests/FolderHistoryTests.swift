import XCTest
@testable import PhotoViewer
import PhotoViewerCore

final class FolderHistoryTests: XCTestCase {
    private var roots: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    @MainActor
    private func fixture() throws -> (BrowserModel, [URL]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-History-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        let folders = ["A", "B", "C", "D"].map { root.appendingPathComponent($0, isDirectory: true) }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["a.png", "z.png"] { try Data().write(to: folder.appendingPathComponent(name)) }
        }
        let suite = "PhotoViewer-HistoryTests-\(UUID().uuidString)"
        suites.append(suite)
        return (BrowserModel(defaults: UserDefaults(suiteName: suite)!), folders)
    }

    @MainActor
    private func finishLoading(_ model: BrowserModel) async throws {
        for _ in 0..<300 {
            if !model.loading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Folder load did not finish")
    }

    @MainActor
    func testUpAndRefreshPreserveSelectionAndHistory() async throws {
        let (model, folders) = try fixture()
        XCTAssertFalse(model.canGoUp)
        XCTAssertFalse(model.canRefreshFolder)
        model.goUp()
        model.refreshFolder()
        XCTAssertFalse(model.loading)
        model.openFolder(folders[0])
        try await finishLoading(model)
        XCTAssertTrue(model.canGoUp)
        model.goUp()
        XCTAssertFalse(model.canGoUp)
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0].deletingLastPathComponent())
        model.goBack()
        try await finishLoading(model)
        let selected = folders[0].appendingPathComponent("z.png")
        model.select([selected], primary: selected)
        let added = folders[0].appendingPathComponent("new.png")
        try Data().write(to: added)
        model.refreshFolder()
        try await finishLoading(model)
        XCTAssertTrue(model.files.contains { $0.url == added })
        XCTAssertEqual(model.currentURL, selected)
        XCTAssertTrue(model.canGoForward)
        XCTAssertFalse(model.canGoBack)
        model.openFolder(URL(fileURLWithPath: "/", isDirectory: true))
        try await finishLoading(model)
        XCTAssertFalse(model.canGoUp)
        model.goUp()
        XCTAssertFalse(model.loading)
    }

    @MainActor
    func testBackForwardUseSuccessfulFolderHistoryAndPreserveMode() async throws {
        let (model, folders) = try fixture()
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        model.openFolder(folders[0])
        try await finishLoading(model)
        XCTAssertFalse(model.canGoBack)
        model.openFolder(folders[1])
        XCTAssertEqual(model.folder, folders[0], "The current folder remains valid until the requested load succeeds")
        try await finishLoading(model)
        model.openFolder(folders[2])
        try await finishLoading(model)
        model.slideMode = true
        model.goBack()
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[1])
        XCTAssertEqual(model.currentURL, folders[1].appendingPathComponent("a.png"))
        XCTAssertTrue(model.slideMode)
        XCTAssertTrue(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0])
        XCTAssertFalse(model.canGoBack)
        model.goBack()
        XCTAssertFalse(model.loading)
        model.goForward()
        try await finishLoading(model)
        model.goForward()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[2])
        XCTAssertFalse(model.canGoForward)
    }

    @MainActor
    func testSameFolderRefreshAndSortRetainForwardHistoryAndSelection() async throws {
        let (model, folders) = try fixture()
        for folder in folders.prefix(3) {
            model.openFolder(folder)
            try await finishLoading(model)
        }
        model.goBack()
        try await finishLoading(model)
        let selected = folders[1].appendingPathComponent("z.png")
        model.select([selected], primary: selected)
        model.setSort(.name, ascending: false)
        model.openFolder(URL(fileURLWithPath: folders[1].path))
        try await finishLoading(model)
        XCTAssertEqual(model.currentURL, selected)
        XCTAssertTrue(model.canGoForward)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0], "Refreshing must not append a duplicate history entry")
        XCTAssertEqual(model.currentURL?.lastPathComponent, "z.png", "History follows the current sort order")
        model.goForward()
        try await finishLoading(model)
        model.goForward()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[2])
    }

    @MainActor
    func testNewFolderAfterBackDiscardsForwardBranch() async throws {
        let (model, folders) = try fixture()
        for folder in folders.prefix(3) {
            model.openFolder(folder)
            try await finishLoading(model)
        }
        model.goBack()
        try await finishLoading(model)
        model.openFolder(folders[3])
        try await finishLoading(model)
        XCTAssertFalse(model.canGoForward)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[1])
        model.goForward()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[3])
    }

    @MainActor
    func testFailedNewFolderAndMissingHistoryTargetKeepCurrentStateAndHistory() async throws {
        let (model, folders) = try fixture()
        model.openFolder(folders[0].appendingPathComponent("missing", isDirectory: true))
        try await finishLoading(model)
        XCTAssertNil(model.folder)
        XCTAssertTrue(model.files.isEmpty)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        for folder in folders.prefix(3) {
            model.openFolder(folder)
            try await finishLoading(model)
        }
        model.goBack()
        try await finishLoading(model)
        let previousFiles = model.files.map(\.url)
        let previousSelection = model.selection
        let previousImage = model.currentURL
        model.openFolder(folders[3].appendingPathComponent("missing", isDirectory: true))
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[1])
        XCTAssertEqual(model.files.map(\.url), previousFiles)
        XCTAssertEqual(model.selection, previousSelection)
        XCTAssertEqual(model.currentURL, previousImage)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
        try FileManager.default.removeItem(at: folders[2])
        model.goForward()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[1])
        XCTAssertEqual(model.files.map(\.url), previousFiles)
        XCTAssertEqual(model.selection, previousSelection)
        XCTAssertTrue(model.canGoForward)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0])
    }

    @MainActor
    func testSupersededLoadCannotCommitFolderOrHistory() async throws {
        let (model, folders) = try fixture()
        model.openFolder(folders[0])
        try await finishLoading(model)
        model.openFolder(folders[1])
        model.openFolder(folders[2])
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[2])
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0])
        XCTAssertFalse(model.canGoBack)
        model.goForward()
        model.openFolder(folders[3])
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[3])
        XCTAssertFalse(model.canGoForward)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0])
    }

    @MainActor
    func testExternalFileOpenRecordsItsFolderButSameFolderFileDoesNotDuplicateHistory() async throws {
        let (model, folders) = try fixture()
        model.openFile(folders[0].appendingPathComponent("z.png"))
        try await finishLoading(model)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "z.png")
        model.openFile(folders[1].appendingPathComponent("z.png"))
        try await finishLoading(model)
        model.openFile(folders[1].appendingPathComponent("a.png"))
        try await finishLoading(model)
        model.goBack()
        try await finishLoading(model)
        XCTAssertEqual(model.folder, folders[0])
        XCTAssertFalse(model.canGoBack)
        XCTAssertEqual(model.currentURL?.lastPathComponent, "a.png")
        model.openFile(folders[1].appendingPathComponent("missing.png"))
        XCTAssertEqual(model.folder, folders[0])
        XCTAssertTrue(model.canGoForward)
    }
}
