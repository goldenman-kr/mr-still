import AppKit
import UniformTypeIdentifiers
import Combine
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

@MainActor
final class ViewerController: NSViewController, NSTextFieldDelegate, NSPopoverDelegate {
    private let model: BrowserModel
    let canvas = ImageCanvasView()
    private let status = NSView()
    private let statusControls = NSStackView()
    private let slider = NSSlider(value: 0, minValue: -7, maxValue: log(3), target: nil, action: nil)
    private let percent = NSTextField(string: "100")
    private let details = NSTextField(labelWithString: L10n.text("Open a folder or photo"))
    private var modeButton: NSButton!
    private var fullscreenButton: NSButton!
    private var infoButton: NSButton!
    private let closeButton = NSButton()
    private var subscriptions = Set<AnyCancellable>()
    private var generation = UUID()
    private var imageURL: URL?
    private var displayedFile: ImageFile?
    private var decodedLimit = 0
    private var upgradePending = false
    private var fitted = true
    private var fullscreen = false
    private var pointerNearBottom = false
    private var percentEditStartingText: String?
    private var canvasAboveStatus: NSLayoutConstraint!
    private var canvasToBottom: NSLayoutConstraint!
    private var metadataPopover: NSPopover?
    private let decoding: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PhotoViewer.viewer.decode"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    var acceptsZoomCommands: Bool { isViewLoaded && view.window?.firstResponder === canvas }
    var isStatusBarVisible: Bool { isViewLoaded && !status.isHidden }

