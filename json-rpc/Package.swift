// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-json-rpc",
    products: [
        .library(name: "JSONRPC", targets: ["JSONRPC"]),
        .executable(name: "ServerExample", targets: ["ServerExample"]),
        .executable(name: "ClientExample", targets: ["ClientExample"]),
        .executable(name: "LightsdDemo", targets: ["LightsdDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.42.0"),
        .package(url: "https://github.com/apple/swift-nio-extras", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "JSONRPC",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
            ],
            path: "Sources/JsonRpc"),
        .executableTarget(
            name: "ServerExample",
            dependencies: [
                "JSONRPC"
            ]),
        .executableTarget(
            name: "ClientExample",
            dependencies: [
                "JSONRPC"
            ]),
        .executableTarget(
            name: "LightsdDemo",
            dependencies: [
                "JSONRPC"
            ]),
        .testTarget(
            name: "JSONRPCTests",
            dependencies: [
                "JSONRPC"
            ],
            path: "Tests/JsonRpcTests"),
    ]
)
