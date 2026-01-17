// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // Core library
        .library(
            name: "AgentKit",
            targets: ["AgentKit"]
        ),
        // HTTP server executable
        .executable(
            name: "AgentKitServer",
            targets: ["AgentKitServer"]
        ),
        // CLI tool for testing
        .executable(
            name: "AgentKitCLI",
            targets: ["AgentKitCLI"]
        ),
        // Envoy - macOS app for agent interaction
        .executable(
            name: "Envoy",
            targets: ["Envoy"]
        ),
    ],
    dependencies: [
        // HTTP server
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),

        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),

        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),

        // MLX for native Apple Silicon inference
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),

        // MLX LLM library for model loading and generation
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.29.0"),

        // VecturaKit for on-device vector database / RAG
        // TODO: Re-enable once API is tested and integrated
        // .package(url: "https://github.com/rryam/VecturaKit.git", from: "2.3.1"),

        // Markdown rendering for chat messages
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "AgentKit",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                // .product(name: "MLXVLM", package: "mlx-swift-lm"),  // TODO: Re-enable when upstream bug #35 is fixed
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                // .product(name: "VecturaKit", package: "VecturaKit"),  // TODO: Re-enable
            ],
            path: "Sources/AgentKit"
        ),

        // MARK: - Server Executable
        .executableTarget(
            name: "AgentKitServer",
            dependencies: [
                "AgentKit",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AgentKitServer"
        ),

        // MARK: - CLI Tool
        .executableTarget(
            name: "AgentKitCLI",
            dependencies: [
                "AgentKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AgentKitCLI"
        ),

        // MARK: - Envoy (macOS App)
        .executableTarget(
            name: "Envoy",
            dependencies: [
                "AgentKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources/Envoy",
            exclude: [
                "Envoy.entitlements",  // Xcode-specific, not needed for SPM build
                "Info.plist"  // Handled by SPM automatically
            ],
            resources: [
                .process("Resources")
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "AgentKitTests",
            dependencies: ["AgentKit"],
            path: "Tests/AgentKitTests"
        ),
    ]
)
