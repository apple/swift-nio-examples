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
import Logging
import NIOConcurrencyHelpers

final class GlueHandler: @unchecked Sendable {
    private let lock = Lock()
    var logger: Logger
    var context: Optional<ChannelHandlerContext> = nil
    var partner: Optional<GlueHandler> = nil
    private var pendingRead = false
    
    internal init(logger: Logger) {
        self.logger = logger
    }
}

extension GlueHandler {
    private func partnerWrite(_ data: NIOAny) {
        self.context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        self.context?.flush()
    }

    private func partnerWriteEOF() {
        self.context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        self.context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        self.lock.withLock {
            if self.pendingRead {
                self.pendingRead = false
                self.context?.read()
            }
        }
    }

    private var partnerWritable: Bool {
        self.lock.withLock {
            self.context?.channel.isWritable ?? false
        }
    }
}

extension GlueHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    func handlerAdded(context: ChannelHandlerContext) {
        self.lock.withLock {
            self.logger[metadataKey: "channel"] = "\(context.channel)"
            self.context = context
        }
    }
    
    func handlerRemoved(context: ChannelHandlerContext) {
        self.lock.withLock {
            self.context = nil
            self.partner = nil
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.lock.withLock {
            self.partner?.partnerWrite(data)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.lock.withLock {
            self.partner?.partnerFlush()
            context.fireChannelReadComplete()
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.lock.withLock {
            self.logger.debug("channel inactive")
            self.partner?.partnerCloseFull()
        }
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            // We have read EOF.
            self.lock.withLock {
                self.partner?.partnerWriteEOF()
            }
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
        self.lock.withLock {
            self.partner?.partnerCloseFull()
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            self.lock.withLock {
                self.partner?.partnerBecameWritable()
            }
        }
    }

    func read(context: ChannelHandlerContext) {
        self.lock.withLock {
            if let partner = self.partner, partner.partnerWritable {
                context.read()
            } else {
                self.pendingRead = true
            }
        }
    }
}
