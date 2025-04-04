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

import Dispatch
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
    .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
    .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(
                ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
            )
            try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
            try channel.pipeline.syncOperations.addHandler(
                ConnectHandler(logger: Logger(label: "com.apple.nio-connect-proxy.ConnectHandler"))
            )
        }
    }

bootstrap.bind(to: try! SocketAddress(ipAddress: "127.0.0.1", port: 8080)).whenComplete { result in
    // Need to create this here for thread-safety purposes
    let logger = Logger(label: "com.apple.nio-connect-proxy.main")

    switch result {
    case .success(let channel):
        logger.info("Listening on \(String(describing: channel.localAddress))")
    case .failure(let error):
        logger.error("Failed to bind 127.0.0.1:8080, \(error)")
    }
}

bootstrap.bind(to: try! SocketAddress(ipAddress: "::1", port: 8080)).whenComplete { result in
    // Need to create this here for thread-safety purposes
    let logger = Logger(label: "com.apple.nio-connect-proxy.main")

    switch result {
    case .success(let channel):
        logger.info("Listening on \(String(describing: channel.localAddress))")
    case .failure(let error):
        logger.error("Failed to bind [::1]:8080, \(error)")
    }
}

// Run forever
dispatchMain()
