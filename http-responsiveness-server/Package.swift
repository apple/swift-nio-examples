// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "nio-http-responsiveness-server",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HTTPResponsivenessServer", targets: ["HTTPResponsivenessServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.79.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.35.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(
            url: "https://github.com/apple/swift-nio-extras.git",
            revision: "4804de1953c14ce71cfca47a03fb4581a6b3301c"
        ),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/swift-extras/swift-extras-json.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.23.0"),
    ],
    targets: [
        .executableTarget(
            name: "HTTPResponsivenessServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOHTTPTypesHTTP2", package: "swift-nio-extras"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
                .product(name: "NIOHTTPResponsiveness", package: "swift-nio-extras"),
                .product(name: "ExtrasJSON", package: "swift-extras-json"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
