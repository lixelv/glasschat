// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassChat",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Vendor/swift-markdown-ui"),
        .package(path: "Vendor/HighlightSwift"),
        // Local voice: whisper-large-v3-turbo (CoreML) and Supertonic 3 text to speech (ONNX Runtime).
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.18.0"),
        .package(url: "https://github.com/onethreeeseven/supertonic.swift", revision: "e26051d312031b0c1238f6114ab4ce899c31a148"),
        // swift-collections 1.3 and later need the standard library of the macOS 27 SDK.
        .package(url: "https://github.com/apple/swift-collections", "1.1.0"..<"1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "GlassChat",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Supertonic", package: "supertonic.swift"),
            ],
            path: "Sources/GlassChat",
            resources: [.copy("Resources/KaTeX")]
        )
    ]
)
