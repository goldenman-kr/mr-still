import AppKit
import Combine
import Darwin
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

@MainActor
private final class DirectoryNode: NSObject {
    let url: URL?
    let title: String
    var children: [DirectoryNode]?
    var loading = false
    var loadGeneration = 0
    var loadError: String?
    var waiters: [() -> Void] = []
    init(_ url: URL, title: String? = nil) {
        self.url = url.standardizedFileURL
        self.title = title ?? url.lastPathComponent
    }
    init(favorites: [DirectoryNode]) {
        url = nil
        title = L10n.text("Favorites")
        children = favorites
    }
}

@MainActor
private final class DirectoryOutlineView: NSOutlineView {
    var onContext: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        onContext?(row(at: convert(event.locationInWindow, from: nil)))
    }
}

@MainActor
final class DirectoryTreeController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let model: BrowserModel
    private let homeURL: URL
    private let outline = DirectoryOutlineView()
    private let path: FolderPathBar
    private let back = NSButton()
    private let forward = NSButton()
    private let up = NSButton()
    private let reload = NSButton()
    private let homeButton = NSButton()
    private let favorites = DirectoryNode(favorites: [])
    private var roots: [DirectoryNode] = []
    private var subscriptions = Set<AnyCancellable>()
    private var updatingSelection = false
    private var revealGeneration = 0

    init(model: BrowserModel, homeURL: URL? = nil) {
        self.model = model
        // The sandbox's homeDirectoryForCurrentUser is the app container.
        // Resolving the account home path does not grant or read its contents.
        self.homeURL = homeURL ?? getpwuid(getuid()).flatMap { account in
            account.pointee.pw_dir.map { URL(fileURLWithPath: String(cString: $0), isDirectory: true) }
        } ?? FileManager.default.homeDirectoryForCurrentUser
        path = FolderPathBar(homeURL: self.homeURL)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        path.navigate = { [weak self] target in
            guard let self, target != self.model.folder else { return }
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &directory)
            // Reject files/missing paths without changing the current folder. For an
            // unapproved sandbox location, let the model request a grant before I/O.
            if exists && !directory.boolValue { return }
            if !exists && self.model.access.hasAccess(to: target) { return }
            self.model.openFolder(target)
        }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 26
        outline.indentationPerLevel = 14
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(toggleClickedDirectory(_:))
        outline.setAccessibilityLabel(L10n.text("Folder browser"))
        outline.onContext = { [weak self] row in self?.contextMenu(at: row) }
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let header = NSBox()
        header.boxType = .custom
        header.borderWidth = 0
        header.fillColor = NSColor(calibratedWhite: 0.19, alpha: 1)
        header.contentViewMargins = .zero
        header.identifier = NSUserInterfaceItemIdentifier("DirectoryPathHeader")
        for (button, symbol, label, action) in [
            (back, "arrow.left", L10n.text("Back"), #selector(goBack(_:))),
            (forward, "arrow.right", L10n.text("Forward"), #selector(goForward(_:))),
            (up, "arrow.up", L10n.text("Up"), #selector(goUp(_:))),
            (reload, "arrow.clockwise", L10n.text("Refresh"), #selector(refreshFolder(_:))),
            (homeButton, "house", L10n.text("Home"), #selector(goHome(_:)))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .labelColor
            button.controlSize = .small
            button.target = self; button.action = action
            button.setAccessibilityLabel(L10n.format("Folder navigation: %@", label))
            button.toolTip = label + (button === back ? " (⌥←)" : button === forward ? " (⌥→)" : "")
            button.isEnabled = false
        }
        for child in [back, forward, up, reload, homeButton, path] {
            header.addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
        }
        for child in [header, scroll] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 24),
            back.heightAnchor.constraint(equalToConstant: 24),
            forward.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 2),
            forward.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            forward.widthAnchor.constraint(equalToConstant: 24),
            forward.heightAnchor.constraint(equalToConstant: 24),
            up.leadingAnchor.constraint(equalTo: forward.trailingAnchor, constant: 2),
            up.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            up.widthAnchor.constraint(equalToConstant: 24),
            up.heightAnchor.constraint(equalToConstant: 24),
            reload.leadingAnchor.constraint(equalTo: up.trailingAnchor, constant: 2),
            reload.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            reload.widthAnchor.constraint(equalToConstant: 24),
            reload.heightAnchor.constraint(equalToConstant: 24),
            homeButton.leadingAnchor.constraint(equalTo: reload.trailingAnchor, constant: 2),
            homeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            homeButton.widthAnchor.constraint(equalToConstant: 24),
            homeButton.heightAnchor.constraint(equalToConstant: 24),
            path.leadingAnchor.constraint(equalTo: homeButton.trailingAnchor, constant: 8),
            path.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            path.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            path.heightAnchor.constraint(equalToConstant: 20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if model.access.isSandboxed {
            roots = [favorites, DirectoryNode(homeURL, title: L10n.text("Home"))]
                + model.access.directoryURLs.filter { $0 != homeURL }.map { DirectoryNode($0) }
            outline.reloadData()
            expandAuthorizedHome()
            model.access.$directoryURLs.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] urls in
                guard let self else { return }
                for url in urls where !self.roots.contains(where: { $0.url == url }) {
                    self.roots.append(DirectoryNode(url))
                }
                self.updatingSelection = true
                self.outline.reloadData()
                self.updatingSelection = false
                self.expandAuthorizedHome()
            }.store(in: &subscriptions)
        } else {
            roots = [favorites, DirectoryNode(homeURL, title: L10n.text("Home")),
                     DirectoryNode(URL(fileURLWithPath: "/Volumes", isDirectory: true), title: L10n.text("Volumes"))]
            outline.reloadData()
            // Open Home one level only.
            let home = roots[1]
            load(home) { [weak self, weak home] in
                guard let self, let home else { return }
                self.outline.expandItem(home, expandChildren: false)
            }
        }
        model.$favoriteURLs.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] urls in
            self?.updateFavorites(urls)
        }.store(in: &subscriptions)
        model.$folder.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] folder in
            self?.show(folder)
        }.store(in: &subscriptions)
        model.$loading.combineLatest(model.$folder).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.up.isEnabled = self.model.canGoUp
            self.reload.isEnabled = self.model.canRefreshFolder
            self.homeButton.isEnabled = !self.model.loading
        }.store(in: &subscriptions)
        model.folderRefreshRequested.sink { [weak self] url in
            guard let self else { return }
            self.refreshNodes(self.roots, matching: url)
        }.store(in: &subscriptions)
        model.$canGoBack.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            self?.back.isEnabled = enabled
        }.store(in: &subscriptions)
        model.$canGoForward.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            self?.forward.isEnabled = enabled
        }.store(in: &subscriptions)
    }

    private func expandAuthorizedHome() {
        guard model.access.hasAccess(to: homeURL),
              let home = roots.first(where: { $0.url == homeURL }), home.children == nil else { return }
        load(home) { [weak self, weak home] in
            guard let self, let home else { return }
            self.outline.expandItem(home, expandChildren: false)
        }
    }

    @objc private func goHome(_ sender: Any?) { model.openFolder(homeURL) }

    @objc private func toggleClickedDirectory(_ sender: Any?) {
        toggleDirectory(at: outline.clickedRow)
    }

    func toggleDirectory(at row: Int) {
        guard row >= 0, let node = outline.item(atRow: row) as? DirectoryNode,
              outline.isExpandable(node) else { return }
        if outline.isItemExpanded(node) {
            outline.collapseItem(node, collapseChildren: false)
        } else {
            outline.expandItem(node, expandChildren: false)
        }
    }

    @objc private func goUp(_ sender: Any?) { model.goUp() }
    @objc private func refreshFolder(_ sender: Any?) { model.refreshFolder() }

    private func refreshNodes(_ nodes: [DirectoryNode], matching url: URL) {
        for node in nodes {
            if node.url == url {
                load(node, refresh: true) { [weak self] in
                    guard let self, self.model.folder == url else { return }
                    self.show(url)
                }
            } else {
                refreshNodes(node.children ?? [], matching: url)
            }
        }
    }

    @objc private func goBack(_ sender: Any?) { model.goBack() }
    @objc private func goForward(_ sender: Any?) { model.goForward() }

    private func show(_ folder: URL?) {
        revealGeneration += 1
        path.update(folder)
        guard let folder else {
            updatingSelection = true
            outline.deselectAll(nil)
            updatingSelection = false
            return
        }
        let url = folder.standardizedFileURL
        // Duplicate URLs have distinct nodes in Favorites and the filesystem tree.
        // A folder load should keep the occurrence the user already selected.
        if (outline.item(atRow: outline.selectedRow) as? DirectoryNode)?.url == url { return }
        let favoriteRoot = favorites.children?.filter { node in
            guard let rootURL = node.url else { return false }
            return url == rootURL || url.path.hasPrefix(rootURL.path + "/")
        }.max { ($0.url?.path.count ?? 0) < ($1.url?.path.count ?? 0) }
        if let favoriteRoot {
            outline.expandItem(favorites, expandChildren: false)
            reveal(url, from: favoriteRoot, generation: revealGeneration)
            return
        }
        let root = roots.filter { node in
            guard let rootURL = node.url else { return false }
            return url == rootURL || url.path.hasPrefix(rootURL.path + "/")
        }.max { ($0.url?.path.count ?? 0) < ($1.url?.path.count ?? 0) } ?? addRoot(for: url)
        reveal(url, from: root, generation: revealGeneration)
    }

    private func addRoot(for url: URL) -> DirectoryNode {
        if model.access.isSandboxed {
            let node = DirectoryNode(url)
            roots.append(node)
            updatingSelection = true
            outline.reloadData()
            updatingSelection = false
            return node
        }
        // A filesystem root reveals every ancestor for folders outside Home and Volumes.
        if let existing = roots.first(where: { $0.url?.path == "/" }) { return existing }
        let node = DirectoryNode(URL(fileURLWithPath: "/", isDirectory: true), title: L10n.text("File System"))
        roots.append(node)
        updatingSelection = true
        outline.reloadData()
        updatingSelection = false
        return node
    }

    private func reveal(_ url: URL, from node: DirectoryNode, generation: Int, refreshed: Bool = false) {
        guard generation == revealGeneration else { return }
        if node.url == url {
            let row = outline.row(forItem: node)
            if row >= 0 {
                updatingSelection = true
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
                updatingSelection = false
            }
            return
        }
        load(node) { [weak self, weak node] in
            guard let self, let node, generation == self.revealGeneration else { return }
            self.outline.expandItem(node, expandChildren: false)
            if let next = node.children?.first(where: { child in
                guard let childURL = child.url else { return false }
                return url == childURL || url.path.hasPrefix(childURL.path + "/")
            }) {
                self.reveal(url, from: next, generation: generation)
            } else if !refreshed {
                // A cached parent may predate a folder created by Finder or another app.
                // Retry this parent once; inaccessible or filtered ancestors then use a direct root.
                self.load(node, refresh: true) { [weak self, weak node] in
                    guard let self, let node, generation == self.revealGeneration else { return }
                    self.reveal(url, from: node, generation: generation, refreshed: true)
                }
            } else {
                self.revealDirectRoot(url, generation: generation)
            }
        }
    }

    private func revealDirectRoot(_ url: URL, generation: Int) {
        guard generation == revealGeneration else { return }
        let node: DirectoryNode
        if let existing = roots.first(where: { $0.url == url }) { node = existing }
        else {
            node = DirectoryNode(url)
            roots.append(node)
            updatingSelection = true
            outline.reloadData()
            updatingSelection = false
        }
        reveal(url, from: node, generation: generation)
    }

    private func load(_ node: DirectoryNode, refresh: Bool = false, completion: (() -> Void)? = nil) {
        guard let url = node.url else { completion?(); return }
        // Tree preloading must never request access or probe an unapproved location.
        guard model.access.hasAccess(to: url) else { completion?(); return }
        if !refresh, !node.loading, node.children != nil { completion?(); return }
        if let completion { node.waiters.append(completion) }
        guard refresh || !node.loading else { return }
        node.loading = true
        node.loadGeneration += 1
        let requestGeneration = node.loadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak node] in
            let result = Result { try DirectoryService.subdirectories(of: url) }
            DispatchQueue.main.async {
                guard let self, let node, requestGeneration == node.loadGeneration else { return }
                node.loading = false
                switch result {
                case .success(let urls):
                    // Keep node identities so refreshed siblings retain disclosure/selection state.
                    let existing = Dictionary(uniqueKeysWithValues: (node.children ?? []).map { ($0.url, $0) })
                    node.children = urls.map { existing[$0.standardizedFileURL] ?? DirectoryNode($0) }
                    node.loadError = nil
                case .failure(let error):
                    node.children = []
                    node.loadError = error.localizedDescription
                }
                self.updatingSelection = true
                self.outline.reloadItem(node, reloadChildren: true)
                if node.children?.isEmpty == true { self.outline.collapseItem(node, collapseChildren: false) }
                self.updatingSelection = false
                let callbacks = node.waiters
                node.waiters.removeAll()
                callbacks.forEach { $0() }
            }
        }
    }

    private func updateFavorites(_ urls: [URL]) {
        let wasExpanded = outline.isItemExpanded(favorites)
        let wasEmpty = favorites.children?.isEmpty != false
        let selectedURL = (outline.item(atRow: outline.selectedRow) as? DirectoryNode)?.url
        let existing = Dictionary(uniqueKeysWithValues: (favorites.children ?? []).compactMap { node in
            node.url.map { ($0, node) }
        })
        favorites.children = urls.map { existing[$0] ?? DirectoryNode($0) }
        updatingSelection = true
        outline.reloadItem(favorites, reloadChildren: true)
        if wasExpanded || wasEmpty { outline.expandItem(favorites, expandChildren: false) }
        updatingSelection = false
        if let selectedURL { show(selectedURL) }
    }

    private func contextMenu(at row: Int) -> NSMenu? {
        guard row >= 0, let node = outline.item(atRow: row) as? DirectoryNode, let url = node.url else { return nil }
        let menu = NSMenu()
        let favorite = NSMenuItem(title: model.isFavorite(url) ? L10n.text("Remove from Favorites") : L10n.text("Add to Favorites"), action: #selector(toggleFavorite(_:)), keyEquivalent: "")
        favorite.target = self; favorite.representedObject = url
        menu.addItem(favorite)
        let finder = NSMenuItem(title: L10n.text("Open in Finder"), action: #selector(openInFinder(_:)), keyEquivalent: "")
        finder.target = self; finder.representedObject = url
        menu.addItem(finder)
        return menu
    }

    @objc private func toggleFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if model.isFavorite(url) { model.removeFavorite(url) }
        else { model.addFavorite(url) }
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? DirectoryNode)?.url != nil
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? DirectoryNode else { return roots.count }
        return node.children?.count ?? 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? DirectoryNode { return node.children![index] }
        return roots[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? DirectoryNode else { return false }
        return node.children?.isEmpty != true
    }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        if let node = item as? DirectoryNode, node.children == nil {
            if let url = node.url, !model.access.hasAccess(to: url),
               !model.access.ensureDirectory(url) { return false }
            // The outline owns disclosure state. Loading must not force an expansion later:
            // a capability query (or a collapse while I/O is pending) is not an expand action.
            load(node)
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? DirectoryNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("DirectoryCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? BrowserFileCell ?? BrowserFileCell()
        cell.identifier = identifier
        cell.showFolder(node.title, symbol: node.url == nil ? "star" : node.url == homeURL ? "house" : "folder")
        cell.textField?.font = .systemFont(ofSize: 12, weight: node.url == nil ? .semibold : .regular)
        cell.textField?.textColor = node.url == nil ? .secondaryLabelColor : .labelColor
        cell.toolTip = (node.url?.path ?? L10n.text("Right-click a folder to add it to Favorites")) + (node.loadError.map { "\n" + $0 } ?? "")
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, let node = outline.item(atRow: outline.selectedRow) as? DirectoryNode,
              let url = node.url else { return }
        revealGeneration += 1
        if url != model.folder { model.openFolder(url) }
    }
}

@MainActor
final class FileBrowserController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate,
                                   NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private let model: BrowserModel
    private let collection = BrowserCollectionView()
    private let table = BrowserTableView()
    private let scroll = NSScrollView()
    private let modes = NSSegmentedControl()
    private let sort = NSPopUpButton(frame: .zero, pullsDown: false)
    private let direction = NSButton()
    private let status = NSTextField(labelWithString: L10n.text("Open a folder"))
    private let spinner = NSProgressIndicator()
    private let empty = NSTextField(labelWithString: L10n.text("Open a folder to browse photos"))
    private var files: [ImageFile] = []
    private var subscriptions = Set<AnyCancellable>()
    private var syncing = false
    private var scheduled = false
    private var activeMode: FileViewMode?
    private var preferredURL: URL?
    private var selectionHistory: [URL] = []
    private var previousFolder: URL?
    private var lastRevealedURL: URL?
    private let layout = BalancedThumbnailLayout()

    init(model: BrowserModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        modes.segmentCount = 3
        for (i, entry) in [("square.grid.3x3", L10n.text("Small Thumbnails")), ("square.grid.2x2", L10n.text("Large Thumbnails")), ("list.bullet", L10n.text("List"))].enumerated() {
            modes.setImage(NSImage(systemSymbolName: entry.0, accessibilityDescription: entry.1), forSegment: i)
            modes.setToolTip(entry.1, forSegment: i)
            modes.setWidth(28, forSegment: i)
        }
        modes.segmentStyle = .texturedRounded
        modes.target = self; modes.action = #selector(changeMode(_:))
        modes.setAccessibilityLabel(L10n.text("File view mode"))
        sort.addItems(withTitles: [L10n.text("Name"), L10n.text("Date Modified"), L10n.text("Size")])
        sort.target = self; sort.action = #selector(changeSort(_:))
        sort.setAccessibilityLabel(L10n.text("Sort by"))
        direction.bezelStyle = .texturedRounded
        direction.imagePosition = .imageOnly
        direction.target = self; direction.action = #selector(reverseSort(_:))
        let toolbar = NSStackView(views: [modes, sort, direction])
        toolbar.orientation = .horizontal; toolbar.spacing = 6; toolbar.alignment = .centerY
        sort.widthAnchor.constraint(equalToConstant: 110).isActive = true
        direction.widthAnchor.constraint(equalToConstant: 30).isActive = true
        collection.collectionViewLayout = layout
        collection.autoresizingMask = [.width]
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        layout.minimumInteritemSpacing = 6; layout.minimumLineSpacing = 8
        collection.register(BrowserThumbnailItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("thumbnail"))
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.dataSource = self; collection.delegate = self
        collection.backgroundColors = [.controlBackgroundColor]
        collection.setAccessibilityLabel(L10n.text("Folder and photo thumbnails"))
        collection.onPointer = { [weak self] index in self?.prefer(index) }
        collection.onSelection = { [weak self] in self?.selectionChanged() }
        collection.onReturn = { [weak self] in self?.model.activateSelection() }
        collection.onActivate = { [weak self] index in self?.activateItem(at: index) }
        collection.onCommand = { [weak self] event in self?.handleCommand(event) ?? false }
        collection.onContext = { [weak self] index in self?.contextMenu(at: index) }
        collection.onArrow = { [weak self] forward in self?.keyboardSelection(forward: forward) }

        for (id, title, width) in [("name", L10n.text("Name"), CGFloat(150)), ("size", L10n.text("Size"), 65), ("date", L10n.text("Date Modified"), 110)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "name" ? 80 : 55
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 30; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(openSlide(_:))
        table.onPointer = { [weak self] index in self?.prefer(index) }
        table.onSelection = { [weak self] in self?.selectionChanged() }
        table.onReturn = { [weak self] in self?.model.activateSelection() }
        table.onCommand = { [weak self] event in self?.handleCommand(event) ?? false }
        table.onContext = { [weak self] index in self?.contextMenu(at: index) }
        table.onArrow = { [weak self] forward in self?.keyboardSelection(forward: forward) }
        table.setAccessibilityLabel(L10n.text("Folder and photo list"))

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .controlBackgroundColor
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        empty.textColor = .secondaryLabelColor; empty.font = .systemFont(ofSize: 12)
        empty.alignment = .center; empty.lineBreakMode = .byWordWrapping; empty.maximumNumberOfLines = 3
        for child in [toolbar, scroll, status, spinner, empty] {
            child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 5),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -5),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -5),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            status.heightAnchor.constraint(equalToConstant: 16),
            spinner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            spinner.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16), spinner.heightAnchor.constraint(equalToConstant: 16),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
        model.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &subscriptions)
        refresh()
    }

    private func scheduleRefresh() {
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.async { [weak self] in self?.scheduled = false; self?.refresh() }
    }
    private func refresh() {
        guard isViewLoaded else { return }
        syncing = true
        let changed = files != model.files
        let folderChanged = previousFolder != model.folder
        previousFolder = model.folder
        files = model.files
        if folderChanged { selectionHistory.removeAll(); preferredURL = nil }
        if changed { collection.reloadData(); table.reloadData() }
        modes.selectedSegment = FileViewMode.allCases.firstIndex(of: model.viewMode) ?? 0
        sort.selectItem(at: FileSortKey.allCases.firstIndex(of: model.sortKey) ?? 0)
        let descriptor = NSSortDescriptor(key: model.sortKey.rawValue, ascending: model.ascending)
        if table.sortDescriptors != [descriptor] { table.sortDescriptors = [descriptor] }
        direction.image = NSImage(systemSymbolName: model.ascending ? "arrow.up" : "arrow.down", accessibilityDescription: model.ascending ? L10n.text("Ascending") : L10n.text("Descending"))
        direction.toolTip = model.ascending ? L10n.text("Ascending — click for descending") : L10n.text("Descending — click for ascending")
        direction.setAccessibilityLabel(model.ascending ? L10n.text("Ascending") : L10n.text("Descending"))
        if activeMode != model.viewMode {
            activeMode = model.viewMode
            let isList = model.viewMode == .list
            scroll.documentView = isList ? table : collection
            if !isList { collection.setFrameSize(scroll.contentSize) }
            scroll.hasHorizontalScroller = isList
            layout.itemSize = model.viewMode == .large ? NSSize(width: 120, height: 128) : NSSize(width: 76, height: 88)
            layout.updateSpacing(for: collection.bounds.width)
            layout.invalidateLayout()
            collection.reloadData()
        }
        let indexes = IndexSet(files.indices.filter { model.selection.contains(files[$0].url) })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
        let paths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        if collection.selectionIndexPaths != paths { collection.selectionIndexPaths = paths }
        selectionHistory.removeAll { !model.selection.contains($0) }
        if let primary = model.primarySelectionURL, selectionHistory.last != primary { selectionHistory.removeAll { $0 == primary }; selectionHistory.append(primary) }
        if (folderChanged || model.primarySelectionURL != lastRevealedURL), model.selection.count == 1,
           let current = model.primarySelectionURL, let index = files.firstIndex(where: { $0.url == current }) {
            table.scrollRowToVisible(index)
            collection.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestVerticalEdge)
        }
        lastRevealedURL = model.primarySelectionURL
        empty.isHidden = !files.isEmpty
        empty.stringValue = model.loading ? L10n.text("Reading photo list…") : (model.folder == nil ? L10n.text("Open a folder to browse photos") : L10n.text("No items to display in this folder"))
        let folderCount = files.filter(\.isDirectory).count
        status.stringValue = model.loading ? L10n.text("Loading…") : L10n.format("%ld folders · %ld photos", folderCount, files.count - folderCount) + (model.selection.isEmpty ? "" : L10n.format(" · %ld selected", model.selection.count))
        if model.loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        syncing = false
    }

    private func prefer(_ index: Int?) {
        preferredURL = index.flatMap { files.indices.contains($0) ? files[$0].url : nil }
    }
    private var selectedIndexes: IndexSet {
        activeMode == .list ? table.selectedRowIndexes : IndexSet(collection.selectionIndexPaths.map(\.item))
    }
    private func selectionChanged() {
        guard !syncing else { return }
        let indexes = selectedIndexes.filter { files.indices.contains($0) }
        let urls = Set(indexes.map { files[$0].url })
        let added = indexes.map { files[$0].url }.filter { !model.selection.contains($0) }
        let primary = preferredURL.flatMap { urls.contains($0) ? $0 : nil }
            ?? added.last ?? selectionHistory.last(where: urls.contains) ?? indexes.last.map { files[$0].url }
        selectionHistory.removeAll { !urls.contains($0) }
        if let primary { selectionHistory.removeAll { $0 == primary }; selectionHistory.append(primary) }
        if urls != model.selection || primary != model.primarySelectionURL { model.select(urls, primary: primary) }
    }
    private func keyboardSelection(forward: Bool) {
        let indexes = selectedIndexes
        prefer(forward ? indexes.last : indexes.first)
        selectionChanged()
    }
    private func handleCommand(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": model.copySelection(); return true
        case "v": model.pasteFiles(); return true
        case "\u{7f}", "\u{8}": model.trashSelection(); return true
        default: return false
        }
    }
    private func contextMenu(at index: Int?) -> NSMenu {
        if let index, files.indices.contains(index), !model.selection.contains(files[index].url) {
            prefer(index)
            syncing = true
            if activeMode == .list { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            else { collection.selectionIndexPaths = [IndexPath(item: index, section: 0)] }
            syncing = false
            selectionChanged()
        }
        let menu = NSMenu()
        for (title, selector) in [(L10n.text("Copy"), #selector(copy(_:))), (L10n.text("Paste"), #selector(paste(_:))), (L10n.text("Move to Trash"), #selector(moveToTrash(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        if let index, files.indices.contains(index) {
            menu.addItem(.separator())
            let finder = NSMenuItem(title: L10n.text("Open in Finder"), action: #selector(revealInFinder(_:)), keyEquivalent: "")
            finder.target = self
            finder.representedObject = files.filter { model.selection.contains($0.url) }.map(\.url)
            menu.addItem(finder)
        }
        return menu
    }
    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)) { return model.folder != nil }
        if menuItem.action == #selector(copy(_:)) || menuItem.action == #selector(moveToTrash(_:)) { return model.canModifySelection }
        if menuItem.action == #selector(revealInFinder(_:)) { return !model.selection.isEmpty }
        return true
    }
    @objc func copy(_ sender: Any?) { model.copySelection() }
    @objc func paste(_ sender: Any?) { model.pasteFiles() }
    @objc func moveToTrash(_ sender: Any?) { model.trashSelection() }
    @objc private func changeMode(_ sender: NSSegmentedControl) { model.viewMode = FileViewMode.allCases[sender.selectedSegment] }
    @objc private func changeSort(_ sender: NSPopUpButton) { model.setSort(FileSortKey.allCases[sender.indexOfSelectedItem], ascending: model.ascending) }
    @objc private func reverseSort(_ sender: NSButton) { model.setSort(model.sortKey, ascending: !model.ascending) }
    func activateItem(at index: Int) {
        guard files.indices.contains(index) else { return }
        let url = files[index].url
        // A table doubleAction can arrive before mouseDown finishes syncing selection.
        // Open the clicked item, then use the same slide entry as the viewer.
        model.select([url], primary: url)
        model.activateSelection()
    }

    @objc private func openSlide(_ sender: Any?) { activateItem(at: table.clickedRow) }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("thumbnail"), for: indexPath) as! BrowserThumbnailItem
        item.show(files[indexPath.item], pixels: model.viewMode == .large ? 256 : 160)
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func numberOfRows(in tableView: NSTableView) -> Int { files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = files[row]
        guard let column = tableColumn else { return nil }
        if column.identifier.rawValue == "name" {
            let id = NSUserInterfaceItemIdentifier("FileCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? BrowserFileCell ?? BrowserFileCell()
            cell.identifier = id; cell.show(file); return cell
        }
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? BrowserDetailCell ?? BrowserDetailCell()
        cell.identifier = column.identifier
        cell.textField?.stringValue = column.identifier.rawValue == "size" ? (file.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) : file.modified.formatted(date: .numeric, time: .omitted)
        return cell
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !syncing, let descriptor = tableView.sortDescriptors.first,
              let rawKey = descriptor.key, let key = FileSortKey(rawValue: rawKey) else { return }
        model.setSort(key, ascending: descriptor.ascending)
    }
    func tableViewSelectionDidChange(_ notification: Notification) { selectionChanged() }
}

