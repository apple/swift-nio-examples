// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UniversalBootstrapDemo",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.33.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.16.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.11.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.1")
    ],
    targets: [
        .target(
            name: "UniversalBootstrapDemo",
            dependencies: ["NIO", "NIOSSL", "NIOTransportServices", "NIOHTTP1", "ArgumentParser"]),
    ]
)
