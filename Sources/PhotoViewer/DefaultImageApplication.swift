import AppKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import PhotoViewerCore
#endif

struct DefaultImageApplicationResult {
    struct Failure {
        let type: UTType
        let reason: String
    }

    var successfulTypes: [UTType] = []
    var failures: [Failure] = []

    var message: String {
        if failures.isEmpty { return "Mr. Still를 기본 이미지 앱으로 설정했습니다." }
        if successfulTypes.isEmpty { return "기본 이미지 앱 설정을 완료하지 못했습니다." }
        return "일부 이미지 형식의 기본 앱을 설정했습니다."
    }

    var details: String {
        var lines: [String] = []
        if !successfulTypes.isEmpty {
            lines.append("설정 완료: " + successfulTypes.map(Self.name).joined(separator: ", "))
        }
        if !failures.isEmpty {
            lines.append("설정하지 못한 형식:")
            lines += failures.map { "\(Self.name($0.type)): \($0.reason)" }
        }
        return lines.joined(separator: "\n")
    }

    private static func name(_ type: UTType) -> String {
        type.preferredFilenameExtension?.uppercased() ?? type.identifier
    }
}

@MainActor
struct DefaultImageApplication {
    typealias Setter = (URL, UTType) async throws -> Void
    typealias Reader = (UTType) -> URL?

    private let setApplication: Setter
    private let application: Reader

    init(setApplication: @escaping Setter, application: @escaping Reader) {
        self.setApplication = setApplication
        self.application = application
    }

    static var workspace: Self {
        Self(setApplication: { url, type in
            // NSWorkspace presents any required system consent and completes asynchronously.
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
        }, application: { NSWorkspace.shared.urlForApplication(toOpen: $0) })
    }

    func setSupportedTypes(to applicationURL: URL) async -> DefaultImageApplicationResult {
        var result = DefaultImageApplicationResult()
        let target = applicationURL.resolvingSymlinksInPath().standardizedFileURL
        for type in DirectoryService.supportedTypes {
            do {
                if application(type)?.resolvingSymlinksInPath().standardizedFileURL != target {
                    // Keep requests sequential so system consent dialogs never overlap.
                    try await setApplication(applicationURL, type)
                }
                guard application(type)?.resolvingSymlinksInPath().standardizedFileURL == target else {
                    result.failures.append(.init(type: type, reason: "macOS에서 기본 앱 변경을 확인할 수 없습니다."))
                    continue
                }
                result.successfulTypes.append(type)
            } catch {
                result.failures.append(.init(type: type, reason: error.localizedDescription))
            }
        }
        return result
    }
}
