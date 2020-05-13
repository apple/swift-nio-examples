// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "backpressure-file-io-channel",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.16.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "BackpressureChannelToFileIO",
            dependencies: ["NIO", "NIOHTTP1", "Logging"]),
    ]
)
