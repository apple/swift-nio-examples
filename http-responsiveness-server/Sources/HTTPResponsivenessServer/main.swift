//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// HTTPResponsivenessServer with Performance Benchmarking
//
// This version of HTTPResponsivenessServer includes performance benchmarking
// capabilities. With the flag --collect-benchmarks, it adds a custom handler
// (PerformanceMeasurementHandler) to measure the time taken to process each request.
// This allows you to log or later analyze per-request responsiveness.
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

// MARK: - PerformanceMeasurementHandler
/// A channel handler that measures the elapsed time for processing an HTTP request.
/// It records the time when a request head is received and computes the elapsed time when the request ends.
final class PerformanceMeasurementHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    private var requestStartTime: DispatchTime?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(_):
            // Record start time when receiving the request head.
            requestStartTime = DispatchTime.now()
            context.fireChannelRead(data)
        case .body:
            context.fireChannelRead(data)
        case .end:
            // Calculate elapsed time and log it.
            if let start = requestStartTime {
                let end = DispatchTime.now()
                let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                print("Request processed in \(String(format: "%.2f", elapsedMs)) ms")
            }
            context.fireChannelRead(data)
        }
    }
}

// MARK: - Updated channelInitializer
/// Configures the channel pipeline for the HTTP server. Now takes an extra parameter `collectBenchmarks`.
func channelInitializer(
    channel: Channel,
    tls: ([Int], NIOSSLContext, ByteBuffer)?,
    insecure: ([Int], ByteBuffer)?,
    isNIOTS: Bool = false,
    collectBenchmarks: Bool = false
) -> EventLoopFuture<Void> {
    // Handle the TLS case.
    if let (ports, sslContext, config) = tls, let port = channel.localAddress?.port, ports.contains(port) {
        let handler = NIOSSLServerHandler(context: sslContext)
        do {
            try channel.pipeline.syncOperations.addHandler(handler)
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
        // In the mux configuration, add the performance measurement handler if enabled.
        return configureCommonHTTPTypesServerPipeline(channel) { channel in
            channel.eventLoop.makeCompletedFuture {
                // If benchmarks are to be collected, insert the measurement handler.
                if collectBenchmarks {
                    try channel.pipeline.syncOperations.addHandler(PerformanceMeasurementHandler())
                }
                try channel.pipeline.syncOperations.addHandler(
                    SimpleResponsivenessRequestMux(responsivenessConfigBuffer: config)
                )
            }
        }
    }
    // Handle the insecure case.
    if let (ports, config) = insecure, let port = channel.localAddress?.port, ports.contains(port) {
        return channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
            if collectBenchmarks {
                try channel.pipeline.syncOperations.addHandler(PerformanceMeasurementHandler())
            }
            return try channel.pipeline.syncOperations.addHandlers([
                HTTP1ToHTTPServerCodec(secure: false),
                SimpleResponsivenessRequestMux(responsivenessConfigBuffer: config),
            ])
        }
    }
    return channel.eventLoop.makeFailedFuture(ChannelInitializeError.unrecognizedPort(channel.localAddress?.port))
}

// MARK: - Command-Line Interface for HTTPResponsivenessServer

struct HTTPResponsivenessServer: ParsableCommand {
    @Option(help: "Which host to bind to")
    var host: String

    @Option(help: "Which port to bind to for encrypted connections")
    var port: Int?

    @Option(help: "Which port to bind to for unencrypted connections")
    var insecurePort: Int?

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
    var threads: Int?

    // New flag to enable performance measurement.
    @Flag(help: "Enable performance benchmark collection for each request")
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
            #if canImport(NIOTransportServices)
            let socketBootstrap = NIOTSListenerBootstrap(
                group: NIOTSEventLoopGroup(loopCount: threads ?? 1)
            )
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer({ channel in
                channelInitializer(
                    channel: channel,
                    tls: tls,
                    insecure: insecure,
                    isNIOTS: true,
                    collectBenchmarks: collectBenchmarks
                )
            })
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            insecureChannelBootstrap = insecurePort.map {
                socketBootstrap.bind(host: host, port: $0)
            }
            secureChannelBootstrap = nil
            #else
            throw RunError.inputError("No Network.framework support on Linux")
            #endif
        } else {
            let group = MultiThreadedEventLoopGroup(
                numberOfThreads: threads ?? NIOSingletons.groupLoopCountSuggestion
            )
            let socketBootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer({ channel in
                    channelInitializer(
                        channel: channel,
                        tls: tls,
                        insecure: insecure,
                        collectBenchmarks: collectBenchmarks
                    )
                })
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
            secureChannelBootstrap = port.map { socketBootstrap.bind(host: host, port: $0) }
            insecureChannelBootstrap = insecurePort.map { socketBootstrap.bind(host: host, port: $0) }
        }

        if let secureChannel = secureChannelBootstrap {
            let channel = try secureChannel.wait()
            print("Listening on https://\(host):\(port!)")
            try channel.closeFuture.wait()
        }

        if let insecureChannel = insecureChannelBootstrap {
            let channel = try insecureChannel.wait()
            print("Listening on http://\(host):\(insecurePort!)")
            try channel.closeFuture.wait()
        }
    }
}

// MARK: - Helper Types and Functions

enum RunError: Error {
    case inputError(String)
}

enum ChannelInitializeError: Error {
    case unrecognizedPort(Int?)
}

/// Helper that creates a responsiveness config buffer.
func responsivenessConfigBuffer(scheme: String, host: String, port: Int) throws -> ByteBuffer {
    let cfg = ResponsivenessConfig(
        version: 1,
        urls: ResponsivenessConfigURLs(scheme: scheme, authority: "\(host):\(port)")
    )
    let encoded = try XJSONEncoder().encode(cfg)
    return ByteBuffer(bytes: encoded)
}

// MARK: - Application Entry

@main
struct Main {
    static func main() throws {
        try HTTPResponsivenessServer.main()
    }
}
