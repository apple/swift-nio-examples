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

import HTTPTypes
import NIOCore
import NIOHTTPTypes

/// A  `ChannelHandler` that provides administrative HTTP endpoints for server management.
/// Currently, it supports a single enpoint that aims to shutdown the server gracefully:
///
/// - `GET /admin/shutdown` - Initiates shutdown via a given callback
///
/// It will only respond to the supported administrative endpoints and return 404 for all other requests.
/// Since it does not forward requests, it should be at the end of a pipeline.
public final class HTTPAdminHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart

    private static let notFoundBody = ByteBuffer(string: "Not Found")

    private static let okBody = ByteBuffer(string: "Initiating shutdown.")

    private var isShuttingDown = false

    private var shutdownCallback: () -> Void

    /// Creates a new HTTP admin handler with the specified shutdown callback.
    ///
    /// - Parameter shutdownCallback: A closure that will be called once when a shutdown request
    ///   is received via the `/admin/shutdown` endpoint.
    public init(shutdownCallback: @escaping () -> Void) {
        self.shutdownCallback = shutdownCallback
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case let .head(request) = self.unwrapInboundIn(data) {
            guard let path = request.path else {
                self.writeSimpleResponse(
                    context: context,
                    status: .notFound,
                    body: HTTPAdminHandler.notFoundBody
                )
                return
            }

            // Parse the path, removing query parameters if present
            var pathComponents = path.utf8.lazy.split(separator: UInt8(ascii: "?"), maxSplits: 1).makeIterator()
            let firstPathComponent = pathComponents.next()!

            // Split the path into components for routing
            var uriComponentIterator:
                LazyMapSequence<LazySequence<[Substring.UTF8View.SubSequence]>.Elements, Substring>.Iterator =
                    firstPathComponent.split(
                        separator: UInt8(ascii: "/"),
                        maxSplits: 3,
                        omittingEmptySubsequences: false
                    ).lazy.map(Substring.init).makeIterator()

            // Route the request based on HTTP method and path components. The only request we handle here is
            // "/admin/shutdown". Other requests will be answered with a 404.
            switch (
                request.method, uriComponentIterator.next(), uriComponentIterator.next(),
                uriComponentIterator.next(), uriComponentIterator.next().flatMap { Int($0) }
            ) {
            case (.post, .some(""), .some("admin"), .some("shutdown"), .none):
                self.writeSimpleResponse(
                    context: context,
                    status: .ok,
                    body: HTTPAdminHandler.okBody
                )

                // Initiate shutdown only once to prevent multiple shutdown calls
                if !self.isShuttingDown {
                    self.shutdownCallback()
                    self.isShuttingDown = true
                }

            default:
                self.writeSimpleResponse(
                    context: context,
                    status: .notFound,
                    body: HTTPAdminHandler.notFoundBody
                )
            }
        }
    }

    private func writeSimpleResponse(
        context: ChannelHandlerContext,
        status: HTTPResponse.Status,
        body: ByteBuffer
    ) {
        let bodyLen = body.readableBytes
        let responseHead = HTTPResponse(
            status: status,
            headerFields: HTTPFields(dictionaryLiteral: (.contentLength, "\(bodyLen)"))
        )
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(body)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}
