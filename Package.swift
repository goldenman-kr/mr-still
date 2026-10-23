// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoViewer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhotoViewer", targets: ["PhotoViewer"])],
    targets: [
        .target(name: "PhotoViewerCore"),
        .executableTarget(name: "PhotoViewer", dependencies: ["PhotoViewerCore"]),
        .testTarget(name: "PhotoViewerCoreTests", dependencies: ["PhotoViewerCore"]),
        .testTarget(name: "PhotoViewerAppTests", dependencies: ["PhotoViewer", "PhotoViewerCore"])
    ]
)
