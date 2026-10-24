import AppKit
import Combine
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controller: MainWindowController!
    private let model = BrowserModel()
    private var recentMenu = NSMenu(title: L10n.text("Open Recent"))
    private var subscriptions: Set<AnyCancellable> = []
    private var pendingOpen: URL?
    private var settingDefaultImageApplication = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        controller = MainWindowController(model: model)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.$recentURLs.sink { [weak self] urls in self?.rebuildRecentMenu(urls) }.store(in: &subscriptions)
        if let pendingOpen { model.openFile(pendingOpen) }
        else if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.indices.contains(index + 1) {
            model.openFile(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        } else if model.access.isSandboxed && model.access.directoryURLs.isEmpty {
            choose(isFolder: true)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last else { return }
        if controller == nil { pendingOpen = url }
        else { controller.showWindow(nil); model.openFile(url); NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationWillTerminate(_ notification: Notification) { model.access.stopAll() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showWindow(nil); return true
    }

    private func menu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title); item.submenu = submenu; parent.addItem(item); return submenu
    }
    @discardableResult
    private func item(_ title: String, _ action: Selector?, _ key: String, in menu: NSMenu, modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    private func buildMenu() {
        let main = NSMenu()
        let app = menu("Mr. Still", in: main)
        item(L10n.text("About Mr. Still"), #selector(about), "", in: app)
        app.addItem(.separator())
        let services = menu(L10n.text("Services"), in: app); NSApp.servicesMenu = services
        app.addItem(.separator())
        item(L10n.text("Hide Mr. Still"), #selector(NSApplication.hide(_:)), "h", in: app, target: NSApp)
        item(L10n.text("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", in: app, modifiers: [.command, .option], target: NSApp)
        item(L10n.text("Show All"), #selector(NSApplication.unhideAllApplications(_:)), "", in: app, target: NSApp)
        app.addItem(.separator())
        item(L10n.text("Quit Mr. Still"), #selector(NSApplication.terminate(_:)), "q", in: app, target: NSApp)

        let file = menu(L10n.text("File"), in: main)
        item(L10n.text("Open File…"), #selector(openFile), "o", in: file)
        item(L10n.text("Open Folder…"), #selector(openFolder), "o", in: file, modifiers: [.command, .shift])
        recentMenu = menu(L10n.text("Open Recent"), in: file)
        file.addItem(.separator())
        item(L10n.text("Set as Default Image App"), #selector(setDefaultImageApplication), "", in: file)
        file.addItem(.separator())
        item(L10n.text("Print…"), #selector(printCurrent), "p", in: file)
        file.addItem(.separator())
        item(L10n.text("Close Window"), #selector(closeWindow), "w", in: file)

        let edit = menu(L10n.text("Edit"), in: main)
        let undo = item(L10n.text("Undo"), Selector(("undo:")), "z", in: edit); undo.target = nil
        let redo = item(L10n.text("Redo"), Selector(("redo:")), "z", in: edit, modifiers: [.command, .shift]); redo.target = nil
        edit.addItem(.separator())
        let copy = item(L10n.text("Copy"), #selector(copyFiles), "c", in: edit); copy.target = self
        item(L10n.text("Paste"), #selector(pasteFiles), "v", in: edit)
        item(L10n.text("Select All"), #selector(selectAllFiles), "a", in: edit)
        edit.addItem(.separator())
        item(L10n.text("Move to Trash"), #selector(trashFiles), "\u{8}", in: edit)

        let go = menu(L10n.text("Go"), in: main)
        item(L10n.text("Back"), #selector(goBack), String(UnicodeScalar(NSLeftArrowFunctionKey)!), in: go, modifiers: .option)
        item(L10n.text("Forward"), #selector(goForward), String(UnicodeScalar(NSRightArrowFunctionKey)!), in: go, modifiers: .option)
        item(L10n.text("Up"), #selector(goUp), "", in: go)
        item(L10n.text("Refresh"), #selector(refreshFolder), "", in: go)

        let view = menu(L10n.text("View"), in: main)
        item(L10n.text("Browser Mode"), #selector(browserMode), "1", in: view)
        item(L10n.text("Slide Mode"), #selector(slideMode), "2", in: view)
        view.addItem(.separator())
        item(L10n.text("Fit to Window"), #selector(fit), "0", in: view)
        item(L10n.text("Zoom In"), #selector(zoomIn), "+", in: view)
        let zoomAlias = item(L10n.text("Zoom In"), #selector(zoomIn), "=", in: view)
        zoomAlias.isHidden = true; zoomAlias.allowsKeyEquivalentWhenHidden = true
        item(L10n.text("Zoom Out"), #selector(zoomOut), "-", in: view)
        item(L10n.text("Image Info"), #selector(info), "i", in: view, modifiers: [])
        view.addItem(.separator())
        item(L10n.text("Toggle Full Screen"), #selector(fullscreen), "f", in: view, modifiers: [])
        let fullscreenAlias = item(L10n.text("Toggle Full Screen"), #selector(fullscreen), "f", in: view)
        fullscreenAlias.isHidden = true; fullscreenAlias.allowsKeyEquivalentWhenHidden = true

        let windowMenu = menu(L10n.text("Window"), in: main)
        item(L10n.text("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m", in: windowMenu, target: nil).target = nil
        NSApp.windowsMenu = windowMenu
        let help = menu(L10n.text("Help"), in: main)
        item(L10n.text("Privacy Policy"), #selector(privacyPolicy), "", in: help)
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }

    private func rebuildRecentMenu(_ urls: [URL]) {
        recentMenu.removeAllItems()
        for url in urls {
            let entry = item(url.lastPathComponent, #selector(openRecent(_:)), "", in: recentMenu)
            entry.representedObject = url; entry.toolTip = url.path
        }
        if !urls.isEmpty { recentMenu.addItem(.separator()) }
        item(L10n.text("Clear Menu"), #selector(clearRecent), "", in: recentMenu)
    }

    @objc private func openFile() { choose(isFolder: false) }
    @objc private func openFolder() { choose(isFolder: true) }
    private func choose(isFolder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = isFolder; panel.canChooseFiles = !isFolder
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Open")
        panel.directoryURL = model.folder
        if !isFolder { panel.allowedContentTypes = [.image] }
        if panel.runModal() == .OK, let url = panel.url {
            if isFolder && !model.access.authorizeDirectory(url) {
                model.errorMessage = L10n.text("Folder access was not granted. Use File > Open Folder to choose it again.")
                return
            }
            model.openFile(url)
        }
    }
    @objc private func openRecent(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { model.openFile(url) } }
    @objc private func clearRecent() { model.clearRecentItems() }
    @objc private func setDefaultImageApplication() {
        guard !settingDefaultImageApplication else { return }
#if APP_STORE
        showDefaultApplicationResult(message: L10n.text("Choose the default image app in Finder"),
            details: L10n.text("In Finder, select an image and choose Get Info. Under Open with, choose Mr. Still, then click Change All. Repeat for each image format you use."), warning: false)
        if let url = model.currentURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        return
#else
        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app" else {
            showDefaultApplicationResult(message: L10n.text("Please run this from the Mr. Still app."),
                                         details: L10n.text("Default app settings are available in the built Mr. Still.app."), warning: true)
            return
        }
        settingDefaultImageApplication = true
        Task { @MainActor [self] in
            let result = await DefaultImageApplication.workspace.setSupportedTypes(to: applicationURL)
            settingDefaultImageApplication = false
            showDefaultApplicationResult(message: result.message, details: result.details, warning: !result.failures.isEmpty)
        }
#endif
    }

    private func showDefaultApplicationResult(message: String, details: String, warning: Bool) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.alertStyle = warning ? .warning : .informational
        alert.messageText = message
        alert.informativeText = details
        alert.addButton(withTitle: L10n.text("OK"))
        alert.beginSheetModal(for: window)
    }
    @objc private func printCurrent() { controller.viewer.printImage() }
    @objc private func closeWindow() { controller.window?.performClose(nil) }
    @objc private func goBack() { model.goBack() }
    @objc private func goForward() { model.goForward() }
    @objc private func goUp() { model.goUp() }
    @objc private func refreshFolder() { model.refreshFolder() }
    @objc private func browserMode() { model.slideMode = false }
    @objc private func slideMode() { model.enterSlide() }
    @objc private func fit() { controller.viewer.fitImage() }
    @objc private func zoomIn() { controller.viewer.zoomIn() }
    @objc private func zoomOut() { controller.viewer.zoomOut() }
    @objc private func info() { controller.viewer.toggleInfo() }
    @objc private func fullscreen() { controller.toggleFullscreen() }
    @objc private func copyFiles() {
        if let text = controller.window?.firstResponder as? NSTextView { text.copy(nil) }
        else if controller.viewer.acceptsZoomCommands { controller.viewer.copyImage() }
        else { model.copySelection() }
    }
    @objc private func pasteFiles() {
        if let text = controller.window?.firstResponder as? NSTextView, text.isEditable { text.paste(nil) } else { model.pasteFiles() }
    }
    @objc private func selectAllFiles() {
        if let text = controller.window?.firstResponder as? NSTextView { text.selectAll(nil) }
        else { model.select(Set(model.files.map(\.url)), primary: model.currentURL ?? model.files.last?.url) }
    }
    @objc private func trashFiles() { model.trashSelection() }
    @objc private func privacyPolicy() {
        let language = Bundle.main.preferredLocalizations.first == "ko" ? "ko" : "en"
        guard let url = Bundle.main.url(forResource: "privacy-policy-" + language, withExtension: "html") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Mr. Still", .applicationVersion: "1.0", .credits: NSAttributedString(string: L10n.text("Browse lightly. Focus on your photos."))])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard controller != nil else { return false }
        switch menuItem.action {
        case #selector(goBack): return model.canGoBack
        case #selector(goForward): return model.canGoForward
        case #selector(goUp): return model.canGoUp
        case #selector(refreshFolder): return model.canRefreshFolder
        case #selector(setDefaultImageApplication):
            menuItem.title = settingDefaultImageApplication ? L10n.text("Setting Default Image App…") : L10n.text("Set as Default Image App")
            return !settingDefaultImageApplication
        case #selector(zoomIn), #selector(zoomOut): return model.currentURL != nil && controller.viewer.acceptsZoomCommands
        case #selector(info): return model.currentURL != nil && !((controller.window?.firstResponder as? NSTextView)?.isEditable == true)
        case #selector(fullscreen): return !((controller.window?.firstResponder as? NSTextView)?.isEditable == true)
        case #selector(printCurrent), #selector(fit), #selector(slideMode): return model.currentURL != nil
        case #selector(copyFiles):
            if controller.window?.firstResponder is NSTextView { return true }
            return controller.viewer.acceptsZoomCommands ? controller.viewer.canCopyImage : model.canModifySelection
        case #selector(trashFiles): return model.canModifySelection && !model.working && !(controller.window?.firstResponder is NSTextView)
        case #selector(pasteFiles): return (controller.window?.firstResponder as? NSTextView)?.isEditable == true || (model.folder != nil && !model.working)
        case #selector(browserMode): menuItem.state = model.slideMode ? .off : .on; return true
        default: return true
        }
    }
}
