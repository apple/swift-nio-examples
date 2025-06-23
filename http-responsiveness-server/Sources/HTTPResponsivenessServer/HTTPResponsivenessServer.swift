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

import ArgumentParser
import ExtrasJSON
import NIOCore
import NIOExtras
import NIOHTTP1
import NIOHTTP2
import NIOHTTPResponsiveness
import NIOHTTPTypesHTTP1
import NIOHTTPTypesHTTP2
import NIOPosix
import NIOSSL
import NIOTLS
import NIOTransportServices

func responsivenessConfigBuffer(scheme: String, host: String, port: Int) throws -> ByteBuffer {
    let cfg = ResponsivenessConfig(
        version: 1,
        urls: ResponsivenessConfigURLs(scheme: scheme, authority: "\(host):\(port)")
    )
    let encoded = try XJSONEncoder().encode(cfg)
    return ByteBuffer(bytes: encoded)
}

@main
private struct HTTPResponsivenessServer: ParsableCommand {
    @Option(help: "Host to bind to.")
    var host: String

    @Option(help: "Port to bind to.")
    var port: Int

    @Option(help: "Number of threads to use.")
    var threads: Int? = nil

    @Option(
        name: .customLong("max-idle-time"),
        help: "Time a connection may be idle for before being closed, in seconds."
    )
    var maxIdleTimeSeconds: Int64?

    @Option(
        name: .customLong("max-age"),
        help: "Time a connection may exist before being gracefully closed, in seconds."
    )
    var maxAgeSeconds: Int64?

    @Option(
        name: .customLong("max-grace-time"),
        help: "Grace period for connections to close after shutdown, in seconds."
    )
    var maxGraceTimeSeconds: Int64?

    func run() throws {
        if let threads = self.threads {
            NIOSingletons.groupLoopCountSuggestion = threads
        }

        let group = MultiThreadedEventLoopGroup.singleton

        // This helper can initate the shutdown process
        let quiesce = ServerQuiescingHelper(group: group)
        let fullyShutdownPromise: EventLoopPromise<Void> = group.next().makePromise()

        // This builds the response for requests to /responsiveness
        let config = try responsivenessConfigBuffer(scheme: "http", host: host, port: port)

        let bootstrap = ServerBootstrap(group: group)
            // Configure the server
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)

            // Inject the channel handler for the shutdown process
            .serverChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(quiesce.makeServerChannelHandler(channel: channel))
                }
            }

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                channel.pipeline.eventLoop.makeCompletedFuture {
                    let shutdownHandler = ServerConnectionManagementHandler(
                        eventLoop: channel.eventLoop,
                        maxIdleTime: maxIdleTimeSeconds == nil ? nil : .seconds(self.maxIdleTimeSeconds!),
                        maxAge: self.maxAgeSeconds == nil ? nil : .seconds(self.maxAgeSeconds!),
                        maxGraceTime: self.maxGraceTimeSeconds == nil ? nil : .seconds(self.maxGraceTimeSeconds!)
                    )

                    _ = try channel.pipeline.syncOperations.configureHTTP2Pipeline(
                        mode: .server,
                        connectionConfiguration: .init(),
                        streamConfiguration: .init(),
                        streamDelegate: shutdownHandler.http2StreamDelegate
                    ) { channel in
                        channel.pipeline.eventLoop.makeCompletedFuture {
                            let sync = channel.pipeline.syncOperations
                            try sync.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                            try sync.addHandlers(HTTP1ToHTTPServerCodec(secure: false))
                            try sync.addHandler(
                                SimpleResponsivenessRequestMux(
                                    responsivenessConfigBuffer: config,
                                    forwardOtherRequests: true
                                )
                            )
                            try sync.addHandlers(
                                HTTPAdminHandler {
                                    quiesce.initiateShutdown(promise: fullyShutdownPromise)
                                }
                            )
                        }
                    }
                    try channel.pipeline.syncOperations.addHandlers(shutdownHandler)
                    try channel.pipeline.syncOperations.addHandlers(NIOCloseOnErrorHandler())
                }
            }
            // Configure the accepted channels
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        _ = try! bootstrap.bind(host: host, port: port).wait()

        // Wait for the server to shutdown.
        try fullyShutdownPromise.futureResult.wait()
    }
}
