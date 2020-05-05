// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UniversalBootstrapDemo",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.16.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.7.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.5.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "0.0.5"))
    ],
    targets: [
        .target(
            name: "UniversalBootstrapDemo",
            dependencies: ["NIO", "NIOSSL", "NIOTransportServices", "NIOHTTP1", "ArgumentParser"]),
    ]
)