private final class BrowserDetailCell: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let label = NSTextField(labelWithString: "")
        textField = label
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class BrowserFileCell: NSTableCellView {
    private var representedURL: URL?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView(); let label = NSTextField(labelWithString: "")
        imageView = icon; textField = label
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.lineBreakMode = .byTruncatingMiddle; label.font = .systemFont(ofSize: 12)
        for child in [icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3), icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func showFolder(_ title: String, symbol: String = "folder") {
        representedURL = nil; textField?.stringValue = title
        imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    func show(_ file: ImageFile) {
        if file.isDirectory {
            showFolder(file.name, symbol: "folder.fill")
            toolTip = file.url.path
            return
        }
        representedURL = file.url; textField?.stringValue = file.name; toolTip = file.name
        imageView?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        ThumbnailService.shared.image(for: file.url, pixelSize: 64) { [weak self] image in
            guard let self, self.representedURL == file.url else { return }; self.imageView?.image = image
        }
    }
}

private final class BalancedThumbnailLayout: NSCollectionViewFlowLayout {
    func updateSpacing(for width: CGFloat) {
        guard itemSize.width > 0 else { return }
        let columns = max(1, floor((width - 8) / (itemSize.width + 8)))
        let gap = max(0, (width - columns * itemSize.width) / (columns + 1))
        sectionInset = NSEdgeInsets(top: 8, left: gap, bottom: 8, right: gap)
        // Flow layout distributes remaining space. Round its minimum down
        // so floating-point error cannot unexpectedly remove a column.
        minimumInteritemSpacing = floor(gap)
        invalidateLayout()
    }
}

private final class BrowserThumbnailItem: NSCollectionViewItem {
    private var representedURL: URL?
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 5
        let photo = NSImageView(); let label = NSTextField(labelWithString: "")
        imageView = photo; textField = label
        photo.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 11); label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle
        for child in [photo, label] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            photo.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5), photo.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            photo.topAnchor.constraint(equalTo: view.topAnchor, constant: 5), photo.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5), label.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    override var isSelected: Bool { didSet { updateSelection() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateSelection() } }
    private func updateSelection() {
        view.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.32) : .clear).cgColor
        view.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : .clear).cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
    }
    func show(_ file: ImageFile, pixels: Int) {
        _ = view
        representedURL = file.url; textField?.stringValue = file.name; view.toolTip = file.name
        imageView?.image = NSImage(systemSymbolName: file.isDirectory ? "folder.fill" : "photo", accessibilityDescription: file.isDirectory ? L10n.text("Folder") : nil)
        view.setAccessibilityLabel(file.isDirectory ? L10n.format("Folder: %@", file.name) : file.name)
        updateSelection()
        guard !file.isDirectory else { return }
        ThumbnailService.shared.image(for: file.url, pixelSize: pixels) { [weak self] image in
            guard let self, self.representedURL == file.url else { return }; self.imageView?.image = image
        }
    }
    override func prepareForReuse() { super.prepareForReuse(); representedURL = nil; imageView?.image = nil }
}