    init(model: BrowserModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = ViewerTrackingView()
        root.onPointerChange = { [weak self] point in self?.updateFullscreenHover(at: point) }
        view = root
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        canvas.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        statusControls.translatesAutoresizingMaskIntoConstraints = false
        statusControls.orientation = .horizontal
        statusControls.spacing = 7
        statusControls.distribution = .fill
        status.wantsLayer = true
        status.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        let fit = button("arrow.down.right.and.arrow.up.left", L10n.text("Fit to Window"), #selector(fitAction))
        infoButton = button("info.circle", L10n.text("Image Info (I)"), #selector(infoAction))
        modeButton = button("sidebar.left", L10n.text("Browser / Slide Mode"), #selector(modeAction))
        fullscreenButton = button("arrow.up.left.and.arrow.down.right", L10n.text("Full Screen (F)"), #selector(fullscreenAction))
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.setAccessibilityLabel(L10n.text("Image zoom level"))
        slider.widthAnchor.constraint(equalToConstant: 86).isActive = true
        percent.alignment = .right
        percent.target = self
        percent.action = #selector(percentChanged)
        percent.delegate = self
        percent.widthAnchor.constraint(equalToConstant: 66).isActive = true
        percent.setAccessibilityLabel(L10n.text("Zoom percentage"))
        details.lineBreakMode = .byTruncatingMiddle
        details.font = .systemFont(ofSize: 10)
        details.textColor = .secondaryLabelColor
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        details.setContentHuggingPriority(.defaultLow, for: .horizontal)
        details.translatesAutoresizingMaskIntoConstraints = false
        status.addSubview(details)
        status.addSubview(statusControls)
        for item in [slider, percent, NSTextField(labelWithString: "%"), fit, modeButton!, fullscreenButton!, infoButton!] {
            statusControls.addArrangedSubview(item)
        }
        NSLayoutConstraint.activate([
            status.heightAnchor.constraint(equalToConstant: 34),
            statusControls.trailingAnchor.constraint(equalTo: status.trailingAnchor, constant: -8),
            statusControls.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            details.leadingAnchor.constraint(equalTo: status.leadingAnchor, constant: 8),
            details.trailingAnchor.constraint(equalTo: statusControls.leadingAnchor, constant: -8),
            details.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            details.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
        view.addSubview(canvas)
        view.addSubview(status)
        canvasAboveStatus = canvas.bottomAnchor.constraint(equalTo: status.topAnchor)
        canvasToBottom = canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvasAboveStatus,
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        canvas.contextMenuProvider = { [weak self] in self?.imageContextMenu() }
        canvas.onNavigate = { [weak model] step in model?.navigate(step) }
        canvas.onDoubleClick = { [weak self] in
            guard let self, !self.fullscreen else { return }
            if self.model.slideMode { self.model.slideMode = false } else { self.model.enterSlide() }
        }
        canvas.onEnter = { [weak self] in
            guard let self, !self.fullscreen else { return }
            self.model.enterSlide()
        }
        canvas.onZoom = { [weak self] factor, anchor in
            guard let self else { return }
            self.applyZoom(self.canvas.scale * factor, anchor: anchor)
        }
        canvas.onViewportChange = { [weak self] in
            guard let self else { return }
            if self.fitted { self.fitImage() } else { self.canvas.constrainPan(); self.canvas.needsDisplay = true }
        }
        configureCloseButton()
        model.$currentURL.removeDuplicates().sink { [weak self] url in self?.load(url) }.store(in: &subscriptions)
        model.$selection.sink { [weak self, weak model] selection in
            self?.canvas.selectionCount = model?.files.filter { !$0.isDirectory && selection.contains($0.url) }.count ?? 0
            self?.canvas.needsDisplay = true
        }.store(in: &subscriptions)
        model.$files.sink { [weak self] files in
            guard let self, let url = self.imageURL,
                  let updated = files.first(where: { $0.url == url }),
                  let previous = self.displayedFile, previous != updated else { return }
            self.load(url)
            self.displayedFile = updated
        }.store(in: &subscriptions)
        model.$slideMode.sink { [weak self] slide in
            self?.modeButton.image = NSImage(systemSymbolName: slide ? "sidebar.left" : "rectangle", accessibilityDescription: slide ? L10n.text("Back to Browser") : L10n.text("Slide Mode"))
        }.store(in: &subscriptions)
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let result = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: self, action: action)
        result.bezelStyle = .inline
        result.toolTip = label
        result.setAccessibilityLabel(label)
        result.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return result
    }

    private func configureCloseButton() {
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.text("Exit Full Screen"))
        closeButton.target = self
        closeButton.action = #selector(fullscreenAction)
        closeButton.bezelStyle = .inline
        closeButton.contentTintColor = .white
        closeButton.toolTip = L10n.text("Exit Full Screen (Esc)")
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        canvas.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -14),
            closeButton.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func load(_ url: URL?) {
        decoding.cancelAllOperations()
        generation = UUID()
        imageURL = url
        displayedFile = model.files.first { $0.url == url }
        decodedLimit = 0
        upgradePending = false
        fitted = true
        metadataPopover?.close()
        canvas.image = nil
        canvas.pixelSize = .zero
        canvas.pan = .zero
        canvas.message = url == nil ? L10n.text("Open a folder or photo") : L10n.text("Loading photo…")
        canvas.needsDisplay = true
        details.stringValue = url?.lastPathComponent ?? L10n.text("No photo selected")
        updateControls()
        guard let url else { return }
        let token = generation
        let limit = max(2048, min(4096, Int(max(canvas.bounds.width, canvas.bounds.height) * canvas.backingScale)))
        decode(url, limit: limit) { [weak self] result in
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let loaded):
                    self.canvas.image = loaded.image
                    self.canvas.pixelSize = loaded.pixelSize
                    self.decodedLimit = max(loaded.image.width, loaded.image.height)
                    self.canvas.message = ""
                    self.fitImage()
                case .failure(let error):
                    self.canvas.message = L10n.format("Could not open image\n%@", error.localizedDescription)
                    self.details.stringValue = L10n.format("Loading failed · %@", url.lastPathComponent)
                    self.canvas.needsDisplay = true
                    self.updateControls()
                }
        }
    }

    private func decode(_ url: URL, limit: Int?, completion: @escaping (Result<LoadedImage, Error>) -> Void) {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = autoreleasepool { Result { try ImageLoader.load(url: url, maxPixelSize: limit) } }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { completion(result) }
        }
        decoding.addOperation(operation)
    }

    private var maximumDecodeDimension: Int {
        let size = canvas.pixelSize
        let area = size.width * size.height
        guard area.isFinite, area > 0 else { return 4096 }
        // Keep a single current-image upgrade, with enough resolution for common
        // 45/61/100 MP cameras at exact 100%. Extreme files retain a visible cap.
        return max(1, Int(min(32768, max(size.width, size.height) * min(1, sqrt(128_000_000 / area)))))
    }

    func fitImage() {
        fitted = true
        canvas.pan = .zero
        canvas.scale = ZoomMath.fit(image: canvas.pixelSize, viewport: canvas.bounds.size, backingScale: canvas.backingScale)
        canvas.needsDisplay = true
        updateControls()
        upgradeIfNeeded()
    }
    func zoomIn() { applyZoom(canvas.scale * 1.2) }
    func zoomOut() { applyZoom(canvas.scale / 1.2) }
    func focusCanvas() { view.window?.makeFirstResponder(canvas) }

    private func applyZoom(_ value: Double, anchor: NSPoint? = nil) {
        guard canvas.image != nil, value.isFinite, value > 0 else { return }
        fitted = false
        let previous = canvas.scale
        let next = min(3, max(Double.leastNormalMagnitude, value))
        let point = anchor ?? NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        let ratio = CGFloat(next / previous)
        canvas.pan = CGPoint(x: (canvas.pan.x + canvas.bounds.midX - point.x) * ratio + point.x - canvas.bounds.midX,
                             y: (canvas.pan.y + canvas.bounds.midY - point.y) * ratio + point.y - canvas.bounds.midY)
        canvas.scale = next
        canvas.constrainPan()
        canvas.needsDisplay = true
        updateControls()
        upgradeIfNeeded()
    }

    private var fileSizeSuffix: String {
        guard let file = displayedFile else { return "" }
        return " · " + ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
    }

    private func updateControls() {
        let fit = ZoomMath.fit(image: canvas.pixelSize, viewport: canvas.bounds.size, backingScale: canvas.backingScale)
        slider.minValue = log(max(Double.leastNormalMagnitude, min(0.001, fit, canvas.scale)))
        slider.doubleValue = log(max(Double.leastNormalMagnitude, canvas.scale))
        percent.stringValue = ZoomMath.percentText(canvas.scale)
        if percentEditStartingText != nil { percentEditStartingText = percent.stringValue }
        slider.isEnabled = canvas.image != nil
        percent.isEnabled = canvas.image != nil
        infoButton?.isEnabled = canvas.image != nil
        if canvas.image != nil, let url = imageURL {
            details.stringValue = "\(url.lastPathComponent) · \(Int(canvas.pixelSize.width)) × \(Int(canvas.pixelSize.height))\(fileSizeSuffix)"
            details.toolTip = details.stringValue
        }
    }

    private func upgradeIfNeeded() {
        guard let url = imageURL, canvas.image != nil, !upgradePending else { return }
        let original = max(canvas.pixelSize.width, canvas.pixelSize.height)
        let requested = original * min(1, canvas.scale)
        let wanted = Int(min(CGFloat(maximumDecodeDimension), ceil(requested)))
        if requested > CGFloat(maximumDecodeDimension), let url = imageURL {
            details.stringValue = L10n.format("%@ · %ld × %ld%@ · Large image resolution limited", url.lastPathComponent, Int(canvas.pixelSize.width), Int(canvas.pixelSize.height), fileSizeSuffix)
            details.toolTip = L10n.text("To limit memory use for large photos, previews are limited to 128 megapixels or 32,768 pixels on the longest edge. Zoom is based on the original dimensions.")
        }
        guard wanted > decodedLimit + 32 else { return }
        let token = generation
        upgradePending = true
        decode(url, limit: wanted) { [weak self] result in
                guard let self, self.generation == token else { return }
                self.upgradePending = false
                if case .success(let result) = result {
                    self.canvas.image = result.image
                    self.decodedLimit = max(result.image.width, result.image.height)
                    self.canvas.needsDisplay = true
                    self.upgradeIfNeeded()
                }
        }
    }

    func setFullscreen(_ flag: Bool) {
        loadViewIfNeeded()
        fullscreen = flag
        // In fullscreen the canvas owns the complete viewport. The status bar is
        // only an overlay, so pointer movement never changes Fit or image geometry.
        if flag {
            canvasAboveStatus.isActive = false
            canvasToBottom.isActive = true
        } else {
            canvasToBottom.isActive = false
            canvasAboveStatus.isActive = true
        }
        pointerNearBottom = false
        refreshStatusVisibility()
        closeButton.isHidden = !flag
        view.layoutSubtreeIfNeeded()
    }

    /// Point is in the root view's coordinates; nil means the pointer left it.
    func updateFullscreenHover(at point: NSPoint?) {
        guard isViewLoaded else { return }
        if let point {
            let bottomHeight = max(44, status.frame.height)
            pointerNearBottom = view.bounds.contains(point) && point.y <= view.bounds.minY + bottomHeight
        } else {
            pointerNearBottom = false
        }
        refreshStatusVisibility()
    }

    private func refreshStatusVisibility() {
        let interacting = percentEditStartingText != nil || percent.currentEditor() != nil || metadataPopover?.isShown == true
        status.isHidden = fullscreen && !pointerNearBottom && !interacting
    }

    @objc private func sliderChanged() { applyZoom(exp(slider.doubleValue)); focusCanvas() }
    @objc private func percentChanged() {
        commitEditedPercent(beepOnFailure: true)
        focusCanvas()
    }
    func controlTextDidBeginEditing(_ obj: Notification) {
        percentEditStartingText = percent.stringValue
        refreshStatusVisibility()
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        commitEditedPercent(beepOnFailure: false)
        percentEditStartingText = nil
        refreshStatusVisibility()
        DispatchQueue.main.async { [weak self] in self?.refreshStatusVisibility() }
    }
    private func commitEditedPercent(beepOnFailure: Bool) {
        // Display rounding (including "<0.01") is not a user request to change
        // the exact scale. Focus/blur and Return without edits preserve Fit.
        let previous = percentEditStartingText ?? ZoomMath.percentText(canvas.scale)
        guard percent.stringValue != previous else { return }
        if let scale = ZoomMath.parsePercent(percent.stringValue) {
            applyZoom(scale)
        } else {
            if beepOnFailure { NSSound.beep() }
            updateControls()
        }
        if percentEditStartingText != nil { percentEditStartingText = percent.stringValue }
    }
    @objc private func fitAction() { fitImage(); focusCanvas() }
    @objc private func infoAction() { toggleInfo() }
    @objc private func modeAction() { model.slideMode.toggle(); focusCanvas() }
    @objc private func fullscreenAction() { model.toggleFullscreen?() }

    func toggleInfo() {
        if let popover = metadataPopover, popover.isShown { popover.close(); return }
        guard let url = imageURL else { return }
        let controller = MetadataInfoController()
        controller.loadViewIfNeeded()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 620, height: 480)
        metadataPopover = popover
        status.isHidden = false
        popover.show(relativeTo: infoButton.bounds, of: infoButton, preferredEdge: .maxY)
        refreshStatusVisibility()
        DispatchQueue.global(qos: .userInitiated).async { [weak controller] in
            let result = Result { try MetadataService.entries(at: url) }
            DispatchQueue.main.async { [weak controller] in
                switch result {
                case .success(let entries): controller?.setEntries(entries)
                case .failure(let error): controller?.showError(error.localizedDescription)
                }
            }
        }
    }

