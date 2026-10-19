// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassChat",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(path: "Vendor/HighlightSwift"),
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
    ],
    targets: [
        .executableTarget(
            name: "GlassChat",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            path: "Sources/GlassChat"
        )
    ]
)
