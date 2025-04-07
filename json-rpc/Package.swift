// swift-tools-version:5.7
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

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
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
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
                "JSONRPC",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Tests/JsonRpcTests"),
    ]
)