    func popoverDidClose(_ notification: Notification) { refreshStatusVisibility() }

    var canCopyImage: Bool { isViewLoaded && canvas.image != nil && imageURL != nil }

    func copyImage(to pasteboard: NSPasteboard = .general) {
        guard canCopyImage, let url = imageURL else { return }
        let token = generation
        // Decode the oriented original, independent of the current zoom/preview resolution.
        decode(url, limit: nil) { [weak self] result in
            guard let self, self.generation == token else { return }
            switch result {
            case .success(let loaded):
                let image = NSImage(cgImage: loaded.image, size: NSSize(width: loaded.image.width, height: loaded.image.height))
                pasteboard.clearContents()
                if !pasteboard.writeObjects([image]) { NSSound.beep() }
            case .failure(let error): self.model.errorMessage = error.localizedDescription
            }
        }
    }

    func copyFilePath(to pasteboard: NSPasteboard = .general) {
        guard canCopyImage, let url = imageURL else { return }
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    func imageContextMenu() -> NSMenu? {
        guard canCopyImage, let url = imageURL else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: L10n.text(title), action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        let copy = add("Copy Image", #selector(copyImageAction))
        copy.keyEquivalent = "c"
        copy.keyEquivalentModifierMask = .command
        _ = add("Copy File Path", #selector(copyPathAction))
        let open = add("Open With", #selector(chooseApplication))
        let apps = NSMenu()
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: url).filter {
            Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted {
            FileManager.default.displayName(atPath: $0.path).localizedStandardCompare(FileManager.default.displayName(atPath: $1.path)) == .orderedAscending
        }
        for app in candidates {
            let item = NSMenuItem(title: FileManager.default.displayName(atPath: app.path), action: #selector(openInApplication(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            apps.addItem(item)
        }
        if !candidates.isEmpty { apps.addItem(.separator()) }
        let other = NSMenuItem(title: L10n.text("Choose Application…"), action: #selector(chooseApplication), keyEquivalent: "")
        other.target = self
        apps.addItem(other)
        open.submenu = apps
        return menu
    }

    @objc private func copyImageAction() { copyImage() }
    @objc private func copyPathAction() { copyFilePath() }
    @objc private func openInApplication(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL, let url = imageURL else { return }
        open(url, in: app)
    }
    @objc private func chooseApplication() {
        guard let url = imageURL, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let app = panel.url else { return }
            self?.open(url, in: app)
        }
    }
    private func open(_ url: URL, in app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.model.errorMessage = error.localizedDescription } }
        }
    }

    func printImage() {
        guard let url = imageURL, let window = view.window else { return }
        let token = generation
        decode(url, limit: nil) { [weak self] result in
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let image):
                    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.horizontalPagination = .fit
                    info.verticalPagination = .fit
                    info.isHorizontallyCentered = true
                    info.isVerticallyCentered = true
                    let page = PrintedPhotoView(image: image.image, printInfo: info)
                    let operation = NSPrintOperation(view: page, printInfo: info)
                    operation.jobTitle = url.lastPathComponent
                    operation.showsPrintPanel = true
                    operation.showsProgressPanel = true
                    operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                case .failure(let error): NSAlert(error: error).beginSheetModal(for: window)
                }
        }
    }
}

