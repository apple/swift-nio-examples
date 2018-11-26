// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "http2-client",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-nio", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-http2", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "http2-client",
            dependencies: ["NIO", "NIOOpenSSL", "NIOHTTP1", "NIOHTTP2"]),
    ]
)
