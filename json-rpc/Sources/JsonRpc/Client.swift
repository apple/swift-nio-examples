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

import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

public final class TCPClient: @unchecked Sendable {
    private let lock = NIOLock()
    private var state = State.initializing
    public let group: MultiThreadedEventLoopGroup
    public let config: Config
    private var channel: Channel?

    public init(group: MultiThreadedEventLoopGroup, config: Config = Config()) {
        self.group = group
        self.config = config
        self.channel = nil
        self.state = .initializing
    }

    deinit {
        assert(.disconnected == self.state)
    }

    public func connect(host: String, port: Int) -> EventLoopFuture<TCPClient> {
        self.lock.withLock {
            assert(.initializing == self.state)

            let bootstrap = ClientBootstrap(group: self.group)
                .channelOption(ChannelOptions.socket(.init(SOL_SOCKET), .init(SO_REUSEADDR)), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addTimeoutHandlers(self.config.timeout)
                        try channel.pipeline.syncOperations.addFramingHandlers(framing: self.config.framing)
                        try channel.pipeline.syncOperations.addHandlers([
                            CodableCodec<JSONResponse, JSONRequest>(),
                            Handler(),
                        ])
                    }
                }

            self.state = .connecting("\(host):\(port)")
            return bootstrap.connect(host: host, port: port).flatMap { channel in
                self.lock.withLock {
                    self.channel = channel
                    self.state = .connected
                }
                return channel.eventLoop.makeSucceededFuture(self)
            }
        }
    }

    public func disconnect() -> EventLoopFuture<Void> {
        self.lock.withLock {
            if .connected != self.state {
                return self.group.next().makeFailedFuture(ClientError.notReady)
            }
            guard let channel = self.channel else {
                return self.group.next().makeFailedFuture(ClientError.notReady)
            }
            self.state = .disconnecting
            channel.closeFuture.whenComplete { _ in
                self.lock.withLock {
                    self.state = .disconnected
                }
            }
            channel.close(promise: nil)
            return channel.closeFuture
        }
    }

    public func call(method: String, params: RPCObject) -> EventLoopFuture<Result> {
        self.lock.withLock {
            if .connected != self.state {
                return self.group.next().makeFailedFuture(ClientError.notReady)
            }
            guard let channel = self.channel else {
                return self.group.next().makeFailedFuture(ClientError.notReady)
            }
            let promise: EventLoopPromise<JSONResponse> = channel.eventLoop.makePromise()
            let request = JSONRequest(id: NSUUID().uuidString, method: method, params: JSONObject(params))
            let requestWrapper = JSONRequestWrapper(request: request, promise: promise)
            let future = channel.writeAndFlush(requestWrapper)
            future.cascadeFailure(to: promise)  // if write fails
            return future.flatMap {
                promise.futureResult.map { Result($0) }
            }
        }
    }

    private enum State: Equatable {
        case initializing
        case connecting(String)
        case connected
        case disconnecting
        case disconnected
    }

    public typealias Result = ResultType<RPCObject, Error>

    public struct Error: Swift.Error, Equatable {
        public let kind: Kind
        public let description: String

        init(kind: Kind, description: String) {
            self.kind = kind
            self.description = description
        }

        internal init(_ error: JSONError) {
            self.init(
                kind: JSONErrorCode(rawValue: error.code).map { Kind($0) } ?? .otherServerError,
                description: error.message
            )
        }

        public enum Kind: Sendable {
            case invalidMethod
            case invalidParams
            case invalidRequest
            case invalidServerResponse
            case otherServerError

            internal init(_ code: JSONErrorCode) {
                switch code {
                case .invalidRequest:
                    self = .invalidRequest
                case .methodNotFound:
                    self = .invalidMethod
                case .invalidParams:
                    self = .invalidParams
                case .parseError:
                    self = .invalidServerResponse
                case .internalError, .other:
                    self = .otherServerError
                }
            }
        }
    }

    public struct Config: Sendable {
        public let timeout: TimeAmount
        public let framing: Framing

        public init(timeout: TimeAmount = TimeAmount.seconds(5), framing: Framing = .default) {
            self.timeout = timeout
            self.framing = framing
        }
    }
}

private class Handler: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = JSONResponse
    public typealias OutboundIn = JSONRequestWrapper
    public typealias OutboundOut = JSONRequest

    private var queue = CircularBuffer<(String, EventLoopPromise<JSONResponse>)>()

    // outbound
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let requestWrapper = self.unwrapOutboundIn(data)
        queue.append((requestWrapper.request.id, requestWrapper.promise))
        context.write(wrapOutboundOut(requestWrapper.request), promise: promise)
    }

    // inbound
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if self.queue.isEmpty {
            context.fireChannelRead(data)  // already complete
            return
        }
        let promise = queue.removeFirst().1
        let response = unwrapInboundIn(data)
        promise.succeed(response)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let remoteAddress = context.remoteAddress {
            print("server", remoteAddress, "error", error)
        }
        if self.queue.isEmpty {
            context.fireErrorCaught(error)  // already complete
            return
        }
        let item = queue.removeFirst()
        let requestId = item.0
        let promise = item.1
        switch error {
        case CodecError.requestTooLarge, CodecError.badFraming, CodecError.badJSON:
            promise.succeed(JSONResponse(id: requestId, errorCode: .parseError, error: error))
        default:
            promise.fail(error)
            // close the connection
            context.close(promise: nil)
        }
    }

    public func channelActive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            print("server", remoteAddress, "connected")
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            print("server ", remoteAddress, "disconnected")
        }
        if !self.queue.isEmpty {
            self.errorCaught(context: context, error: ClientError.connectionResetByPeer)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if (event as? IdleStateHandler.IdleStateEvent) == .read {
            self.errorCaught(context: context, error: ClientError.timeout)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

private struct JSONRequestWrapper {
    let request: JSONRequest
    let promise: EventLoopPromise<JSONResponse>
}

internal enum ClientError: Error {
    case notReady
    case cantBind
    case timeout
    case connectionResetByPeer
}

extension ResultType where Value == RPCObject, Error == TCPClient.Error {
    init(_ response: JSONResponse) {
        if let result = response.result {
            self = .success(RPCObject(result))
        } else if let error = response.error {
            self = .failure(TCPClient.Error(error))
        } else {
            self = .failure(TCPClient.Error(kind: .invalidServerResponse, description: "invalid server response"))
        }
    }
}
