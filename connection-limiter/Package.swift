// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "connection-limiter",
    dependencies: [
        .package(name: "swift-nio", url: "https://github.com/apple/swift-nio", from: "2.16.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "connection-limiter",
            dependencies: [
                .product(name: "NIO", package: "swift-nio")
            ]),
        .testTarget(
            name: "connection-limiterTests",
            dependencies: ["connection-limiter"]),
    ]
)
