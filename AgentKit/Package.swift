// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
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
    ],
    dependencies: [
        // HTTP server
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),

        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),

        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),

        // Note: MLX will be added once we start Phase 2
        // .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "AgentKit",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
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

        // MARK: - Tests
        .testTarget(
            name: "AgentKitTests",
            dependencies: ["AgentKit"],
            path: "Tests/AgentKitTests"
        ),
    ]
)
