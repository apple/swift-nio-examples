// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "nio-launchd",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
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
