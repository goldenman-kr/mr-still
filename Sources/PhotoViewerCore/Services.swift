import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum PhotoServiceError: LocalizedError {
    case unreadableImage(URL)
    case invalidImageDimensions(URL)
    case invalidPixelLimit

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return "이미지를 읽을 수 없습니다: \(url.lastPathComponent)"
        case .invalidImageDimensions(let url): return "이미지 크기를 확인할 수 없습니다: \(url.lastPathComponent)"
        case .invalidPixelLimit: return "이미지 표시 크기는 0보다 커야 합니다."
        }
    }
}

public enum DirectoryService {
    private static let extensions: Set<String> = ["jpg", "jpeg", "jpe", "png", "heic", "heif", "hif", "tif", "tiff", "bmp", "gif"]
    public static let supportedTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff, .bmp, .gif]

    /// This deliberately checks the declared format, not the file contents: listing a large
    /// folder must not decode every photo. ImageLoader validates actual image data on demand.
    public static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if extensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    public static func contents(of directory: URL) throws -> [ImageFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            let directory = values.isDirectory == true && values.isPackage != true
            guard directory || (values.isRegularFile == true && isSupported(url)) else { return nil }
            return ImageFile(url: url, size: directory ? 0 : Int64(values.fileSize ?? 0),
                             modified: values.contentModificationDate ?? .distantPast, isDirectory: directory)
        }
    }

    public static func subdirectories(of directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).filter { url in
            let values = try url.resourceValues(forKeys: keys)
            return values.isDirectory == true && values.isPackage != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

public struct LoadedImage {
    public let image: CGImage
    /// Oriented original dimensions, independent of the decoded preview dimensions.
    public let pixelSize: CGSize

    public init(image: CGImage, pixelSize: CGSize) {
        self.image = image
        self.pixelSize = pixelSize
    }
}

public enum ImageLoader {
    /// Pass nil for original resolution (for example, printing); orientation is still applied.
    public static func load(url: URL, maxPixelSize: Int?) throws -> LoadedImage {
        if let maxPixelSize, maxPixelSize <= 0 { throw PhotoServiceError.invalidPixelLimit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw PhotoServiceError.unreadableImage(url)
        }
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max) else { throw PhotoServiceError.invalidImageDimensions(url) }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let pixelSize = CGSize(width: rotated ? height : width, height: rotated ? width : height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize ?? Int(max(width, height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoServiceError.unreadableImage(url)
        }
        return LoadedImage(image: image, pixelSize: pixelSize)
    }
}

public final class ThumbnailService {
    public static let shared = ThumbnailService()
    private let cache = NSCache<NSString, NSImage>()
    private let coordination = DispatchQueue(label: "PhotoViewer.thumbnail.coordination", qos: .userInitiated)
    private let decoding: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PhotoViewer.thumbnail.decoding"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private var pending: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 600
    }

    public func image(for url: URL, pixelSize: Int, completion: @escaping (NSImage?) -> Void) {
        coordination.async { [self] in
            let size = max(1, min(2048, pixelSize))
            // URL resource values can be cached on a URL retained by the browser. Read
            // fresh attributes so an externally replaced image cannot reuse stale pixels.
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let key = "\(url.standardizedFileURL.path)|\(size)|\(modified)|\(bytes)"
            if let cached = cache.object(forKey: key as NSString) {
                DispatchQueue.main.async { completion(cached) }
                return
            }
            if pending[key] != nil {
                pending[key]?.append(completion)
                return
            }
            pending[key] = [completion]
            decoding.addOperation { [self] in
                let image: NSImage? = autoreleasepool {
                    guard let loaded = try? ImageLoader.load(url: url, maxPixelSize: size) else { return nil }
                    let image = NSImage(cgImage: loaded.image, size: NSSize(width: loaded.image.width, height: loaded.image.height))
                    cache.setObject(image, forKey: key as NSString, cost: loaded.image.bytesPerRow * loaded.image.height)
                    return image
                }
                coordination.async { [self] in
                    let callbacks = pending.removeValue(forKey: key) ?? []
                    DispatchQueue.main.async { callbacks.forEach { $0(image) } }
                }
            }
        }
    }
}

public struct MetadataEntry: Sendable {
    public let key: String
    public let value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

public enum MetadataService {
    public static func entries(at url: URL) throws -> [MetadataEntry] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            throw PhotoServiceError.unreadableImage(url)
        }
        var result = [MetadataEntry(key: "File / Name", value: url.lastPathComponent), MetadataEntry(key: "File / Path", value: url.path)]
        if let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]) {
            if let bytes = attributes.fileSize { result.append(MetadataEntry(key: "File / Bytes", value: String(bytes))) }
            let formatter = ISO8601DateFormatter()
            if let date = attributes.creationDate { result.append(MetadataEntry(key: "File / Created", value: formatter.string(from: date))) }
            if let date = attributes.contentModificationDate { result.append(MetadataEntry(key: "File / Modified", value: formatter.string(from: date))) }
        }
        if let type = CGImageSourceGetType(source) { result.append(MetadataEntry(key: "File / Type", value: type as String)) }
        result.append(MetadataEntry(key: "File / Frames", value: String(CGImageSourceGetCount(source))))
        if let container = CGImageSourceCopyProperties(source, nil) { flatten(container, prefix: "Container", into: &result) }
        flatten(imageProperties, prefix: "Image", into: &result)
        return result
    }

    private static func flatten(_ value: Any, prefix: String, into entries: inout [MetadataEntry]) {
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty { entries.append(MetadataEntry(key: prefix, value: "{}")) }
            for key in dictionary.keys.sorted() {
                flatten(dictionary[key]!, prefix: "\(prefix) / \(key)", into: &entries)
            }
        } else if let array = value as? [Any] {
            if array.isEmpty { entries.append(MetadataEntry(key: prefix, value: "[]")) }
            for (index, item) in array.enumerated() { flatten(item, prefix: "\(prefix) [\(index)]", into: &entries) }
        } else if let data = value as? Data {
            entries.append(MetadataEntry(key: prefix, value: data.base64EncodedString()))
        } else {
            entries.append(MetadataEntry(key: prefix, value: String(describing: value)))
        }
    }
}

