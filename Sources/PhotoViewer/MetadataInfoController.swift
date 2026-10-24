import AppKit
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

/// Native rows retain every metadata value; the lower inspector shows the full
/// selected value without truncation, including long EXIF comments and paths.
@MainActor
final class MetadataInfoController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct Row {
        let group: String
        let item: String
        let value: String
        init(entry: MetadataEntry) {
            let components = entry.key.components(separatedBy: " / ")
            group = components.count > 1 ? components.dropLast().joined(separator: " / ") : L10n.text("General")
            item = components.last ?? entry.key
            value = entry.value
        }
    }
    private(set) var rows: [Row] = []
    let table = NSTableView()
    let valueText = NSTextView()
    private let summary = NSTextField(labelWithString: L10n.text("Loading metadata…"))
    private let valueTitle = NSTextField(labelWithString: L10n.text("Select an item to view its full value."))
    private let copyButton = NSButton(title: L10n.text("Copy Value"), target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
        view.appearance = NSAppearance(named: .darkAqua)
        summary.font = .systemFont(ofSize: 12, weight: .medium)
        summary.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 25
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsEmptySelection = true
        table.setAccessibilityLabel(L10n.text("Image metadata"))
        for (identifier, title, width) in [("group", L10n.text("Group"), 150.0), ("item", L10n.text("Item"), 150.0), ("value", L10n.text("Value"), 280.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 80
            table.addTableColumn(column)
        }
        scroll.documentView = table
        let valueScroll = NSScrollView()
        valueScroll.hasVerticalScroller = true
        valueScroll.borderType = .bezelBorder
        valueText.isEditable = false
        valueText.isSelectable = true
        valueText.font = .systemFont(ofSize: 12)
        valueText.textColor = .labelColor
        valueText.backgroundColor = .textBackgroundColor
        valueText.textContainerInset = NSSize(width: 8, height: 8)
        valueText.isVerticallyResizable = true
        valueText.isHorizontallyResizable = false
        valueText.autoresizingMask = .width
        valueText.textContainer?.widthTracksTextView = true
        valueText.setAccessibilityLabel(L10n.text("Full value of selected metadata"))
        valueScroll.documentView = valueText
        valueTitle.font = .systemFont(ofSize: 11, weight: .medium)
        valueTitle.lineBreakMode = .byTruncatingMiddle
        copyButton.target = self
        copyButton.action = #selector(copySelectedValue)
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false
        for child in [summary, scroll, valueTitle, copyButton, valueScroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            summary.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: valueTitle.topAnchor, constant: -12),
            valueTitle.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            valueTitle.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),
            valueTitle.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            copyButton.bottomAnchor.constraint(equalTo: valueScroll.topAnchor, constant: -8),
            valueScroll.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            valueScroll.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            valueScroll.heightAnchor.constraint(equalToConstant: 100),
            valueScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    func setEntries(_ entries: [MetadataEntry]) {
        loadViewIfNeeded()
        rows = entries.map(Row.init)
        summary.stringValue = entries.isEmpty ? L10n.text("No metadata available.") : L10n.format("Image Info · %ld items", rows.count)
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateSelectedValue()
    }

    func showError(_ message: String) {
        setEntries([])
        summary.stringValue = L10n.text("Could not read image info.")
        valueText.string = message
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        let entry = rows[row]
        cell.stringValue = identifier.rawValue == "group" ? entry.group : identifier.rawValue == "item" ? entry.item : entry.value
        cell.toolTip = cell.stringValue
        cell.font = .systemFont(ofSize: 12)
        cell.textColor = identifier.rawValue == "group" ? .secondaryLabelColor : .labelColor
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelectedValue() }
    private func updateSelectedValue() {
        let index = table.selectedRow
        copyButton.isEnabled = rows.indices.contains(index)
        guard rows.indices.contains(index) else {
            valueTitle.stringValue = L10n.text("Select an item to view its full value.")
            valueText.string = ""
            return
        }
        let row = rows[index]
        valueTitle.stringValue = "\(row.group) / \(row.item)"
        valueTitle.toolTip = valueTitle.stringValue
        valueText.string = row.value
        valueText.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    @objc private func copySelectedValue() {
        guard rows.indices.contains(table.selectedRow) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows[table.selectedRow].value, forType: .string)
    }
}
