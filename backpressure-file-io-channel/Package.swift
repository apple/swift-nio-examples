// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "backpressure-file-io-channel",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.16.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "BackpressureChannelToFileIO",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .executableTarget(
            name: "BackpressureChannelToFileIODemo",
            dependencies: [
                "BackpressureChannelToFileIO",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .testTarget(
            name: "BackpressureChannelToFileIOTests",
            dependencies: [
                "BackpressureChannelToFileIO",
                .product(name: "NIO", package: "swift-nio"),
            ]),
    ]
)