private final class BrowserCollectionView: NSCollectionView {
    override func setFrameSize(_ newSize: NSSize) {
        let previousWidth = bounds.width
        super.setFrameSize(newSize)
        if bounds.width != previousWidth {
            (collectionViewLayout as? BalancedThumbnailLayout)?.updateSpacing(for: bounds.width)
        }
    }

    var onActivate: ((Int) -> Void)?
    var onPointer: ((Int?) -> Void)?
    var onSelection: (() -> Void)?
    var onReturn: (() -> Void)?
    var onCommand: ((NSEvent) -> Bool)?
    var onContext: ((Int?) -> NSMenu?)?
    var onArrow: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item
        onPointer?(index)
        super.mouseDown(with: event)
        onSelection?()
        if event.clickCount == 2, let index { onActivate?(index) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        onContext?(indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item)
    }
    override func keyDown(with event: NSEvent) {
        if onCommand?(event) == true { return }
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        onPointer?(nil)
        super.keyDown(with: event)
        if [123, 124, 125, 126].contains(event.keyCode) { onArrow?(event.keyCode == 124 || event.keyCode == 125) }
        else { onSelection?() }
    }
}

private final class BrowserTableView: NSTableView {
    var onPointer: ((Int?) -> Void)?
    var onSelection: (() -> Void)?
    var onReturn: (() -> Void)?
    var onCommand: ((NSEvent) -> Bool)?
    var onContext: ((Int?) -> NSMenu?)?
    var onArrow: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        onPointer?(index >= 0 ? index : nil)
        super.mouseDown(with: event)
        onSelection?()
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        return onContext?(index >= 0 ? index : nil)
    }
    override func keyDown(with event: NSEvent) {
        if onCommand?(event) == true { return }
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        onPointer?(nil)
        super.keyDown(with: event)
        if [123, 124, 125, 126].contains(event.keyCode) { onArrow?(event.keyCode == 124 || event.keyCode == 125) }
        else { onSelection?() }
    }
}
