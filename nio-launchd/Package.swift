// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "nio-launchd",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "0.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "nio-launchd",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
    ]
)