@MainActor
private final class ViewerTrackingView: NSView {
    var onPointerChange: ((NSPoint?) -> Void)?
    private var pointerTracking: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        pointerTracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) { onPointerChange?(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { onPointerChange?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onPointerChange?(nil) }
}

@MainActor
final class ImageCanvasView: NSView {
    var image: CGImage? {
        didSet {
            previousButton.isHidden = image == nil
            nextButton.isHidden = image == nil
        }
    }
    var pixelSize: CGSize = .zero
    var scale: Double = 1
    var pan: CGPoint = .zero
    var selectionCount = 0
    var message = L10n.text("Open a folder or photo")
    var contextMenuProvider: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        guard image != nil else { return nil }
        window?.makeFirstResponder(self)
        return contextMenuProvider?()
    }
    var onNavigate: ((Int) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onEnter: (() -> Void)?
    var onZoom: ((Double, NSPoint?) -> Void)?
    var onViewportChange: (() -> Void)?
    private var dragStart: NSPoint?
    private var panStart: CGPoint = .zero
    private let previousButton = NSButton(title: "‹", target: nil, action: nil)
    private let nextButton = NSButton(title: "›", target: nil, action: nil)
    var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Never stretch a cached canvas bitmap while its layer is being resized.
        layerContentsRedrawPolicy = .duringViewResize
        layerContentsPlacement = .center
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.text("Photo viewer. Use arrow keys to navigate, and Command plus or minus to zoom."))
        for (button, label, action) in [(previousButton, L10n.text("Previous Photo"), #selector(previousPhoto)), (nextButton, L10n.text("Next Photo"), #selector(nextPhoto))] {
            button.target = self
            button.action = action
            button.isBordered = false
            button.font = .systemFont(ofSize: 32, weight: .light)
            button.contentTintColor = NSColor.white.withAlphaComponent(0.8)
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
            button.layer?.cornerRadius = 8
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 44),
                button.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
        nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { onViewportChange?() }
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let changed = frame.origin != newOrigin
        super.setFrameOrigin(newOrigin)
        if changed { needsDisplay = true }
    }
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        needsDisplay = true
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); onViewportChange?() }

    var imageRect: NSRect {
        let size = NSSize(width: pixelSize.width * scale / backingScale, height: pixelSize.height * scale / backingScale)
        let rect = NSRect(x: bounds.midX - size.width / 2 + pan.x, y: bounds.midY - size.height / 2 + pan.y, width: size.width, height: size.height)
        // Centering odd-sized images (or fractional split panes/pan) can land
        // between device pixels. Snap only the origin, preserving the zoom size.
        var pixels = convertToBacking(rect)
        pixels.origin.x = pixels.origin.x.rounded()
        pixels.origin.y = pixels.origin.y.rounded()
        return convertFromBacking(pixels)
    }
    func constrainPan() {
        let rect = imageRect
        let horizontal = max(0, (rect.width - bounds.width) / 2)
        let vertical = max(0, (rect.height - bounds.height) / 2)
        pan.x = min(horizontal, max(-horizontal, pan.x))
        pan.y = min(vertical, max(-vertical, pan.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (message as NSString).draw(in: NSRect(x: 30, y: bounds.midY - 44, width: max(0, bounds.width - 60), height: 88), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
            return
        }
        let rect = imageRect
        if selectionCount > 1 {
            for offset in [12.0, 6.0] {
                let sheet = rect.offsetBy(dx: offset, dy: -offset)
                NSColor(calibratedWhite: offset == 12 ? 0.23 : 0.34, alpha: 1).setFill()
                sheet.fill()
            }
        }
        context.interpolationQuality = scale >= 1 ? .none : .high
        context.draw(image, in: rect)
        if selectionCount > 1 {
            let badge = L10n.format("%ld selected", selectionCount) as NSString
            badge.draw(at: NSPoint(x: 14, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.5)])
        }
    }
    @objc private func previousPhoto() { window?.makeFirstResponder(self); onNavigate?(-1) }
    @objc private func nextPhoto() { window?.makeFirstResponder(self); onNavigate?(1) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 { onDoubleClick?(); return }
        dragStart = point
        panStart = pan
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        pan = CGPoint(x: panStart.x + point.x - start.x, y: panStart.y + point.y - start.y)
        constrainPan()
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            guard window?.firstResponder === self else { return }
            onZoom?(exp(Double(event.scrollingDeltaY) * 0.015), convert(event.locationInWindow, from: nil))
        } else {
            pan.x += event.scrollingDeltaX
            pan.y -= event.scrollingDeltaY
            constrainPan()
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) { onZoom?(max(0.01, 1 + Double(event.magnification)), convert(event.locationInWindow, from: nil)) }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers {
            if key == "+" || key == "=" { onZoom?(1.2, nil); return }
            if key == "-" { onZoom?(1 / 1.2, nil); return }
        }
        switch event.keyCode {
        case 123, 126, 116: onNavigate?(-1)
        case 124, 125, 121: onNavigate?(1)
        case 36, 76: onEnter?()
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
final class PrintedPhotoView: NSView {
    private let image: CGImage
    private let printInfo: NSPrintInfo
    init(image: CGImage, printInfo: NSPrintInfo) {
        self.image = image
        self.printInfo = printInfo
        super.init(frame: .zero)
        updatePrintableSize()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updatePrintableSize() {
        // NSPrintOperation updates this same info after paper/orientation changes.
        // Re-paginate from the final printable area instead of the initial dialog.
        let info = NSPrintOperation.current?.printInfo ?? printInfo
        let width = max(1, info.paperSize.width - info.leftMargin - info.rightMargin)
        let height = max(1, info.paperSize.height - info.topMargin - info.bottomMargin)
        setFrameSize(NSSize(width: width, height: height))
    }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        updatePrintableSize()
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }
    override func rectForPage(_ page: Int) -> NSRect {
        updatePrintableSize()
        return bounds
    }
    override func draw(_ dirtyRect: NSRect) {
        let factor = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = NSSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        NSGraphicsContext.current?.cgContext.draw(image, in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }
}
