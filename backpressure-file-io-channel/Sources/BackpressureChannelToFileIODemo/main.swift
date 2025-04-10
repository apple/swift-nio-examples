//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import BackpressureChannelToFileIO
import Logging
import NIOCore
import NIOPosix

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
    try! group.syncShutdownGracefully()
}

let threadPool = NIOThreadPool(numberOfThreads: 1)
threadPool.start()
defer {
    try! threadPool.syncShutdownGracefully()
}

let fileIO = NonBlockingFileIO(threadPool: threadPool)

let logger: Logger = {
    var logger = Logger(label: "BackpressureChannelToFileIO")
    logger.logLevel = .info
    return logger
}()

let server = try ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
    .childChannelInitializer { [logger] channel in
        var logger = logger
        logger[metadataKey: "connection"] = "\(channel.remoteAddress!)"
        return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: false).flatMap { [logger] in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHandler(
                    SaveEverythingHTTPServer(
                        fileIO: fileIO,
                        uploadDirectory: "/tmp",
                        logger: logger
                    )
                )
            }
        }
    }
    .bind(host: "localhost", port: 8080)
    .wait()
logger.info("Server up and running at \(server.localAddress!)")
try! server.closeFuture.wait()
