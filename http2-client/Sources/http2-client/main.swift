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

import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import Foundation

/// Fires off a GET request when our stream is active and collects all response parts into a promise.
///
/// - warning: This will read the whole response into memory and delivers it into a promise.
final class SendRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart
    
    private let responseReceivedPromise: EventLoopPromise<[HTTPClientResponsePart]>
    private var responsePartAccumulator: [HTTPClientResponsePart] = []
    private let host: String
    private let compoundRequest: HTTPRequest
    
    init(host: String, request: HTTPRequest, responseReceivedPromise: EventLoopPromise<[HTTPClientResponsePart]>) {
        self.responseReceivedPromise = responseReceivedPromise
        self.host = host
        self.compoundRequest = request
    }
    
    func channelActive(context: ChannelHandlerContext) {
        assert(context.channel.parent!.isActive)
        var headers = HTTPHeaders(self.compoundRequest.headers)
        headers.add(name: "Host", value: self.host)
        var reqHead = HTTPRequestHead(version: self.compoundRequest.version,
                                      method: self.compoundRequest.method,
                                      uri: self.compoundRequest.target)
        reqHead.headers = headers
        if let body = self.compoundRequest.body {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.write(self.wrapOutboundOut(.head(reqHead)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(self.compoundRequest.trailers.map(HTTPHeaders.init))), promise: nil)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let resPart = self.unwrapInboundIn(data)
        self.responsePartAccumulator.append(resPart)
        if case .end = resPart {
            self.responseReceivedPromise.succeed(self.responsePartAccumulator)
        }
    }
}

/// Collects any errors in the root stream, forwards them to a promise and closes the whole network connection.
final class CollectErrorsAndCloseStreamHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    private let responseReceivedPromise: EventLoopPromise<[HTTPClientResponsePart]>
    
    init(responseReceivedPromise: EventLoopPromise<[HTTPClientResponsePart]>) {
        self.responseReceivedPromise = responseReceivedPromise
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.responseReceivedPromise.fail(error)
        context.close(promise: nil)
    }
}

let sslContext = try NIOSSLContext(configuration: TLSConfiguration.forClient(applicationProtocols: ["h2"]))

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let responseReceivedPromise = group.next().makePromise(of: [HTTPClientResponsePart].self)
var verbose = false
var args = ArraySlice(CommandLine.arguments)

func usage() {
    print("Usage: http2-client [-v] https://host:port/path")
    print()
    print("OPTIONS:")
    print("     -v: verbose operation (print response code, headers, etc.)")
}

if case .some(let arg) = args.dropFirst().first, arg.starts(with: "-") {
    switch arg {
    case "-v":
        verbose = true
        args = args.dropFirst()
    default:
        usage()
        exit(1)
    }
}

guard let url = args.dropFirst().first.flatMap(URL.init(string:)) else {
    usage()
    exit(1)
}
guard let host = url.host else {
    print("ERROR: URL '\(url)' does not have a hostname which is required")
    exit(1)
}
guard url.scheme == "https" else {
    print("ERROR: URL '\(url)' is not https but that's required")
    exit(1)
}

let uri = url.absoluteURL.path == "" ? "/" : url.absoluteURL.path
let port = url.port ?? 443
let bootstrap = ClientBootstrap(group: group)
    .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
    .channelInitializer { channel in
        channel.pipeline.addHandler(try! NIOSSLClientHandler(context: sslContext, serverHostname: host)).flatMap {
            channel.configureHTTP2Pipeline(mode: .client) { (channel, id) -> EventLoopFuture<Void> in
                print("channel \(channel) open with id \(id)")
                return channel.eventLoop.makeSucceededFuture(())
            }
        }.flatMap { http2Multiplexer -> EventLoopFuture<Void> in
            func requestStreamInitializer(channel: Channel, streamID: HTTP2StreamID) -> EventLoopFuture<Void> {
                return channel.pipeline.addHandlers([HTTP2ToHTTP1ClientCodec(streamID: streamID, httpProtocol: .https),
                                                     SendRequestHandler(host: host,
                                                                        request: .init(method: .GET,
                                                                                       target: uri,
                                                                                       version: .init(major: 2, minor: 0),
                                                                                       headers: [],
                                                                                       body: nil,
                                                                                       trailers: nil),
                                                                        responseReceivedPromise: responseReceivedPromise)],
                                                    position: .last)
            }

            let errorHandler = CollectErrorsAndCloseStreamHandler(responseReceivedPromise: responseReceivedPromise)
            return  channel.pipeline.addHandler(errorHandler).map {
                http2Multiplexer.createStreamChannel(promise: nil, requestStreamInitializer)
            }
        }
    }

defer {
    try! group.syncShutdownGracefully()
}

do {
    let channel = try bootstrap.connect(host: host, port: port).wait()
    if verbose {
        print("* Connected to \(host) (\(channel.remoteAddress!)")
    }
    try! responseReceivedPromise.futureResult.map { responseParts in
        for part in responseParts {
            switch part {
            case .head(let resHead):
                if verbose {
                    print("< HTTP/\(resHead.version.major).\(resHead.version.minor) \(resHead.status.code)")
                    for header in resHead.headers {
                        print("< \(header.name): \(header.value)")
                    }
                }
            case .body(let buffer):
                let written = buffer.withUnsafeReadableBytes { ptr in
                    write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
                }
                precondition(written == buffer.readableBytes) // technically, write could write short ;)
            case .end(_):
                if verbose {
                    print("* Response fully received")
                }
            }
        }
    }.recover { error in
        print("ERROR: \(error)")
        exit(1)
    }.wait()
    exit(0)
} catch {
    print("ERROR: \(error)")
}
