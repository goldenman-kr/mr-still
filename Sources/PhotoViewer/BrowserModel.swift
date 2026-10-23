import AppKit
import Combine
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

@MainActor
final class BrowserModel: ObservableObject {
    @Published var folder: URL?
    @Published var files: [ImageFile] = []
    @Published var selection: Set<URL> = []
    @Published var currentURL: URL?
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var statusMessage = "폴더를 열어 사진을 탐색하세요"
    @Published var sortKey: FileSortKey
    @Published var ascending: Bool
    @Published var viewMode: FileViewMode
    @Published var slideMode = false
    @Published private(set) var recentURLs: [URL]
    @Published private(set) var favoriteURLs: [URL]
    @Published private(set) var working = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    let folderRefreshRequested = PassthroughSubject<URL, Never>()
    var canGoUp: Bool { !loading && folder.map { $0.path != "/" } == true }
    var canRefreshFolder: Bool { !loading && folder != nil }
    var toggleFullscreen: (() -> Void)?
    var currentFile: ImageFile? { files.first { $0.url == currentURL && !$0.isDirectory } }
    var primarySelectionURL: URL? { selectionHistory.last }
    var selectedImageCount: Int { files.filter { !$0.isDirectory && selection.contains($0.url) }.count }
    var canModifySelection: Bool {
        !selection.isEmpty && !files.contains { selection.contains($0.url) && $0.isDirectory }
    }
    private var selectionHistory: [URL] = []
    private var folderHistory: [URL] = []
    private var folderHistoryIndex = -1
    private var requestID = 0
    private var monitor: DispatchSourceFileSystemObject?
    private var refreshTask: DispatchWorkItem?
    private let io = DispatchQueue(label: "PhotoViewer.files", qos: .userInitiated)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sortKey = FileSortKey(rawValue: defaults.string(forKey: "sortKey") ?? "") ?? .name
        ascending = defaults.object(forKey: "ascending") as? Bool ?? true
        viewMode = FileViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .large
        recentURLs = (defaults.stringArray(forKey: "recentPaths") ?? []).map { URL(fileURLWithPath: $0) }
        var seen = Set<URL>()
        favoriteURLs = (defaults.stringArray(forKey: "favoritePaths") ?? []).compactMap { path in
            guard path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            return seen.insert(url).inserted ? url : nil
        }
    }

    func isFavorite(_ url: URL) -> Bool { favoriteURLs.contains(Self.favoriteURL(url)) }

    func addFavorite(_ url: URL) {
        guard url.isFileURL, !isFavorite(url) else { return }
        let target = Self.favoriteURL(url)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &directory), directory.boolValue else { return }
        favoriteURLs.append(target)
        defaults.set(favoriteURLs.map(\.path), forKey: "favoritePaths")
    }

    func removeFavorite(_ url: URL) {
        favoriteURLs.removeAll { $0 == Self.favoriteURL(url) }
        defaults.set(favoriteURLs.map(\.path), forKey: "favoritePaths")
    }

    private static func favoriteURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    func openFile(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            errorMessage = "파일 또는 폴더를 찾을 수 없습니다: \(url.path)"
            return
        }
        if isDirectory.boolValue {
            openFolder(url)
        } else if DirectoryService.isSupported(url) {
            openFolder(url.deletingLastPathComponent(), selecting: url.standardizedFileURL)
            remember(url)
        } else {
            errorMessage = "지원하지 않는 이미지 형식입니다: \(url.lastPathComponent)"
        }
    }

    func openFolder(_ url: URL, selecting preferred: URL? = nil) {
        loadFolder(url, selecting: preferred, historyIndex: nil)
    }

    func goBack() {
        guard canGoBack else { return }
        let index = folderHistoryIndex - 1
        loadFolder(folderHistory[index], selecting: nil, historyIndex: index)
    }

    func goForward() {
        guard canGoForward else { return }
        let index = folderHistoryIndex + 1
        loadFolder(folderHistory[index], selecting: nil, historyIndex: index)
    }

    func goUp() {
        guard canGoUp, let folder else { return }
        openFolder(folder.deletingLastPathComponent())
    }

    func refreshFolder() {
        guard canRefreshFolder, let folder else { return }
        openFolder(folder)
        folderRefreshRequested.send(folder)
    }

    private func updateHistoryAvailability() {
        canGoBack = !loading && folderHistoryIndex > 0
        canGoForward = !loading && folderHistoryIndex >= 0 && folderHistoryIndex + 1 < folderHistory.count
    }

    private func loadFolder(_ url: URL, selecting preferred: URL?, historyIndex: Int?) {
        let target = Self.favoriteURL(url)
        requestID += 1
        let id = requestID
        loading = true
        updateHistoryAvailability()
        refreshTask?.cancel()
        statusMessage = "폴더를 읽는 중…"
        io.async { [weak self] in
            let result = Result {
                var entries = try DirectoryService.contents(of: target)
                if let preferred, !entries.contains(where: { $0.url == preferred }) {
                    let values = try preferred.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                    if values.isRegularFile == true {
                        entries.append(ImageFile(url: preferred, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
                    }
                }
                return entries
            }
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                switch result {
                case .success(let entries):
                    let sameFolder = self.folder == target
                    let retained = sameFolder ? self.selection : []
                    let previous = sameFolder ? self.primarySelectionURL : nil
                    self.folder = target
                    self.files = FileOrdering.sorted(entries, by: self.sortKey, ascending: self.ascending)
                    let available = Set(entries.map(\.url))
                    if let preferred, available.contains(preferred) {
                        self.select([preferred], primary: preferred)
                    } else {
                        let valid = retained.intersection(available)
                        if !valid.isEmpty { self.select(valid, primary: previous) }
                        else if let first = self.files.first(where: { !$0.isDirectory }) ?? self.files.first { self.select([first.url], primary: first.url) }
                        else { self.select([], primary: nil) }
                    }
                    let folders = entries.filter(\.isDirectory).count
                    let images = entries.count - folders
                    self.statusMessage = entries.isEmpty ? "이 폴더에 표시할 항목이 없습니다" : "폴더 \(folders)개 · 사진 \(images)개"
                    if let historyIndex {
                        self.folderHistoryIndex = historyIndex
                    } else if !sameFolder {
                        self.folderHistory = Array(self.folderHistory.prefix(self.folderHistoryIndex + 1))
                        self.folderHistory.append(target)
                        self.folderHistoryIndex = self.folderHistory.count - 1
                    }
                    self.remember(target)
                    self.watch(target)
                case .failure(let error):
                    self.statusMessage = "폴더를 열 수 없습니다"
                    self.errorMessage = "\(target.path)\n\(error.localizedDescription)"
                }
                self.loading = false
                self.updateHistoryAvailability()
            }
        }
    }

    func select(_ urls: Set<URL>, primary: URL?) {
        let valid = urls.intersection(Set(files.map(\.url)))
        selectionHistory.removeAll { !valid.contains($0) }
        for file in files where valid.contains(file.url) && !selectionHistory.contains(file.url) {
            selectionHistory.append(file.url)
        }
        if let primary, valid.contains(primary) {
            selectionHistory.removeAll { $0 == primary }
            selectionHistory.append(primary)
        }
        selection = valid
        // A folder may be the browser's primary selection, but must never be decoded as an image.
        let imageURLs = Set(files.filter { !$0.isDirectory }.map(\.url))
        currentURL = selectionHistory.last.flatMap { imageURLs.contains($0) ? $0 : nil }
    }

    func navigate(_ step: Int) {
        let images = files.filter { !$0.isDirectory }
        guard !images.isEmpty else { return }
        let index = images.firstIndex { $0.url == currentURL } ?? (step > 0 ? -1 : images.count)
        let next = max(0, min(images.count - 1, index + step))
        select([images[next].url], primary: images[next].url)
    }

    func activateSelection() {
        guard let primary = primarySelectionURL, let entry = files.first(where: { $0.url == primary }) else { return }
        if entry.isDirectory { openFolder(entry.url) }
        else { enterSlide() }
    }

    func setSort(_ key: FileSortKey, ascending: Bool) {
        sortKey = key; self.ascending = ascending
        files = FileOrdering.sorted(files, by: key, ascending: ascending)
        defaults.set(key.rawValue, forKey: "sortKey")
        defaults.set(ascending, forKey: "ascending")
    }

    func enterSlide() { if currentURL != nil { slideMode = true } }

    func copySelection() {
        guard canModifySelection else {
            statusMessage = "복사는 이미지 파일을 선택했을 때 사용할 수 있습니다"
            return
        }
        let urls = files.filter { selection.contains($0.url) }.map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
        statusMessage = "\(urls.count)개 파일 복사됨"
    }

    func pasteFiles() {
        guard let folder, !working else { return }
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { DirectoryService.isSupported($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard !urls.isEmpty else { NSSound.beep(); return }
        var policy = CopyConflictPolicy.keepBoth
        if urls.contains(where: { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.lastPathComponent).path) }) {
            let alert = NSAlert()
            alert.messageText = "같은 이름의 파일이 있습니다"
            alert.informativeText = "‘둘 다 유지’를 선택하면 새 이름으로 복사합니다. 기존 파일은 덮어쓰지 않습니다."
            alert.addButton(withTitle: "둘 다 유지")
            alert.addButton(withTitle: "건너뛰기")
            alert.addButton(withTitle: "취소")
            let answer = alert.runModal()
            if answer == .alertThirdButtonReturn { return }
            if answer == .alertSecondButtonReturn { policy = .skip }
        }
        working = true
        statusMessage = "파일 복사 중…"
        let chosenPolicy = policy
        io.async { [weak self] in
            let result = FileOperations.copy(urls, to: folder, conflict: chosenPolicy)
            DispatchQueue.main.async {
                guard let self else { return }
                self.working = false
                if self.folder == folder { self.openFolder(folder, selecting: result.succeeded.last) }
                if !result.failures.isEmpty { self.errorMessage = result.failures.joined(separator: "\n") }
            }
        }
    }

    func trashSelection() {
        guard !working, let folder else { return }
        guard canModifySelection else {
            statusMessage = "휴지통 이동은 이미지 파일을 선택했을 때 사용할 수 있습니다"
            return
        }
        let urls = files.filter { selection.contains($0.url) }.map(\.url)
        let lastIndex = files.lastIndex { selection.contains($0.url) } ?? 0
        let remaining = files.filter { !selection.contains($0.url) }
        let following = files.dropFirst(lastIndex + 1).first?.url ?? remaining.last?.url
        working = true
        statusMessage = "휴지통으로 이동 중…"
        io.async { [weak self] in
            let result = FileOperations.trash(urls)
            DispatchQueue.main.async {
                guard let self else { return }
                self.working = false
                if self.folder == folder {
                    if result.failures.isEmpty { self.openFolder(folder, selecting: following) }
                    else { self.openFolder(folder) }
                }
                if !result.failures.isEmpty { self.errorMessage = result.failures.joined(separator: "\n") }
            }
        }
    }

    func clearRecentItems() {
        recentURLs = []; defaults.removeObject(forKey: "recentPaths")
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    func savePreferences() { defaults.set(viewMode.rawValue, forKey: "viewMode") }

    private func remember(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(20))
        defaults.set(recentURLs.map(\.path), forKey: "recentPaths")
    }

    private func watch(_ url: URL) {
        monitor?.cancel(); monitor = nil
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib, .extend], queue: .main)
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            guard let self, !self.working, !self.loading else { return }
            self.refreshTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.folder == url, !self.working, !self.loading else { return }
                self.openFolder(url)
            }
            self.refreshTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
        monitor = source
        source.resume()
    }
}
