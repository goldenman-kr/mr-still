import AppKit
import Darwin
import Foundation

// Reproduce from repository root:
// swiftc -O -target arm64-apple-macos14.0 -module-cache-path build/BenchmarkModuleCache -parse-as-library Sources/PhotoViewerCore/Models.swift Sources/PhotoViewerCore/Services.swift scripts/benchmark.swift -o build/Verification/benchmark
// build/Verification/benchmark
@main
struct PerformanceBenchmark {
    static let iterations = 20
    static let fileCount = 10_000

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 5, arguments[1] == "--case" {
            let result = try measure(arguments[2], fixture: URL(fileURLWithPath: arguments[3]), directory: URL(fileURLWithPath: arguments[4]))
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
            return
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fixture = root.appendingPathComponent("build/Fixtures/01 Alpine Lake.jpg")
        let outputDirectory = root.appendingPathComponent("build/Verification", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let directory = outputDirectory.appendingPathComponent("BenchmarkDirectory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 1...fileCount {
            try FileManager.default.linkItem(at: fixture, to: directory.appendingPathComponent("Photo\(index).jpg"))
        }

        var measurements = [[String: Any]]()
        for name in ["directory_listing_and_natural_name_sort", "24mp_preview_decode_1600px", "24mp_original_decode"] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: arguments[0], relativeTo: root).standardizedFileURL
            child.arguments = ["--case", name, fixture.path, directory.path]
            let output = Pipe()
            child.standardOutput = output
            try child.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            guard child.terminationStatus == 0,
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Benchmark", code: Int(child.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Benchmark child failed: \(name)"])
            }
            measurements.append(result)
        }

        let report: [String: Any] = [
            "recorded_at_utc": ISO8601DateFormatter().string(from: Date()),
            "scope": "Core service throughput only. Does not measure UI transition latency, rendering, thumbnail grid population, event-loop responsiveness, or app-wide peak memory.",
            "fixture": ["path": fixture.path, "kind": "Synthetic gradient JPEG; generated locally, not a user photo", "width_pixels": 6000, "height_pixels": 4000, "file_bytes": (try FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as? NSNumber)?.int64Value ?? 0],
            "host": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "hardware_model": systemString("hw.model"), "cpu": systemString("machdep.cpu.brand_string"), "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory, "active_processor_count": ProcessInfo.processInfo.activeProcessorCount],
            "conditions": [
                "Optimized (-O) standalone Swift executable compiled directly with the current Models.swift and Services.swift.",
                "10,000 synthetic directory entries are hardlinks to the same fixture; filesystem metadata/link locality is not representative of 10,000 unrelated photographs.",
                "Each workload runs in a separate child process with one excluded warmup and 20 serial measured iterations; filesystem cache is warm and is not purged.",
                "ImageLoader.load creates a new image source each time; no ThumbnailService cache is involved. The API requests immediate decode caching.",
                "Autorelease pools drain between iterations; measurement includes returned object validation and excludes fixture creation.",
                "p95 uses nearest-rank ceil(0.95*n), median averages the middle pair. Samples are wall-clock milliseconds.",
                "Peak RSS is getrusage(RUSAGE_SELF).ru_maxrss in bytes on macOS, covering the workload child lifetime including warmup and runtime overhead; it is not an incremental allocation measurement.",
                "Concurrent desktop activity and other verification processes are uncontrolled; results are observations, not pass/fail thresholds."
            ],
            "reproduction": "swiftc -O -target arm64-apple-macos14.0 -module-cache-path build/BenchmarkModuleCache -parse-as-library Sources/PhotoViewerCore/Models.swift Sources/PhotoViewerCore/Services.swift scripts/benchmark.swift -o build/Verification/benchmark && build/Verification/benchmark",
            "measurements": measurements
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("performance.json"), options: .atomic)
        FileHandle.standardOutput.write(data)
        print()
    }

    static func measure(_ name: String, fixture: URL, directory: URL) throws -> [String: Any] {
        var decodedDimensions = [Int]()
        func perform() throws {
            try autoreleasepool {
                if name == "directory_listing_and_natural_name_sort" {
                    let files = FileOrdering.sorted(try DirectoryService.contents(of: directory), by: .name, ascending: true)
                    guard files.count == fileCount, files.first?.name == "Photo1.jpg", files.last?.name == "Photo10000.jpg" else {
                        throw NSError(domain: "Benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory result validation failed"])
                    }
                } else {
                    let preview = name == "24mp_preview_decode_1600px"
                    let image = try ImageLoader.load(url: fixture, maxPixelSize: preview ? 1600 : nil)
                    guard image.pixelSize == CGSize(width: 6000, height: 4000), image.image.width == (preview ? 1600 : 6000) else {
                        throw NSError(domain: "Benchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decoded dimensions validation failed"])
                    }
                    decodedDimensions = [image.image.width, image.image.height]
                }
            }
        }
        try perform()
        var samples = [Double]()
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try perform()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let sorted = samples.sorted()
        var usage = rusage()
        let usageAvailable = getrusage(RUSAGE_SELF, &usage) == 0
        var result: [String: Any] = [
            "name": name,
            "measured_iterations": iterations,
            "excluded_warmup_iterations": 1,
            "median_ms": (sorted[iterations / 2 - 1] + sorted[iterations / 2]) / 2,
            "p95_ms": sorted[Int(ceil(Double(iterations) * 0.95)) - 1],
            "minimum_ms": sorted.first!,
            "maximum_ms": sorted.last!,
            "samples_ms": samples,
            "peak_rss_bytes": usageAvailable ? usage.ru_maxrss : NSNull()
        ]
        if decodedDimensions.isEmpty { result["file_count"] = fileCount }
        else { result["decoded_dimensions_pixels"] = decodedDimensions }
        return result
    }

    static func systemString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        return String(cString: bytes)
    }
}
