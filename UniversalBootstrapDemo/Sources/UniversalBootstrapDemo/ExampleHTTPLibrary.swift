//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1
import Foundation

public struct UnsupportedURLError: Error {
    var url: String
}

public final class ExampleHTTPLibrary: Sendable {
    let groupManager: EventLoopGroupManager

    public init(groupProvider provider: EventLoopGroupManager.Provider) {
        self.groupManager = EventLoopGroupManager(provider: provider)
    }

    public func shutdown() throws {
        try self.groupManager.syncShutdown()
    }

    public func makeRequest(url urlString: String) throws {
        final class PrintToStdoutHandler: ChannelInboundHandler {

            typealias InboundIn = HTTPClientResponsePart

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                switch self.unwrapInboundIn(data) {
                case .head:
                    () // ignore
                case .body(let buffer):
                    buffer.withUnsafeReadableBytes { ptr in
                        _ = write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
                    }
                case .end:
                    context.close(promise: nil)
                }
            }
        }

        guard let url = URL(string: urlString),
              let hostname = url.host,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw UnsupportedURLError(url: urlString)
        }
        let useTLS = scheme == "https"
        let connection = try groupManager.makeBootstrap(hostname: hostname, useTLS: useTLS)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        channel.pipeline.addHandler(PrintToStdoutHandler())
                    }
                }
                .connect(host: hostname, port: useTLS ? 443 : 80)
                .wait()
        print("# Channel")
        print(connection)
        print("# ChannelPipeline")
        print("\(connection.pipeline)")
        print("# HTTP response body")
        let reqHead = HTTPClientRequestPart.head(.init(version: .init(major: 1, minor: 1),
                                                       method: .GET,
                                                       uri: url.path,
                                                       headers: ["host": hostname]))
        connection.write(reqHead, promise: nil)
        try connection.writeAndFlush(HTTPClientRequestPart.end(nil)).wait()
        try connection.closeFuture.wait()
    }
}
