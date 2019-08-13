// swift-tools-version:5.1
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
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
    name: "http2-server",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.5.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.5.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "http2-server",
            dependencies: ["NIO", "NIOHTTP1", "NIOHTTP2", "NIOSSL"]),
    ]
)
