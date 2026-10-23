import XCTest
import AppKit
@testable import PhotoViewer
import PhotoViewerCore

final class ThumbnailSpacingTests: XCTestCase {
    @MainActor
    func testThumbnailGapsRemainEqualAcrossColumnCountsAndResizing() async throws {
        _ = NSApplication.shared
        let suite = "PhotoViewer-Spacing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(defaults: defaults)
        model.files = (0..<13).map {
            ImageFile(url: URL(fileURLWithPath: "/tmp/Folder\($0)", isDirectory: true), size: 0, modified: .distantPast, isDirectory: true)
        }
        let controller = FileBrowserController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        defer { window.close() }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSCollectionView }.first)
        for mode: FileViewMode in [.large, .small, .large] {
            model.viewMode = mode
            try await Task.sleep(nanoseconds: 20_000_000)
            for width: CGFloat in [300, 400, 420, 550, 565, 420, 300] {
                window.setContentSize(NSSize(width: width, height: 500))
                controller.view.layoutSubtreeIfNeeded()
                collection.layoutSubtreeIfNeeded()
                let layout = try XCTUnwrap(collection.collectionViewLayout)
                let frames = try (0..<13).map { index in
                    try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
                }
                let firstRow = frames.filter { abs($0.minY - frames[0].minY) < 1 }.sorted { $0.minX < $1.minX }
                XCTAssertGreaterThanOrEqual(firstRow.count, 2)
                let gap = firstRow[0].minX
                XCTAssertEqual(collection.bounds.width - firstRow.last!.maxX, gap, accuracy: 1, "Right edge at \(mode) \(width)")
                for pair in zip(firstRow, firstRow.dropFirst()) {
                    XCTAssertEqual(pair.1.minX - pair.0.maxX, gap, accuracy: 1, "Inner gap at \(mode) \(width)")
                }
                // A partial final row keeps the same columns instead of stretching apart.
                for (index, frame) in frames.enumerated() {
                    XCTAssertEqual(frame.minX, firstRow[index % firstRow.count].minX, accuracy: 1)
                    XCTAssertLessThanOrEqual(frame.maxX, collection.bounds.width + 1)
                }
            }
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
}
