// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassChat",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Vendor/swift-markdown-ui"),
        .package(path: "Vendor/HighlightSwift"),
    ],
    targets: [
        .executableTarget(
            name: "GlassChat",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
            ],
            path: "Sources/GlassChat",
            resources: [.copy("Resources/KaTeX")]
        )
    ]
)
