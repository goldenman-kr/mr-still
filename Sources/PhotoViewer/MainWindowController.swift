import AppKit
import Combine
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

private final class PhotoWindow: NSWindow {
    var escapeAction: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escapeAction?() }
}

private final class PaneSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 4 }
    override func drawDivider(in rect: NSRect) {
        NSColor(calibratedWhite: 0.23, alpha: 1).setFill()
        rect.fill()
    }
}

enum ViewingShortcut {
    case info, fullscreen

    static func action(for event: NSEvent, firstResponder: NSResponder?) -> Self? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              (firstResponder as? NSTextView)?.isEditable != true,
              (firstResponder as? NSTextField)?.isEditable != true else { return nil }
        // Physical ANSI I/F positions also work when the input source produces ㅑ/ㄹ.
        switch event.keyCode {
        case 34: return .info
        case 3: return .fullscreen
        default: return nil
        }
    }
}

enum FolderNavigationInput {
    case back, forward

    static func action(for event: NSEvent, firstResponder: NSResponder?) -> Self? {
        switch event.type {
        case .keyDown:
            // Preserve Option-arrow word navigation while editing the zoom field.
            guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option,
                  (firstResponder as? NSTextView)?.isEditable != true,
                  (firstResponder as? NSTextField)?.isEditable != true else { return nil }
            switch event.keyCode {
            case 123: return .back
            case 124: return .forward
            default: return nil
            }
        case .otherMouseDown, .otherMouseUp:
            switch event.buttonNumber {
            case 3: return .back
            case 4: return .forward
            default: return nil
            }
        default: return nil
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate {
    let model: BrowserModel
    let viewer: ViewerController
    let tree: DirectoryTreeController
    let browser: FileBrowserController
    private let content = NSView()
    private let outer = PaneSplitView()
    private let left = PaneSplitView()
    private let viewerHost = NSView()
    private var shortcutMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []
    private var storedLeftWidth: CGFloat = 360
    private var storedTopRatio: CGFloat = 0.4
    private var presentingFullscreen = false
    private var fullscreenTransition = false
    private var modeBeforeFullscreen: Bool?
    private var initialLayout = true
    private var adjusting = false

    init(model: BrowserModel) {
        self.model = model
        viewer = ViewerController(model: model)
        tree = DirectoryTreeController(model: model)
        browser = FileBrowserController(model: model)
        let window = PhotoWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Mr. Still"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PhotoViewer.MainWindow")
        window.contentMinSize = browserMinimumSize
        if let width = UserDefaults.standard.object(forKey: "leftPaneWidth") as? Double { storedLeftWidth = max(280, width) }
        if let ratio = UserDefaults.standard.object(forKey: "treeRatio") as? Double { storedTopRatio = max(0.1, min(0.9, ratio)) }

        content.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentView = content
        outer.frame = content.bounds
        outer.isVertical = true; outer.dividerStyle = .thin
        left.isVertical = false; left.dividerStyle = .thin
        left.addArrangedSubview(tree.view); left.addArrangedSubview(browser.view)
        outer.addArrangedSubview(left); outer.addArrangedSubview(viewerHost)
        viewer.view.autoresizingMask = [.width, .height]
        viewerHost.addSubview(viewer.view)
        outer.autoresizingMask = [.width, .height]
        content.addSubview(outer)
        outer.delegate = self; left.delegate = self
        layoutPanels()
        window.escapeAction = { [weak self] in self?.escape() }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleFolderNavigation(event) || self.handleViewingShortcut(event) ? nil : event
        }
        model.toggleFullscreen = { [weak self] in self?.toggleFullscreen() }
        model.$slideMode.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updatePresentation() }
        }.store(in: &subscriptions)
        model.$currentURL.sink { [weak self] url in
            self?.window?.title = url.map { "\($0.lastPathComponent) — Mr. Still" } ?? "Mr. Still"
            self?.window?.representedURL = url
        }.store(in: &subscriptions)
        model.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            DispatchQueue.main.async { self?.showError(message) }
        }.store(in: &subscriptions)
        model.$viewMode.sink { [weak model] _ in DispatchQueue.main.async { model?.savePreferences() } }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
    }

    private var browserMinimumSize: NSSize {
        NSSize(width: LayoutMath.leftMinimum + LayoutMath.rightMinimum + outer.dividerThickness,
               height: 160 + 240 + left.dividerThickness)
    }

    func handleViewingShortcut(_ event: NSEvent) -> Bool {
        guard let window, let eventWindow = event.window,
              eventWindow === window || eventWindow.parent === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              let action = ViewingShortcut.action(for: event, firstResponder: eventWindow.firstResponder) else { return false }
        // Swallow repeats too, so menu handling cannot toggle again while held.
        guard !event.isARepeat else { return true }
        switch action {
        case .info: viewer.toggleInfo()
        case .fullscreen: toggleFullscreen()
        }
        return true
    }

    func handleFolderNavigation(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              let action = FolderNavigationInput.action(for: event, firstResponder: window.firstResponder) else { return false }
        // Consume both mouse phases but navigate once. An unavailable history
        // command must not fall through to the canvas's photo-arrow handling.
        if event.type == .otherMouseUp || (event.type == .keyDown && event.isARepeat) { return true }
        switch action {
        case .back: model.goBack()
        case .forward: model.goForward()
        }
        return true
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        layoutPanels()
    }

    private var hideBrowser: Bool { model.slideMode || presentingFullscreen }

    private func updatePresentation() {
        guard let window else { return }
        let hidden = hideBrowser
        if !hidden && !fullscreenTransition {
            let size = window.contentLayoutRect.size
            if size.width < browserMinimumSize.width || size.height < browserMinimumSize.height {
                window.setContentSize(NSSize(width: max(size.width, browserMinimumSize.width), height: max(size.height, browserMinimumSize.height)))
            }
        }
        window.contentMinSize = hidden ? NSSize(width: 400, height: 320) : browserMinimumSize
        // Keep both split panes installed. Removing an arranged subview lets
        // NSSplitView expand the remaining pane and retain conflicting constraints.
        // Only the viewer moves; the hidden split keeps its browser geometry.
        adjusting = true
        if hidden {
            outer.autoresizingMask = []
            outer.isHidden = true
            if viewer.view.superview !== content {
                viewer.view.removeFromSuperview()
                content.addSubview(viewer.view)
            }
        } else {
            if viewer.view.superview !== viewerHost {
                viewer.view.removeFromSuperview()
                viewerHost.addSubview(viewer.view)
            }
            outer.frame = content.bounds
            outer.autoresizingMask = [.width, .height]
            outer.isHidden = false
        }
        adjusting = false
        layoutPanels()
        viewer.setFullscreen(presentingFullscreen)
        content.needsDisplay = true
        if hidden { viewer.focusCanvas() }
    }

    private func layoutPanels() {
        guard !adjusting else { return }
        adjusting = true
        defer { adjusting = false }
        let bounds = outer.bounds
        if hideBrowser {
            viewer.view.frame = content.bounds
        } else {
            let width = LayoutMath.leftWidth(total: bounds.width, previous: storedLeftWidth, divider: outer.dividerThickness)
            storedLeftWidth = width
            left.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
            viewerHost.frame = NSRect(x: width + outer.dividerThickness, y: 0, width: max(0, bounds.width - width - outer.dividerThickness), height: bounds.height)
            viewer.view.frame = viewerHost.bounds
            layoutLeft()
        }
        initialLayout = false
    }

    private func layoutLeft() {
        guard !hideBrowser else { return }
        let available = max(0, left.bounds.height - left.dividerThickness)
        let topHeight = max(160, min(available - 240, available * storedTopRatio))
        tree.view.frame = NSRect(x: 0, y: 0, width: left.bounds.width, height: topHeight)
        browser.view.frame = NSRect(x: 0, y: topHeight + left.dividerThickness, width: left.bounds.width, height: max(0, available - topHeight))
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        if splitView === outer { layoutPanels() }
        else { layoutLeft() }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView === outer ? 280 : 160
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView === outer ? max(280, splitView.bounds.width - 400 - splitView.dividerThickness) : max(160, splitView.bounds.height - 240 - splitView.dividerThickness)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool { splitView === outer && hideBrowser }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !adjusting, !initialLayout, !hideBrowser, let split = notification.object as? NSSplitView else { return }
        if split === outer { storedLeftWidth = max(280, left.frame.width) }
        else if left.bounds.height > 1 { storedTopRatio = tree.view.frame.height / (left.bounds.height - left.dividerThickness) }
    }

    func toggleFullscreen() {
        guard !fullscreenTransition else { return }
        window?.toggleFullScreen(nil)
    }

    private func escape() {
        if presentingFullscreen { toggleFullscreen() }
        else if model.slideMode { model.slideMode = false }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        modeBeforeFullscreen = model.slideMode
        fullscreenTransition = true; presentingFullscreen = true; updatePresentation()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { fullscreenTransition = false; viewer.focusCanvas() }
    func windowWillExitFullScreen(_ notification: Notification) { fullscreenTransition = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        restoreModeBeforeFullscreen()
        fullscreenTransition = false; presentingFullscreen = false; updatePresentation()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        restoreModeBeforeFullscreen()
        fullscreenTransition = false; presentingFullscreen = false; updatePresentation()
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { fullscreenTransition = false }

    private func restoreModeBeforeFullscreen() {
        if let modeBeforeFullscreen { model.slideMode = modeBeforeFullscreen }
        modeBeforeFullscreen = nil
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(Double(storedLeftWidth), forKey: "leftPaneWidth")
        UserDefaults.standard.set(Double(storedTopRatio), forKey: "treeRatio")
        model.savePreferences()
    }

    private func showError(_ message: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("The operation could not be completed")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("OK"))
        model.errorMessage = nil
        alert.beginSheetModal(for: window)
    }
}
