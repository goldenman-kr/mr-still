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
    private var recentMenu = NSMenu(title: "최근 항목")
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
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last else { return }
        if controller == nil { pendingOpen = url }
        else { controller.showWindow(nil); model.openFile(url); NSApp.activate(ignoringOtherApps: true) }
    }

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
        item("Mr. Still 정보", #selector(about), "", in: app)
        app.addItem(.separator())
        let services = menu("서비스", in: app); NSApp.servicesMenu = services
        app.addItem(.separator())
        item("Mr. Still 가리기", #selector(NSApplication.hide(_:)), "h", in: app, target: NSApp)
        item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", in: app, modifiers: [.command, .option], target: NSApp)
        item("모두 보기", #selector(NSApplication.unhideAllApplications(_:)), "", in: app, target: NSApp)
        app.addItem(.separator())
        item("Mr. Still 종료", #selector(NSApplication.terminate(_:)), "q", in: app, target: NSApp)

        let file = menu("파일", in: main)
        item("파일 열기…", #selector(openFile), "o", in: file)
        item("폴더 열기…", #selector(openFolder), "o", in: file, modifiers: [.command, .shift])
        recentMenu = menu("최근 항목", in: file)
        file.addItem(.separator())
        item("기본 이미지 앱으로 설정", #selector(setDefaultImageApplication), "", in: file)
        file.addItem(.separator())
        item("인쇄…", #selector(printCurrent), "p", in: file)
        file.addItem(.separator())
        item("윈도우 닫기", #selector(closeWindow), "w", in: file)

        let edit = menu("편집", in: main)
        let undo = item("실행 취소", Selector(("undo:")), "z", in: edit); undo.target = nil
        let redo = item("실행 복귀", Selector(("redo:")), "z", in: edit, modifiers: [.command, .shift]); redo.target = nil
        edit.addItem(.separator())
        let copy = item("복사", #selector(copyFiles), "c", in: edit); copy.target = self
        item("붙여넣기", #selector(pasteFiles), "v", in: edit)
        item("전체 선택", #selector(selectAllFiles), "a", in: edit)
        edit.addItem(.separator())
        item("휴지통으로 이동", #selector(trashFiles), "\u{8}", in: edit)

        let go = menu("이동", in: main)
        item("뒤로", #selector(goBack), String(UnicodeScalar(NSLeftArrowFunctionKey)!), in: go, modifiers: .option)
        item("앞으로", #selector(goForward), String(UnicodeScalar(NSRightArrowFunctionKey)!), in: go, modifiers: .option)
        item("위로", #selector(goUp), "", in: go)
        item("새로고침", #selector(refreshFolder), "", in: go)

        let view = menu("보기", in: main)
        item("탐색기 모드", #selector(browserMode), "1", in: view)
        item("슬라이드 모드", #selector(slideMode), "2", in: view)
        view.addItem(.separator())
        item("화면에 맞추기", #selector(fit), "0", in: view)
        item("확대", #selector(zoomIn), "+", in: view)
        let zoomAlias = item("확대", #selector(zoomIn), "=", in: view)
        zoomAlias.isHidden = true; zoomAlias.allowsKeyEquivalentWhenHidden = true
        item("축소", #selector(zoomOut), "-", in: view)
        item("이미지 정보", #selector(info), "i", in: view, modifiers: [])
        view.addItem(.separator())
        item("전체화면 전환", #selector(fullscreen), "f", in: view, modifiers: [])
        let fullscreenAlias = item("전체화면 전환", #selector(fullscreen), "f", in: view)
        fullscreenAlias.isHidden = true; fullscreenAlias.allowsKeyEquivalentWhenHidden = true

        let windowMenu = menu("윈도우", in: main)
        item("최소화", #selector(NSWindow.performMiniaturize(_:)), "m", in: windowMenu, target: nil).target = nil
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    private func rebuildRecentMenu(_ urls: [URL]) {
        recentMenu.removeAllItems()
        for url in urls {
            let entry = item(url.lastPathComponent, #selector(openRecent(_:)), "", in: recentMenu)
            entry.representedObject = url; entry.toolTip = url.path
        }
        if !urls.isEmpty { recentMenu.addItem(.separator()) }
        item("최근 항목 지우기", #selector(clearRecent), "", in: recentMenu)
    }

    @objc private func openFile() { choose(isFolder: false) }
    @objc private func openFolder() { choose(isFolder: true) }
    private func choose(isFolder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = isFolder; panel.canChooseFiles = !isFolder
        panel.allowsMultipleSelection = false
        panel.prompt = "열기"
        panel.directoryURL = model.folder
        if !isFolder { panel.allowedContentTypes = [.image] }
        if panel.runModal() == .OK, let url = panel.url { model.openFile(url) }
    }
    @objc private func openRecent(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { model.openFile(url) } }
    @objc private func clearRecent() { model.clearRecentItems() }
    @objc private func setDefaultImageApplication() {
        guard !settingDefaultImageApplication else { return }
        let applicationURL = Bundle.main.bundleURL
        guard applicationURL.pathExtension == "app" else {
            showDefaultApplicationResult(message: "Mr. Still 앱에서 실행해 주세요.",
                                         details: "기본 앱 설정은 빌드된 Mr. Still.app에서 사용할 수 있습니다.", warning: true)
            return
        }
        settingDefaultImageApplication = true
        Task { @MainActor [self] in
            let result = await DefaultImageApplication.workspace.setSupportedTypes(to: applicationURL)
            settingDefaultImageApplication = false
            showDefaultApplicationResult(message: result.message, details: result.details, warning: !result.failures.isEmpty)
        }
    }

    private func showDefaultApplicationResult(message: String, details: String, warning: Bool) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.alertStyle = warning ? .warning : .informational
        alert.messageText = message
        alert.informativeText = details
        alert.addButton(withTitle: "확인")
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
        if let text = controller.window?.firstResponder as? NSTextView { text.copy(nil) } else { model.copySelection() }
    }
    @objc private func pasteFiles() {
        if let text = controller.window?.firstResponder as? NSTextView, text.isEditable { text.paste(nil) } else { model.pasteFiles() }
    }
    @objc private func selectAllFiles() {
        if let text = controller.window?.firstResponder as? NSTextView { text.selectAll(nil) }
        else { model.select(Set(model.files.map(\.url)), primary: model.currentURL ?? model.files.last?.url) }
    }
    @objc private func trashFiles() { model.trashSelection() }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Mr. Still", .applicationVersion: "1.0", .credits: NSAttributedString(string: "가볍게 탐색하고, 사진에 집중하세요.")])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard controller != nil else { return false }
        switch menuItem.action {
        case #selector(goBack): return model.canGoBack
        case #selector(goForward): return model.canGoForward
        case #selector(goUp): return model.canGoUp
        case #selector(refreshFolder): return model.canRefreshFolder
        case #selector(setDefaultImageApplication):
            menuItem.title = settingDefaultImageApplication ? "기본 이미지 앱 설정 중…" : "기본 이미지 앱으로 설정"
            return !settingDefaultImageApplication
        case #selector(zoomIn), #selector(zoomOut): return model.currentURL != nil && controller.viewer.acceptsZoomCommands
        case #selector(info): return model.currentURL != nil && !((controller.window?.firstResponder as? NSTextView)?.isEditable == true)
        case #selector(fullscreen): return !((controller.window?.firstResponder as? NSTextView)?.isEditable == true)
        case #selector(printCurrent), #selector(fit), #selector(slideMode): return model.currentURL != nil
        case #selector(copyFiles): return controller.window?.firstResponder is NSTextView || model.canModifySelection
        case #selector(trashFiles): return model.canModifySelection && !model.working && !(controller.window?.firstResponder is NSTextView)
        case #selector(pasteFiles): return (controller.window?.firstResponder as? NSTextView)?.isEditable == true || (model.folder != nil && !model.working)
        case #selector(browserMode): menuItem.state = model.slideMode ? .off : .on; return true
        default: return true
        }
    }
}
