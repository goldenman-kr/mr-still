import AppKit
import Combine
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

/// Keeps folder grants alive for image decoding, thumbnails, file watching and printing.
/// Grants are released once, on termination; asynchronous readers may outlive a folder switch.
@MainActor
final class FileAccessController: ObservableObject {
    nonisolated static var sandboxBuild: Bool {
#if APP_STORE
        true
#else
        false
#endif
    }
    struct BookmarkResolution { let url: URL; let stale: Bool }
    struct Operations {
        var create: (URL) throws -> Data = { try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        var resolve: (Data) throws -> BookmarkResolution = { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            return BookmarkResolution(url: url, stale: stale)
        }
        var start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
        var stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
        var readable: (URL) -> Bool = { FileManager.default.isReadableFile(atPath: $0.path) }
        var writable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) }
    }
    @Published private(set) var directoryURLs: [URL] = []
    private(set) var persistenceWarning: String?
    let isSandboxed: Bool
    private let defaults: UserDefaults
    private let operations: Operations
    private var active: [URL: Bool] = [:]
    private var bookmarks: [String: Data]
    private var relocated: [URL: URL] = [:]
    private let key = "securityScopedFolders.v1"
    var chooseDirectory: (URL) -> URL? = { requested in
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = requested
        panel.prompt = L10n.text("Allow Access")
        panel.message = L10n.text("Choose this folder or a parent folder to browse its photos. Access is saved for future launches.")
        return panel.runModal() == .OK ? panel.url : nil
    }

    init(defaults: UserDefaults = .standard, isSandboxed: Bool = FileAccessController.sandboxBuild, operations: Operations = Operations()) {
        self.defaults = defaults
        self.isSandboxed = isSandboxed
        self.operations = operations
        bookmarks = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
        guard isSandboxed else { return }
        // Resolve saved grants without prompting. Failed grants are re-requested on use.
        for (path, data) in bookmarks {
            guard let resolved = try? operations.resolve(data) else { continue }
            let url = resolved.url.standardizedFileURL
            if active[url] == nil {
                guard operations.start(url) else { continue }
                active[url] = true
                directoryURLs.append(url)
            }
            relocated[URL(fileURLWithPath: path).standardizedFileURL] = url
            if resolved.stale || path != url.path {
                if let renewed = try? operations.create(url) {
                    bookmarks[url.path] = renewed
                    if path != url.path { bookmarks.removeValue(forKey: path) }
                } else {
                    persistenceWarning = L10n.text("Folder access could not be saved. You may need to choose the folder again after restarting the app.")
                }
            }
        }
        save()
    }

    nonisolated static func contains(_ file: URL, in directory: URL) -> Bool {
        let child = canonicalURL(file).pathComponents
        let parent = canonicalURL(directory).pathComponents
        return child.starts(with: parent)
    }

    private nonisolated static func canonicalURL(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var suffix: [String] = []
        while existing.path != "/" && !FileManager.default.fileExists(atPath: existing.path) {
            suffix.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return suffix.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }

    func restoredURL(for stored: URL) -> URL {
        // A directory bookmark can follow a move; recent child paths follow it too.
        for old in relocated.keys.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            let parts = stored.standardizedFileURL.pathComponents
            guard parts.starts(with: old.pathComponents), let current = relocated[old] else { continue }
            return parts.dropFirst(old.pathComponents.count).reduce(current) { $0.appendingPathComponent($1) }
        }
        return stored
    }

    func hasAccess(to url: URL) -> Bool {
        !isSandboxed || directoryURLs.contains { Self.contains(url, in: $0) }
    }

    /// Call only with a URL returned by NSOpenPanel, never an arbitrary stored path.
    @discardableResult
    func authorizeDirectory(_ url: URL) -> Bool {
        guard isSandboxed else { return true }
        let url = url.standardizedFileURL
        if active[url] != nil { return operations.readable(url) }
        let started = operations.start(url)
        guard operations.readable(url) else {
            if started { operations.stop(url) }
            return false
        }
        // NSOpenPanel may already have activated its extension, so start can return false.
        active[url] = started
        directoryURLs.append(url)
        if let bookmark = try? operations.create(url) {
            bookmarks[url.path] = bookmark
            save()
        } else {
            persistenceWarning = L10n.text("Folder access could not be saved. You may need to choose the folder again after restarting the app.")
        }
        return true
    }

    func ensureDirectory(_ url: URL, writing: Bool = false) -> Bool {
        guard isSandboxed else { return true }
        if hasAccess(to: url), operations.readable(url), !writing || operations.writable(url) { return true }
        guard let chosen = chooseDirectory(url), Self.contains(url, in: chosen), authorizeDirectory(chosen) else { return false }
        return operations.readable(url) && (!writing || operations.writable(url))
    }

    /// Pasteboard URLs carry a temporary sandbox extension; retain it through the copy.
    func beginTemporaryAccess(to urls: [URL]) -> [URL] {
        guard isSandboxed else { return [] }
        return urls.filter { !hasAccess(to: $0) && operations.start($0) }
    }
    func endTemporaryAccess(to urls: [URL]) { urls.forEach(operations.stop) }

    func stopAll() {
        for (url, started) in active where started { operations.stop(url) }
        active.removeAll()
        directoryURLs.removeAll()
    }
    private func save() { defaults.set(bookmarks, forKey: key) }
}
