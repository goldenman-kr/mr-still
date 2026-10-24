import AppKit
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

/// Clickable, read-only folder breadcrumbs.
@MainActor
final class FolderPathBar: NSView {
    private let breadcrumbs = NSPathControl()
    private(set) var folderURL: URL?
    let homeURL: URL
    var navigate: ((URL) -> Void)?

    init(homeURL: URL) {
        self.homeURL = homeURL.standardizedFileURL
        super.init(frame: .zero)
        breadcrumbs.pathStyle = .standard
        breadcrumbs.backgroundColor = .clear
        breadcrumbs.isEditable = false
        breadcrumbs.font = .systemFont(ofSize: 11)
        breadcrumbs.controlSize = .small
        breadcrumbs.placeholderString = L10n.text("Open a folder")
        breadcrumbs.target = self
        breadcrumbs.action = #selector(clickedBreadcrumb(_:))
        breadcrumbs.setAccessibilityLabel(L10n.text("Current folder path"))
        breadcrumbs.translatesAutoresizingMaskIntoConstraints = false
        addSubview(breadcrumbs)
        NSLayoutConstraint.activate([
            breadcrumbs.leadingAnchor.constraint(equalTo: leadingAnchor),
            breadcrumbs.trailingAnchor.constraint(equalTo: trailingAnchor),
            breadcrumbs.centerYAnchor.constraint(equalTo: centerYAnchor),
            breadcrumbs.heightAnchor.constraint(equalToConstant: 20)
        ])
        update(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ url: URL?) {
        folderURL = url?.standardizedFileURL
        toolTip = folderURL?.path
        breadcrumbs.url = folderURL
        let nativeItems = breadcrumbs.pathItems
        breadcrumbs.pathItems = Self.components(for: folderURL, home: homeURL).compactMap { component in
            guard let item = nativeItems.first(where: { $0.url?.path == component.url.path }) else { return nil }
            item.title = component.title
            item.image = nil
            return item
        }
    }

    static func components(for folder: URL?, home: URL) -> [(title: String, url: URL)] {
        guard let selected = folder else { return [] }
        let folder = selected.standardizedFileURL
        let home = home.standardizedFileURL
        let withinHome = folder.pathComponents.starts(with: home.pathComponents)
        var url = withinHome ? home : URL(fileURLWithPath: "/", isDirectory: true)
        var result = [(withinHome ? L10n.text("Home") : "/", url)]
        for name in folder.pathComponents.dropFirst(withinHome ? home.pathComponents.count : 1) {
            url.appendPathComponent(name, isDirectory: true)
            result.append((name, url))
        }
        return result
    }

    @objc private func clickedBreadcrumb(_ sender: NSPathControl) {
        guard let url = sender.clickedPathItem?.url, url.path != folderURL?.path else { return }
        navigate?(url)
    }
}
