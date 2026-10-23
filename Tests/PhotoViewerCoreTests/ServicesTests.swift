import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoViewerCore

final class ServicesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoViewer-ServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testDirectoryEnumerationSkipsHiddenNonImagesAndDoesNotRecurse() throws {
        _ = try writeImage("사진 2.PNG")
        _ = try writeImage(".hidden.png")
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        for name in ["Folder10", "Folder2", ".private", "fake.jpg"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        _ = try writeImage("Folder2/nested.png")
        let files = try DirectoryService.contents(of: root)
        XCTAssertEqual(Set(files.filter(\.isDirectory).map(\.name)), ["fake.jpg", "Folder2", "Folder10"])
        let images = files.filter { !$0.isDirectory }
        XCTAssertEqual(images.map(\.name), ["사진 2.PNG"])
        XCTAssertGreaterThan(images[0].size, 0)
        XCTAssertGreaterThan(images[0].modified, .distantPast)
        XCTAssertEqual(try DirectoryService.subdirectories(of: root).map(\.lastPathComponent), ["fake.jpg", "Folder2", "Folder10"])
        XCTAssertTrue(DirectoryService.isSupported(root.appendingPathComponent("photo.HEIF")))
        XCTAssertFalse(DirectoryService.isSupported(root.appendingPathComponent("photo.txt")))
        XCTAssertThrowsError(try DirectoryService.contents(of: root.appendingPathComponent("missing")))
    }

    func testLoaderDownsamplesWithoutChangingOriginalDimensions() throws {
        let url = try writeImage("image.png")
        let loaded = try ImageLoader.load(url: url, maxPixelSize: 20)
        XCTAssertEqual(loaded.pixelSize, CGSize(width: 80, height: 40))
        XCTAssertEqual(loaded.image.width, 20)
        XCTAssertEqual(loaded.image.height, 10)
        let full = try ImageLoader.load(url: url, maxPixelSize: 500)
        XCTAssertEqual(full.image.width, 80)
        XCTAssertEqual(full.image.height, 40)
    }

    func testOrientationIsAppliedToPreviewAndOriginalDimensions() throws {
        let url = try writeImage("rotated.jpg", type: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        let loaded = try ImageLoader.load(url: url, maxPixelSize: 20)
        XCTAssertEqual(loaded.pixelSize, CGSize(width: 40, height: 80))
        XCTAssertEqual(loaded.image.width, 10)
        XCTAssertEqual(loaded.image.height, 20)
        let original = try ImageLoader.load(url: url, maxPixelSize: nil)
        XCTAssertEqual(original.image.width, 40)
        XCTAssertEqual(original.image.height, 80)
    }

    func testSupportedWritableFormatsDecode() throws {
        let formats: [(String, UTType)] = [("jpg", .jpeg), ("png", .png), ("tiff", .tiff), ("bmp", .bmp), ("gif", .gif)]
        for (ext, type) in formats {
            let url = try writeImage("sample.\(ext)", type: type)
            XCTAssertTrue(DirectoryService.isSupported(url))
            XCTAssertEqual(try ImageLoader.load(url: url, maxPixelSize: 80).pixelSize, CGSize(width: 80, height: 40))
        }
    }

    func testHEICAndHEIFDecodeWhenFixtureEncoderIsAvailable() throws {
        let url: URL
        do { url = try writeImage("sample.heic", type: .heic) }
        catch FixtureError.encodingFailed {
            throw XCTSkip("The HEIC fixture encoder is unavailable in this execution environment (for example, sandbox restrictions on VideoToolbox).")
        }
        XCTAssertEqual(try ImageLoader.load(url: url, maxPixelSize: 80).pixelSize, CGSize(width: 80, height: 40))
        let heif = root.appendingPathComponent("sample.heif")
        try FileManager.default.copyItem(at: url, to: heif)
        XCTAssertTrue(DirectoryService.isSupported(heif))
        XCTAssertEqual(try ImageLoader.load(url: heif, maxPixelSize: 80).pixelSize, CGSize(width: 80, height: 40))
    }

    func testCorruptImageAndInvalidDecodeSizeFail() throws {
        let url = root.appendingPathComponent("corrupt.jpg")
        try Data("not an image".utf8).write(to: url)
        XCTAssertThrowsError(try ImageLoader.load(url: url, maxPixelSize: 20))
        XCTAssertThrowsError(try MetadataService.entries(at: url))
        let valid = try writeImage("image.png")
        XCTAssertThrowsError(try ImageLoader.load(url: valid, maxPixelSize: 0))
    }

    func testMetadataContainsNestedGPSAndEXIFValues() throws {
        let url = try writeImage("gps.jpg", type: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 127.25, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:22 12:30:00"]
        ])
        let entries = try MetadataService.entries(at: url)
        XCTAssertTrue(entries.contains { $0.key.hasSuffix("Latitude") && $0.value == "37.5" })
        XCTAssertTrue(entries.contains { $0.key.hasSuffix("Longitude") && $0.value == "127.25" })
        XCTAssertTrue(entries.contains { $0.key.hasSuffix("DateTimeOriginal") && $0.value == "2026:10:22 12:30:00" })
        XCTAssertTrue(entries.contains { $0.key == "File / Name" && $0.value == "gps.jpg" })
        XCTAssertTrue(entries.contains { $0.key.hasSuffix("PixelWidth") && $0.value == "80" })
    }

