// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var targets: [PackageDescription.Target] = [
    .target(name: "JSONRPC", dependencies: ["NIO", "NIOFoundationCompat", "NIOExtras"]),
    .target(name: "ServerExample", dependencies: ["JSONRPC"]),
    .target(name: "ClientExample", dependencies: ["JSONRPC"]),
    .target(name: "LightsdDemo", dependencies: ["JSONRPC"]),
    .testTarget(name: "JSONRPCTests", dependencies: ["JSONRPC"]),
]

let package = Package(
    name: "swift-json-rpc",
    products: [
        .library(name: "JSONRPC", targets: ["JSONRPC"]),
        .executable(name: "ServerExample", targets: ["ServerExample"]),
        .executable(name: "ClientExample", targets: ["ClientExample"]),
        .executable(name: "LightsdDemo", targets: ["LightsdDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-extras", from: "1.0.0"),
    ],
    targets: targets
)
