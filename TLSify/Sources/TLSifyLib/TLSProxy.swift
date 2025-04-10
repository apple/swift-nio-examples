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

import Logging
import NIOCore
import NIOPosix
import NIOSSL

public final class TLSProxy {
    enum State {
        case waitingToBeActivated
        case connecting(ByteBuffer)
        case connected
        case error(Error)
        case closed
    }
    private var state = State.waitingToBeActivated {
        didSet {
            self.logger.trace("SM new state: \(self.state)")
        }
    }

    private let host: String
    private let port: Int
    private var logger: Logger
    private let sslContext: NIOSSLContext

    public init(host: String, port: Int, sslContext: NIOSSLContext, logger: Logger) {
        self.host = host
        self.port = port
        self.sslContext = sslContext
        self.logger = logger
        self.logger[metadataKey: "side"] = "Source <--[plain text]--> Proxy"

    }

    func illegalTransition(to: String = #function) -> Never {
        preconditionFailure("illegal transition to \(to) in \(self.state)")
    }

    func gotError(_ error: Error) {
        self.logger.warning("unexpected error: \(#function): \(error)")

        switch self.state {
        case .connected, .connecting, .waitingToBeActivated, .closed:
            self.state = .error(error)
        case .error:
            ()
        }
    }

    func connected(
        partnerChannel: Channel,
        myChannel: Channel,
        contextForInitialData: ChannelHandlerContext
    ) {
        self.logger.debug("connected to \(partnerChannel)")

        let bytes: ByteBuffer
        switch self.state {
        case .waitingToBeActivated, .connected:
            self.illegalTransition()
        case .error(let error):
            partnerChannel.pipeline.fireErrorCaught(error)
            myChannel.pipeline.fireErrorCaught(error)
            partnerChannel.close(promise: nil)
            return
        case .closed:
            self.logger.warning("discarding \(partnerChannel) because we're already closed.")
            partnerChannel.close(promise: nil)
            return
        case .connecting(let buffer):
            bytes = buffer
            self.state = .connected
        // fall through
        }

        var partnerLogger = self.logger
        partnerLogger[metadataKey: "side"] = "Proxy <--[TLS]--> Target"
        let myGlue = GlueHandler(logger: self.logger)
        let partnerGlue = GlueHandler(logger: partnerLogger)
        myGlue.partner = partnerGlue
        partnerGlue.partner = myGlue

        assert(partnerChannel.eventLoop === myChannel.eventLoop)

        do {
            try myChannel.pipeline.syncOperations.addHandler(myGlue, position: .after(contextForInitialData.handler))
            try partnerChannel.pipeline.syncOperations.addHandler(partnerGlue)
        } catch {
            self.gotError(error)

            partnerChannel.pipeline.fireErrorCaught(error)
            contextForInitialData.fireErrorCaught(error)
        }
        guard case .connected = self.state else {
            return
        }
        assert(myGlue.context != nil)
        assert(partnerGlue.context != nil)

        if bytes.readableBytes > 0 {
            contextForInitialData.fireChannelRead(self.wrapInboundOut(bytes))
            contextForInitialData.fireChannelReadComplete()
        }
        contextForInitialData.read()
    }

    func connectPartner(eventLoop: EventLoop) -> EventLoopFuture<Channel> {
        self.logger.debug("connecting to \(self.host):\(self.port)")

        return ClientBootstrap(group: eventLoop)
            .channelInitializer { [sslContext, host, logger] channel in
                channel.pipeline.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers(
                        try! NIOSSLClientHandler(context: sslContext, serverHostname: host),
                        CloseOnErrorHandler(logger: logger)
                    )
                }
            }
            .connect(host: self.host, port: self.port)
    }
}

@available(*, unavailable)
extension TLSProxy: Sendable {}

extension TLSProxy: ChannelDuplexHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    public func handlerAdded(context: ChannelHandlerContext) {
        self.logger[metadataKey: "channel"] = "\(context.channel)"

        let isActive = context.channel.isActive
        self.logger.trace("added to Channel", metadata: ["isActive": "\(isActive)"])
        if isActive {
            self.beginConnecting(context: context)
        }
    }

    public func channelActive(context: ChannelHandlerContext) {
        self.logger.trace("Received channelActive")
        self.beginConnecting(context: context)
    }

    private func beginConnecting(context: ChannelHandlerContext) {
        switch self.state {
        case .waitingToBeActivated:
            self.state = .connecting(context.channel.allocator.buffer(capacity: 0))
            self.connectPartner(eventLoop: context.eventLoop).assumeIsolatedUnsafeUnchecked().whenComplete { result in
                switch result {
                case .failure(let error):
                    self.gotError(error)

                    context.fireErrorCaught(error)
                case .success(let channel):
                    self.connected(
                        partnerChannel: channel,
                        myChannel: context.channel,
                        contextForInitialData: context
                    )
                }
            }
        case .connecting, .connected, .error, .closed:
            // Duplicate call, fine. Can happen if channelActive is awkwardly
            // ordered.
            ()
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.state {
        case .connected:
            context.fireChannelRead(data)  // Glue will pick that up and forward to other Channel
        case .connecting(var buffer):
            var incomingBuffer = self.unwrapInboundIn(data)
            if buffer.readableBytes == 0 {
                self.state = .connecting(incomingBuffer)
            } else {
                buffer.writeBuffer(&incomingBuffer)
                self.state = .connecting(buffer)
            }
        case .error, .closed:
            ()  // we can drop this
        case .waitingToBeActivated:
            self.illegalTransition()
        }
    }

    public func read(context: ChannelHandlerContext) {
        switch self.state {
        case .connected:
            context.read()
        case .connecting, .error, .closed:
            ()  // No, let's not read more that we'd need to buffer/drop anyway
        case .waitingToBeActivated:
            self.illegalTransition()
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.logger.debug("Channel inactive")
        defer {
            context.fireChannelInactive()
        }
        switch self.state {
        case .connected, .connecting:
            self.state = .closed
        case .error:
            ()
        case .closed, .waitingToBeActivated:
            self.illegalTransition()
        }
    }
}
