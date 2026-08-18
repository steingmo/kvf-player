// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KVF",
    platforms: [.macOS(.v14)],
    targets: [
        // Models + kvf.fo scraping/feeds. No UI, so kvf-check can exercise the parsers.
        .target(name: "KVFKit"),
        .executableTarget(name: "KVF", dependencies: ["KVFKit"]),
        .executableTarget(name: "kvf-check", dependencies: ["KVFKit"]),
    ]
)