    func testThumbnailCallbacksArriveOnMainThreadAndCacheInvalidates() throws {
        let url = try writeImage("thumbnail.png")
        let callbacks = expectation(description: "coalesced thumbnail callbacks")
        callbacks.expectedFulfillmentCount = 4
        for _ in 0..<4 {
            ThumbnailService.shared.image(for: url, pixelSize: 20) { image in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(image?.size, NSSize(width: 20, height: 10))
                callbacks.fulfill()
            }
        }
        wait(for: [callbacks], timeout: 5)
        _ = try writeImage("thumbnail.png", width: 40, height: 80)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: url.path)
        let replaced = expectation(description: "updated thumbnail")
        ThumbnailService.shared.image(for: url, pixelSize: 20) { image in
            XCTAssertEqual(image?.size, NSSize(width: 10, height: 20))
            replaced.fulfill()
        }
        wait(for: [replaced], timeout: 5)
        let missing = expectation(description: "failed thumbnail")
        ThumbnailService.shared.image(for: root.appendingPathComponent("missing.png"), pixelSize: 20) { image in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(image)
            missing.fulfill()
        }
        wait(for: [missing], timeout: 5)
    }

    func testCopyKeepsBothWithoutOverwritingAndReportsPartialFailure() throws {
        let source = try writeImage("original.png")
        let originalData = try Data(contentsOf: source)
        let result = FileOperations.copy([source, source, root.appendingPathComponent("missing.png")], to: root, conflict: .keepBoth)
        XCTAssertEqual(result.succeeded.map(\.lastPathComponent), ["original 2.png", "original 3.png"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), originalData)
        for copy in result.succeeded { XCTAssertEqual(try Data(contentsOf: copy), originalData) }
        let skipped = FileOperations.copy([source], to: root, conflict: .skip)
        XCTAssertTrue(skipped.succeeded.isEmpty)
        XCTAssertEqual(skipped.failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), originalData)
        let invalidDestination = FileOperations.copy([source], to: source, conflict: .keepBoth)
        XCTAssertEqual(invalidDestination.failures.count, 1)
    }

    func testTrashMissingFileReportsFailure() {
        let result = FileOperations.trash([root.appendingPathComponent("missing.png")])
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
    }

    @discardableResult
    private func writeImage(_ name: String, type: UTType = .png, width: Int = 80, height: Int = 40, properties: [CFString: Any] = [:]) throws -> URL {
        let url = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.encodingFailed }
        return url
    }

    private enum FixtureError: Error { case encodingFailed }
}
