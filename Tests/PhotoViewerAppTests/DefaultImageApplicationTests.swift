import XCTest
import UniformTypeIdentifiers
@testable import PhotoViewer
import PhotoViewerCore

final class DefaultImageApplicationTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Mr. Still.app", isDirectory: true)

    @MainActor
    func testSetsEverySupportedFormatSequentiallyAndVerifiesResults() async {
        var defaults: [UTType: URL] = [:]
        var requested: [UTType] = []
        var activeRequests = 0
        let service = DefaultImageApplication(setApplication: { url, type in
            activeRequests += 1
            XCTAssertEqual(activeRequests, 1)
            await Task.yield()
            requested.append(type)
            defaults[type] = url
            activeRequests -= 1
        }, application: { defaults[$0] })

        let result = await service.setSupportedTypes(to: app)
        XCTAssertEqual(Set(requested), Set([UTType.jpeg, .png, .heic, .heif, .tiff, .bmp, .gif]))
        XCTAssertEqual(requested.count, 7)
        XCTAssertEqual(result.successfulTypes.count, 7)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.details.contains("HEIC"))
        XCTAssertTrue(result.details.contains("HEIF"))
    }

    @MainActor
    func testAlreadySelectedApplicationNeedsNoSystemChange() async {
        let target = app
        let service = DefaultImageApplication(setApplication: { _, _ in
            XCTFail("Existing defaults must not request system consent again")
        }, application: { _ in target })

        let result = await service.setSupportedTypes(to: target)
        XCTAssertEqual(result.successfulTypes.count, 7)
        XCTAssertTrue(result.failures.isEmpty)
    }

    @MainActor
    func testReportsDeclinedAndUnchangedFormatsWhileCompletingRemainingTypes() async {
        var defaults: [UTType: URL] = [:]
        let service = DefaultImageApplication(setApplication: { url, type in
            if type == .png { throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
            if type != .heif { defaults[type] = url }
        }, application: { defaults[$0] })

        let result = await service.setSupportedTypes(to: app)
        XCTAssertEqual(result.successfulTypes.count, 5)
        XCTAssertEqual(result.failures.map(\.type), [.png, .heif])
        XCTAssertTrue(result.successfulTypes.contains(.gif), "A failed earlier format must not stop the remaining formats")
        XCTAssertEqual(result.message, L10n.text("The default app was set for some image formats."))
        XCTAssertTrue(result.details.contains("PNG"))
        XCTAssertTrue(result.details.contains("HEIF"))
        XCTAssertFalse(result.failures[0].reason.isEmpty)
        XCTAssertEqual(result.failures[1].reason, L10n.text("macOS could not confirm the default app change."))
    }

    func testSupportedDefaultTypesMatchAppDocumentDeclarations() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: project.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let documents = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let identifiers = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(identifiers), Set(DirectoryService.supportedTypes.map(\.identifier)))
    }
}
