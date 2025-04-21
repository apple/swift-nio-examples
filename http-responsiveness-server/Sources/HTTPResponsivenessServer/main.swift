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
import Foundation
import NIOCore
import NIOHTTP1
import NIOHTTP2
import NIOHTTPResponsiveness
import NIOHTTPTypesHTTP1
import NIOHTTPTypesHTTP2
import NIOPosix
import NIOSSL
import NIOTLS
import NIOTransportServices

enum ChannelInitializeError: Error {
    case unrecognizedPort(Int?)
}

// MARK: Performance Measurement Handler

/// Logs the time between request head and request end.
final class PerformanceMeasurementHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    private var startTime: DispatchTime?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head:
            startTime = DispatchTime.now()
            context.fireChannelRead(data)
        case .body:
            context.fireChannelRead(data)
        case .end:
            if let start = startTime {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                print("Request handled in \(String(format: "%.2f", elapsedMs)) ms")
            }
            context.fireChannelRead(data)
        }
    }
}

/// Simple `/ping` endpoint that immediately responds “pong” — and swallows both head and end.
final class PingHandler: ChannelInboundHandler {
    // HTTP *requests* coming in…
    typealias InboundIn = HTTPServerRequestPart
    // HTTP *responses* going out.
    typealias OutboundOut = HTTPServerResponsePart

    // Track whether we’re currently in the middle of a ping request:
    private var handlingPing = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head) where head.uri == "/ping":
            // Mark that we’ve started handling ping:
            handlingPing = true

            // Build and send a 200 OK / "pong"
            var resHead = HTTPResponseHead(version: head.version, status: .ok)
            resHead.headers.add(name: "Content-Length", value: "4")
            resHead.headers.add(name: "Content-Type", value: "text/plain")
            context.write(wrapOutboundOut(.head(resHead)), promise: nil)

            var buf = context.channel.allocator.buffer(capacity: 4)
            buf.writeString("pong")
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)

            // And flush the end of response:
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

            // **Do not forward** the request head downstream.
            return

        case .body where handlingPing:
            // ignore any body for ping
            return

        case .end where handlingPing:
            // ping is done
            handlingPing = false
            return

        default:
            // everything else: pass through normally
            context.fireChannelRead(data)
        }
    }
}

func configureCommonHTTPTypesServerPipeline(
    _ channel: Channel,
    _ configurator: @Sendable @escaping (Channel) -> EventLoopFuture<Void>
) -> EventLoopFuture<Void> {
    channel.configureHTTP2SecureUpgrade(
        h2ChannelConfigurator: { channel in
            channel.configureHTTP2Pipeline(mode: .server) { streamChannel in
                do {
                    try streamChannel.pipeline.syncOperations.addHandler(
                        HTTP2FramePayloadToHTTPServerCodec()
                    )
                } catch {
                    return streamChannel.eventLoop.makeFailedFuture(error)
                }
                return configurator(streamChannel)
            }.map { _ in () }
        },
        http1ChannelConfigurator: { channel in
            channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                do {
                    try channel.pipeline.syncOperations.addHandler(
                        HTTP1ToHTTPServerCodec(secure: true)
                    )
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
                return configurator(channel)
            }
        }
    )
}

func channelInitializer(
    channel: Channel,
    tls: ([Int], NIOSSLContext, ByteBuffer)?,
    insecure: ([Int], ByteBuffer)?,
    isNIOTS: Bool = false,
    collectBenchmarks: Bool = false
) -> EventLoopFuture<Void> {
    // Handle TLS case
    var port = channel.localAddress?.port
    if port == nil && isNIOTS {
        port = insecure?.0.first
    }

    if let (ports, sslContext, config) = tls, let port,
        ports.contains(port)
    {
        let handler = NIOSSLServerHandler(context: sslContext)
        do {
            try channel.pipeline.syncOperations.addHandler(handler)
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
        return configureCommonHTTPTypesServerPipeline(channel) { channel in
            channel.eventLoop.makeCompletedFuture {
                if collectBenchmarks {
                    try channel.pipeline.syncOperations.addHandler(PerformanceMeasurementHandler())
                }
                try channel.pipeline.syncOperations.addHandler(
                    SimpleResponsivenessRequestMux(responsivenessConfigBuffer: config)
                )
            }
        }
    }

    // Handle insecure case
    if let (ports, config) = insecure, let port, ports.contains(port) {
        return channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
            // If benchmarking is enabled, install timer and ping handlers first:
            if collectBenchmarks {
                try channel.pipeline.syncOperations.addHandler(PerformanceMeasurementHandler())
                try channel.pipeline.syncOperations.addHandler(PingHandler())
            }
            let mux = SimpleResponsivenessRequestMux(responsivenessConfigBuffer: config)
            return try channel.pipeline.syncOperations.addHandlers([
                HTTP1ToHTTPServerCodec(secure: false),
                mux,
            ])
        }
    }

    // We're getting traffic on a port we didn't expect. Fail the connection
    return channel.eventLoop.makeFailedFuture(
        ChannelInitializeError.unrecognizedPort(channel.localAddress?.port)
    )
}

