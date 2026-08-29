// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KVF",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        // Exposed so the tvOS app can depend on the shared layer.
        .library(name: "KVFKit", targets: ["KVFKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Models + kvf.fo scraping/feeds. No UI, so kvf-check can exercise the parsers.
        .target(name: "KVFKit"),
        .executableTarget(
            name: "KVF",
            dependencies: ["KVFKit", .product(name: "Sparkle", package: "Sparkle")]),
        // kvf-check stays dependency-free so the parser checks run without Sparkle.
        .executableTarget(name: "kvf-check", dependencies: ["KVFKit"]),
    ]
)