public enum CopyConflictPolicy: Sendable { case keepBoth, skip }

public struct FileOperationResult: Sendable {
    public var succeeded: [URL]
    public var failures: [String]
    public init(succeeded: [URL] = [], failures: [String] = []) {
        self.succeeded = succeeded
        self.failures = failures
    }
}

public enum FileOperations {
    /// Succeeded URLs are destinations for copy and original URLs for trash.
    public static func copy(_ urls: [URL], to directory: URL, conflict: CopyConflictPolicy) -> FileOperationResult {
        let manager = FileManager.default
        var result = FileOperationResult()
        var isDirectory: ObjCBool = false
        guard directory.isFileURL, manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.failures = urls.map { "\($0.lastPathComponent): 대상 폴더가 없습니다." }
            return result
        }
        for source in urls {
            var suffix = 1
            while true {
                let destination = destination(for: source, directory: directory, suffix: suffix)
                do {
                    // copyItem itself refuses existing destinations, including a file created
                    // between checking a name and copying. Never remove a destination to retry.
                    try manager.copyItem(at: source, to: destination)
                    result.succeeded.append(destination)
                    break
                } catch {
                    let nsError = error as NSError
                    let exists = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteFileExistsError
                    if exists && conflict == .keepBoth {
                        suffix += 1
                        continue
                    }
                    let reason = exists ? "동일한 이름이 있어 건너뛰었습니다." : error.localizedDescription
                    result.failures.append("\(source.lastPathComponent): \(reason)")
                    break
                }
            }
        }
        return result
    }

    public static func trash(_ urls: [URL]) -> FileOperationResult {
        var result = FileOperationResult()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.succeeded.append(url)
            } catch { result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }

    private static func destination(for source: URL, directory: URL, suffix: Int) -> URL {
        guard suffix > 1 else { return directory.appendingPathComponent(source.lastPathComponent) }
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        let name = "\(stem) \(suffix)" + (ext.isEmpty ? "" : ".\(ext)")
        return directory.appendingPathComponent(name)
    }
}
