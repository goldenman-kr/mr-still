import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class FileAccessTests: XCTestCase {
    private let bookmarkKey = "securityScopedFolders.v1"

    private final class Recorder {
        var starts: [URL] = []
        var stops: [URL] = []
        var creates: [URL] = []
        var startResult = true
        var readable = true
        var writable = true

        func operations() -> FileAccessController.Operations {
            FileAccessController.Operations(
                create: { self.creates.append($0); return Data($0.path.utf8) },
                resolve: { .init(url: URL(fileURLWithPath: String(decoding: $0, as: UTF8.self), isDirectory: true), stale: false) },
                start: { self.starts.append($0); return self.startResult },
                stop: { self.stops.append($0) },
                readable: { _ in self.readable },
                writable: { _ in self.writable })
        }
    }

    private func defaults() -> (UserDefaults, String) {
        let name = "MrStill-FileAccessTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @MainActor
    func testRestoresSavedBookmarkAndRefreshesStaleMovedPathWithoutPrompting() throws {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let old = URL(fileURLWithPath: "/tmp/OldAlbum", isDirectory: true)
        let current = URL(fileURLWithPath: "/tmp/MovedAlbum", isDirectory: true)
        defaults.set([old.path: Data("old-bookmark".utf8)], forKey: bookmarkKey)
        var operations = recorder.operations()
        operations.resolve = { data in
            XCTAssertEqual(data, Data("old-bookmark".utf8))
            return .init(url: current, stale: true)
        }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        access.chooseDirectory = { _ in XCTFail("Restored grants must not prompt"); return nil }
        XCTAssertEqual(access.directoryURLs, [current])
        XCTAssertTrue(access.ensureDirectory(current.appendingPathComponent("Child", isDirectory: true)))
        XCTAssertEqual(recorder.starts, [current])
        XCTAssertEqual(recorder.creates, [current])
        let saved = try XCTUnwrap(defaults.dictionary(forKey: bookmarkKey) as? [String: Data])
        XCTAssertNil(saved[old.path])
        XCTAssertEqual(saved[current.path], Data(current.path.utf8))
        access.stopAll()
        XCTAssertEqual(recorder.stops, [current])
    }

    @MainActor
    func testDuplicateResolvedBookmarksAcquireAndReleaseOnlyOneScope() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let current = URL(fileURLWithPath: "/tmp/SharedAlbum", isDirectory: true)
        defaults.set(["/tmp/old-a": Data("a".utf8), "/tmp/old-b": Data("b".utf8)], forKey: bookmarkKey)
        var operations = recorder.operations()
        operations.resolve = { _ in .init(url: current, stale: true) }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertEqual(access.directoryURLs, [current])
        XCTAssertEqual(recorder.starts, [current])
        access.stopAll()
        access.stopAll()
        XCTAssertEqual(recorder.stops, [current])
    }

    @MainActor
    func testRepeatedAuthorizationPersistsOneGrantAndStopAllIsIdempotent() throws {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let folder = URL(fileURLWithPath: "/tmp/RepeatedAlbum", isDirectory: true)
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        XCTAssertTrue(access.authorizeDirectory(folder))
        XCTAssertTrue(access.authorizeDirectory(folder))
        XCTAssertEqual(recorder.starts, [folder])
        XCTAssertEqual(recorder.creates, [folder])
        XCTAssertEqual(access.directoryURLs, [folder])
        let saved = try XCTUnwrap(defaults.dictionary(forKey: bookmarkKey) as? [String: Data])
        XCTAssertEqual(saved[folder.path], Data(folder.path.utf8))
        access.stopAll()
        access.stopAll()
        XCTAssertEqual(recorder.stops, [folder])
        XCTAssertFalse(access.hasAccess(to: folder))
        XCTAssertTrue(access.directoryURLs.isEmpty)
        XCTAssertNotNil((defaults.dictionary(forKey: bookmarkKey) as? [String: Data])?[folder.path], "Stopping a session must preserve future-launch bookmarks")
    }

    @MainActor
    func testPanelActivatedScopeDoesNotReceiveAnUnbalancedStop() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        recorder.startResult = false
        let folder = URL(fileURLWithPath: "/tmp/PanelAlbum", isDirectory: true)
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        XCTAssertTrue(access.authorizeDirectory(folder))
        XCTAssertTrue(access.authorizeDirectory(folder))
        XCTAssertTrue(access.hasAccess(to: folder))
        access.stopAll()
        XCTAssertEqual(recorder.starts, [folder])
        XCTAssertTrue(recorder.stops.isEmpty)
    }

    @MainActor
    func testUnreadableAuthorizationReleasesScopeAndDoesNotPersistGrant() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        recorder.readable = false
        let folder = URL(fileURLWithPath: "/tmp/UnreadableAlbum", isDirectory: true)
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        XCTAssertFalse(access.authorizeDirectory(folder))
        XCTAssertEqual(recorder.starts, [folder])
        XCTAssertEqual(recorder.stops, [folder])
        XCTAssertTrue(access.directoryURLs.isEmpty)
        XCTAssertTrue(recorder.creates.isEmpty)
        access.stopAll()
        XCTAssertEqual(recorder.stops.count, 1)
    }

    @MainActor
    func testCancellationAndUnrelatedFolderNeverGrantRequestedAccess() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let requested = URL(fileURLWithPath: "/tmp/RequestedAlbum", isDirectory: true)
        let unrelated = URL(fileURLWithPath: "/tmp/RequestedAlbum-other", isDirectory: true)
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        var prompts: [URL] = []
        access.chooseDirectory = { prompts.append($0); return nil }
        XCTAssertFalse(access.ensureDirectory(requested))
        access.chooseDirectory = { prompts.append($0); return unrelated }
        XCTAssertFalse(access.ensureDirectory(requested))
        XCTAssertEqual(prompts, [requested, requested])
        XCTAssertTrue(recorder.starts.isEmpty)
        XCTAssertTrue(access.directoryURLs.isEmpty)
        XCTAssertFalse(access.hasAccess(to: requested))
    }

    @MainActor
    func testReadGrantDoesNotBypassWritePermissionAndParentSelectionCoversChildren() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let parent = URL(fileURLWithPath: "/tmp/ParentAlbum", isDirectory: true)
        let child = parent.appendingPathComponent("Child", isDirectory: true)
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        var promptCount = 0
        access.chooseDirectory = { requested in
            promptCount += 1
            XCTAssertEqual(requested, child)
            return parent
        }
        XCTAssertTrue(access.ensureDirectory(child))
        XCTAssertEqual(access.directoryURLs, [parent])
        XCTAssertEqual(promptCount, 1)
        recorder.writable = false
        access.chooseDirectory = { _ in promptCount += 1; return nil }
        XCTAssertTrue(access.ensureDirectory(child), "Read-only operations should retain access")
        XCTAssertEqual(promptCount, 1)
        XCTAssertFalse(access.ensureDirectory(child, writing: true))
        XCTAssertEqual(promptCount, 2)
        recorder.writable = true
        XCTAssertTrue(access.ensureDirectory(child, writing: true))
        XCTAssertEqual(promptCount, 2)
        access.stopAll()
    }

    @MainActor
    func testContainmentUsesPathComponentsAndRejectsSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let granted = root.appendingPathComponent("Album", isDirectory: true)
        let outside = root.appendingPathComponent("Album-other", isDirectory: true)
        try FileManager.default.createDirectory(at: granted, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let escape = granted.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        XCTAssertTrue(FileAccessController.contains(granted, in: granted))
        XCTAssertTrue(FileAccessController.contains(granted.appendingPathComponent("photo.png"), in: granted))
        XCTAssertFalse(FileAccessController.contains(outside, in: granted))
        try Data().write(to: outside.appendingPathComponent("existing.png"))
        XCTAssertFalse(FileAccessController.contains(escape.appendingPathComponent("existing.png"), in: granted))
        XCTAssertFalse(FileAccessController.contains(escape.appendingPathComponent("missing.png"), in: granted))
    }

    @MainActor
    func testTemporaryPasteboardScopesReleaseOnlySuccessfulAcquisitions() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let granted = URL(fileURLWithPath: "/tmp/GrantedAlbum", isDirectory: true)
        let temporary = URL(fileURLWithPath: "/tmp/Temporary.png")
        let denied = URL(fileURLWithPath: "/tmp/Denied.png")
        var operations = recorder.operations()
        operations.start = { recorder.starts.append($0); return $0 != denied }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertTrue(access.authorizeDirectory(granted))
        let acquired = access.beginTemporaryAccess(to: [granted.appendingPathComponent("photo.png"), temporary, denied])
        XCTAssertEqual(acquired, [temporary])
        access.endTemporaryAccess(to: acquired)
        XCTAssertEqual(recorder.stops, [temporary])
        access.stopAll()
        XCTAssertEqual(recorder.stops, [temporary, granted])
        XCTAssertEqual(recorder.starts, [granted, temporary, denied])
    }

    @MainActor
    func testCanceledFolderGrantPreservesBrowserFolderAndNavigationHistory() async throws {
        _ = NSApplication.shared
        let (defaults, suite) = defaults()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folders = ["A", "B", "C"].map { root.appendingPathComponent($0, isDirectory: true) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let recorder = Recorder()
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: recorder.operations())
        XCTAssertTrue(access.authorizeDirectory(folders[0]))
        XCTAssertTrue(access.authorizeDirectory(folders[1]))
        access.chooseDirectory = { _ in nil }
        let model = BrowserModel(defaults: defaults, access: access)
        model.openFolder(folders[0]); try await settle(model)
        model.openFolder(folders[1]); try await settle(model)
        XCTAssertTrue(model.canGoBack)
        let recent = model.recentURLs
        model.openFolder(folders[2])
        XCTAssertEqual(model.folder, folders[1])
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
        XCTAssertEqual(model.recentURLs, recent)
        XCTAssertEqual(model.errorMessage, L10n.text("Folder access was not granted. Use File > Open Folder to choose it again."))
        model.goBack(); try await settle(model)
        XCTAssertEqual(model.folder, folders[0])
        XCTAssertFalse(model.canGoBack)
        XCTAssertTrue(model.canGoForward)
        model.goForward(); try await settle(model)
        XCTAssertEqual(model.folder, folders[1])
        access.stopAll()
    }

    @MainActor
    func testMovedBookmarkRelocatesRecentDescendantsAndFavoritePathsAtModelInitialization() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let old = URL(fileURLWithPath: "/tmp/OriginalAlbum", isDirectory: true)
        let moved = URL(fileURLWithPath: "/tmp/MovedAlbum", isDirectory: true)
        let oldPhoto = old.appendingPathComponent("Nested/photo.png")
        let unrelated = URL(fileURLWithPath: "/tmp/OriginalAlbum-other/photo.png")
        defaults.set([old.path: Data("bookmark".utf8)], forKey: bookmarkKey)
        defaults.set([oldPhoto.path, unrelated.path], forKey: "recentPaths")
        defaults.set([old.path], forKey: "favoritePaths")
        var operations = recorder.operations()
        operations.resolve = { _ in .init(url: moved, stale: true) }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertEqual(access.restoredURL(for: old), moved)
        XCTAssertEqual(access.restoredURL(for: oldPhoto), moved.appendingPathComponent("Nested/photo.png"))
        XCTAssertEqual(access.restoredURL(for: unrelated), unrelated)
        let model = BrowserModel(defaults: defaults, access: access)
        XCTAssertEqual(model.favoriteURLs, [moved])
        XCTAssertEqual(model.recentURLs, [moved.appendingPathComponent("Nested/photo.png"), unrelated])
        XCTAssertEqual(defaults.stringArray(forKey: "favoritePaths"), [moved.path])
        XCTAssertEqual(defaults.stringArray(forKey: "recentPaths"), [moved.appendingPathComponent("Nested/photo.png").path, unrelated.path])
        access.stopAll()

        // A second launch has only the renewed bookmark, with no old-to-new mapping.
        let nextRecorder = Recorder()
        let nextAccess = FileAccessController(defaults: defaults, isSandboxed: true, operations: nextRecorder.operations())
        let nextModel = BrowserModel(defaults: defaults, access: nextAccess)
        XCTAssertEqual(nextModel.favoriteURLs, [moved])
        XCTAssertEqual(nextModel.recentURLs, [moved.appendingPathComponent("Nested/photo.png"), unrelated])
        XCTAssertEqual(nextAccess.directoryURLs, [moved])
        XCTAssertTrue(nextAccess.hasAccess(to: nextModel.recentURLs[0]))
        nextAccess.stopAll()
    }

    @MainActor
    func testStaleBookmarkRefreshFailureRetainsOriginalDataForFutureLaunch() throws {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = URL(fileURLWithPath: "/tmp/OriginalBookmarkAlbum", isDirectory: true)
        let moved = URL(fileURLWithPath: "/tmp/MovedBookmarkAlbum", isDirectory: true)
        let original = Data("original-recoverable-bookmark".utf8)
        defaults.set([old.path: original], forKey: bookmarkKey)
        let recorder = Recorder()
        var operations = recorder.operations()
        operations.resolve = { data in
            XCTAssertEqual(data, original)
            return .init(url: moved, stale: true)
        }
        operations.create = { url in
            recorder.creates.append(url)
            throw CocoaError(.fileWriteNoPermission)
        }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertEqual(access.directoryURLs, [moved])
        XCTAssertTrue(access.hasAccess(to: moved))
        let saved = try XCTUnwrap(defaults.dictionary(forKey: bookmarkKey) as? [String: Data])
        XCTAssertEqual(saved, [old.path: original])
        XCTAssertEqual(recorder.creates, [moved])
        access.stopAll()

        let nextAccess = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertEqual(nextAccess.directoryURLs, [moved])
        XCTAssertEqual(nextAccess.restoredURL(for: old), moved)
        XCTAssertEqual((defaults.dictionary(forKey: bookmarkKey) as? [String: Data])?[old.path], original)
        nextAccess.stopAll()
        XCTAssertEqual(recorder.starts, [moved, moved])
        XCTAssertEqual(recorder.stops, [moved, moved])
    }

    @MainActor
    func testInvalidAndUnavailableBookmarksAreNotPublishedAsActiveGrants() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = Recorder()
        let unavailable = URL(fileURLWithPath: "/tmp/UnavailableAlbum", isDirectory: true)
        defaults.set(["/tmp/invalid": Data("invalid".utf8), unavailable.path: Data("unavailable".utf8)], forKey: bookmarkKey)
        var operations = recorder.operations()
        operations.resolve = { data in
            if data == Data("invalid".utf8) { throw CocoaError(.fileReadCorruptFile) }
            return .init(url: unavailable, stale: false)
        }
        operations.start = { recorder.starts.append($0); return false }
        let access = FileAccessController(defaults: defaults, isSandboxed: true, operations: operations)
        XCTAssertTrue(access.directoryURLs.isEmpty)
        XCTAssertFalse(access.hasAccess(to: unavailable))
        access.chooseDirectory = { _ in nil }
        XCTAssertFalse(access.ensureDirectory(unavailable))
        XCTAssertEqual(recorder.starts, [unavailable])
        access.stopAll()
        XCTAssertTrue(recorder.stops.isEmpty)
        XCTAssertTrue(recorder.creates.isEmpty)
    }

    @MainActor
    private func settle(_ model: BrowserModel) async throws {
        for _ in 0..<300 {
            if !model.loading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Folder load timed out")
    }
}
