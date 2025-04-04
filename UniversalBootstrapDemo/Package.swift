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
    name: "UniversalBootstrapDemo",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.42.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.16.1"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.11.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.1")
    ],
    targets: [
        .executableTarget(
            name: "UniversalBootstrapDemo",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
    ]
)
