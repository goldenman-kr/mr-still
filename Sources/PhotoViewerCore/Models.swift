import Foundation
import CoreGraphics

public struct ImageFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let size: Int64
    public let modified: Date
    public let isDirectory: Bool
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public init(url: URL, size: Int64, modified: Date, isDirectory: Bool = false) {
        self.url = url.standardizedFileURL; self.size = size; self.modified = modified
        self.isDirectory = isDirectory
    }
}

public enum FileSortKey: String, CaseIterable, Sendable { case name, date, size }
public enum FileViewMode: String, CaseIterable, Sendable { case small, large, list }

public enum FileOrdering {
    public static func sorted(_ files: [ImageFile], by key: FileSortKey, ascending: Bool) -> [ImageFile] {
        files.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            var result: ComparisonResult
            switch key {
            case .name: result = a.name.localizedStandardCompare(b.name)
            case .date: result = a.modified == b.modified ? .orderedSame : (a.modified < b.modified ? .orderedAscending : .orderedDescending)
            case .size: result = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            }
            if result == .orderedSame { result = a.name.localizedStandardCompare(b.name) }
            if result == .orderedSame { result = a.url.path.compare(b.url.path) }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

public enum ZoomMath {
    public static func fit(image: CGSize, viewport: CGSize, backingScale: CGFloat) -> Double {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(1, Double(viewport.width * backingScale / image.width), Double(viewport.height * backingScale / image.height))
    }
    public static func parsePercent(_ input: String) -> Double? {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("%") { cleaned.removeLast(); cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleaned.contains("%") else { return nil }
        guard let value = Double(cleaned), value.isFinite, value > 0, value <= 300 else { return nil }
        let scale = value / 100
        return scale > 0 ? scale : nil
    }
    public static func percentText(_ scale: Double) -> String {
        let value = scale * 100
        if value > 0 && value < 0.01 { return "<0.01" }
        return String(format: "%.2f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

public enum LayoutMath {
    public static let leftMinimum: CGFloat = 280
    public static let rightMinimum: CGFloat = 400
    public static func leftWidth(total: CGFloat, previous: CGFloat, divider: CGFloat = 1) -> CGFloat {
        max(leftMinimum, min(previous, total - divider - rightMinimum))
    }
}
