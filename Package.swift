// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoViewer",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhotoViewer", targets: ["PhotoViewer"])],
    targets: [
        .target(name: "PhotoViewerCore", resources: [.process("Localization")]),
        .executableTarget(name: "PhotoViewer", dependencies: ["PhotoViewerCore"]),
        .testTarget(name: "PhotoViewerCoreTests", dependencies: ["PhotoViewerCore"]),
        .testTarget(name: "PhotoViewerAppTests", dependencies: ["PhotoViewer", "PhotoViewerCore"])
    ]
)