enum RunError: Error {
    case inputError(String)
}

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
    @Option(help: "Which host to bind to")
    var host: String

    @Option(help: "Which port to bind to for encrypted connections")
    var port: Int? = nil

    @Option(help: "Which port to bind to for unencrypted connections")
    var insecurePort: Int? = nil

    @Option(help: "path to PEM encoded certificate")
    var certificatePath: String?

    @Option(help: "path to PEM encoded private key")
    var privateKeyPath: String?

    @Flag(
        name: .customLong("nw"),
        help: "Use Network framework instead of NIOSSL. Disables TLS support."
    )
    var useNetwork: Bool = false

    @Option(help: "override how many threads to use")
    var threads: Int? = nil

    @Flag(help: "Enable per-request performance measurements")
    var collectBenchmarks: Bool = false

    func run() throws {
        if port == nil && insecurePort == nil {
            throw RunError.inputError("must provide either port or insecurePort")
        }

        if useNetwork && port != nil {
            throw RunError.inputError("Network.framework backend doesn't support TLS")
        }

        let tls = try port.map { port in
            guard let certificatePath = certificatePath, let privateKeyPath = privateKeyPath else {
                throw RunError.inputError("must provide TLS keypair")
            }

            let secureResponsivenessConfig = try responsivenessConfigBuffer(
                scheme: "https",
                host: host,
                port: port
            )

            let certificate = try NIOSSLCertificate(file: certificatePath, format: .pem)
            let privateKey = try NIOSSLPrivateKey(file: privateKeyPath, format: .pem)
            var sslConfiguration = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(certificate)],
                privateKey: .privateKey(privateKey)
            )
            sslConfiguration.applicationProtocols = ["h2", "http/1.1"]
            let sslContext = try NIOSSLContext(configuration: sslConfiguration)
            return ([port], sslContext, secureResponsivenessConfig)
        }

        let insecure = try insecurePort.map { port in
            let config = try responsivenessConfigBuffer(scheme: "http", host: host, port: port)
            return ([port], config)
        }

        let secureChannelBootstrap: EventLoopFuture<Channel>?
        let insecureChannelBootstrap: EventLoopFuture<Channel>?

        if useNetwork {
            #if canImport(Network)
            let socketBootstrap = NIOTSListenerBootstrap(
                group: NIOTSEventLoopGroup(loopCount: threads ?? 1)
            )
            // Enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer({ [useNetwork] channel in
                channelInitializer(
                    channel: channel,
                    tls: tls,
                    insecure: insecure,
                    isNIOTS: useNetwork,
                    collectBenchmarks: collectBenchmarks
                )
            })

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            .childChannelOption(
                ChannelOptions.writeBufferWaterMark,
                value: .init(low: 100 * 16384, high: 100 * 100 * 16384)
            )

            // Split this out as a prior step because we want to initiate both binds at once without waiting on either one of them
            secureChannelBootstrap = nil
            insecureChannelBootstrap = insecurePort.map {
                socketBootstrap.bind(host: host, port: $0)
            }
            #else
            throw RunError.inputError("No Network.framework support on Linux")
            #endif
        } else {
            let group = MultiThreadedEventLoopGroup(
                numberOfThreads: threads ?? NIOSingletons.groupLoopCountSuggestion
            )
            let socketBootstrap = ServerBootstrap(group: group)
                // Specify backlog and enable SO_REUSEADDR for the server itself
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

                // Set the handlers that are applied to the accepted Channels
                .childChannelInitializer({ channel in
                    channelInitializer(
                        channel: channel,
                        tls: tls,
                        insecure: insecure,
                        collectBenchmarks: collectBenchmarks
                    )
                })

                // Enable SO_REUSEADDR for the accepted Channels
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                .childChannelOption(
                    ChannelOptions.socketOption(.init(rawValue: SO_SNDBUF)),
                    value: 10 * 1024 * 1024
                )
                .childChannelOption(
                    ChannelOptions.writeBufferWaterMark,
                    value: .init(low: 100 * 16384, high: 100 * 100 * 16384)
                )

            // Split this out as a prior step because we want to initiate both binds at once without waiting on either one of them
            secureChannelBootstrap = port.map { socketBootstrap.bind(host: host, port: $0) }
            insecureChannelBootstrap = insecurePort.map {
                socketBootstrap.bind(host: host, port: $0)
            }
        }

        let secureChannel = try secureChannelBootstrap.map {
            let out = try $0.wait()
            print("Listening on https://\(host):\(port!)")
            return out
        }

        let insecureChannel = try insecureChannelBootstrap.map {
            let out = try $0.wait()
            print("Listening on http://\(host):\(insecurePort!)")
            return out
        }

        let _ = try secureChannel?.closeFuture.wait()
        let _ = try insecureChannel?.closeFuture.wait()
    }
}
