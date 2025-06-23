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
/*
 * Copyright 2024, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import NIOCore
import NIOHTTP2

/// A `ChannelHandler` which manages the HTTP/2 connection shutdown.
///
/// This handler is responsible for managing several aspects of the connection, including:
/// 1. Handling the graceful close of connections. When gracefully closing a connection the server
///    sends a GOAWAY frame with the last stream ID set to the maximum stream ID allowed followed by
///    a PING frame. On receipt of the PING frame the server sends another GOAWAY frame with the
///    highest ID of all streams which have been opened. After this, the handler closes the
///    connection once all streams are closed.
/// 2. Enforcing that graceful shutdown doesn't exceed a configured limit (if configured).
/// 3. Gracefully closing the connection once it reaches the maximum configured age (if configured).
/// 4. Gracefully closing the connection once it has been idle for a given period of time (if configured).
///
final class ServerConnectionManagementHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame
    typealias OutboundIn = HTTP2Frame
    typealias OutboundOut = HTTP2Frame

    /// The `EventLoop` of the `Channel` this handler exists in.
    private let eventLoop: any EventLoop

    /// The timer used to gracefully close idle connections.
    private var maxIdleTimerHandler: Timer<MaxIdleTimerHandlerView>?

    /// The timer used to gracefully close old connections.
    private var maxAgeTimerHandler: Timer<MaxAgeTimerHandlerView>?

    /// The timer used to forcefully close a connection during a graceful close.
    /// The timer starts after the second GOAWAY frame has been sent.
    private var maxGraceTimerHandler: Timer<MaxGraceTimerHandlerView>?

    /// Whether a flush is pending.
    private var flushPending: Bool

    /// Whether `channelRead` has been called and `channelReadComplete` hasn't yet been called.
    /// Resets once `channelReadComplete` returns.
    private var inReadLoop: Bool

    /// The context of the channel this handler is in.
    private var context: ChannelHandlerContext?

    /// The current state of the connection.
    private var state: StateMachine

    /// The clock.
    private let clock: Clock

    /// A clock providing the current time.
    ///
    /// This is necessary for testing where a manual clock can be used and advanced from the test.
    /// While NIO's `EmbeddedEventLoop` provides control over its view of time (and therefore any
    /// events scheduled on it) it doesn't offer a way to get the current time. This is usually done
    /// via `NIODeadline`.
    enum Clock {
        case nio
        case manual(Manual)

        func now() -> NIODeadline {
            switch self {
            case .nio:
                return .now()
            case .manual(let clock):
                return clock.time
            }
        }

        final class Manual {
            private(set) var time: NIODeadline

            init() {
                self.time = .uptimeNanoseconds(0)
            }

            func advance(by amount: TimeAmount) {
                self.time = self.time + amount
            }
        }
    }

    /// Creates a new handler which manages the lifecycle of a connection.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` of the `Channel` this handler is placed in.
    ///   - maxIdleTime: The maximum amount time a connection may be idle for before being closed.
    ///   - maxAge: The maximum amount of time a connection may exist before being gracefully closed.
    ///   - maxGraceTime: The maximum amount of time that the connection has to close gracefully.
    ///   - clock: A clock providing the current time.
    init(
        eventLoop: any EventLoop,
        maxIdleTime: TimeAmount?,
        maxAge: TimeAmount?,
        maxGraceTime: TimeAmount?,
        clock: Clock = .nio
    ) {
        self.eventLoop = eventLoop

        // Generate a random value to be used as keep alive ping data.
        let pingData = UInt64.random(in: .min ... .max)

        self.state = StateMachine(goAwayPingData: HTTP2PingData(withInteger: ~pingData))

        self.flushPending = false
        self.inReadLoop = false
        self.clock = clock

        if let maxIdleTime {
            self.maxIdleTimerHandler = Timer(
                eventLoop: eventLoop,
                duration: maxIdleTime,
                repeating: false,
                handler: MaxIdleTimerHandlerView(self)
            )
        }
        if let maxAge {
            self.maxAgeTimerHandler = Timer(
                eventLoop: eventLoop,
                duration: maxAge,
                repeating: false,
                handler: MaxAgeTimerHandlerView(self)
            )
        }
        if let maxGraceTime {
            self.maxGraceTimerHandler = Timer(
                eventLoop: eventLoop,
                duration: maxGraceTime,
                repeating: false,
                handler: MaxGraceTimerHandlerView(self)
            )
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        assert(context.eventLoop === self.eventLoop)
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    func channelActive(context: ChannelHandlerContext) {
        self.maxAgeTimerHandler?.start()
        self.maxIdleTimerHandler?.start()
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.maxIdleTimerHandler?.cancel()
        self.maxAgeTimerHandler = nil

        self.maxAgeTimerHandler?.cancel()
        self.maxAgeTimerHandler = nil

        self.maxGraceTimerHandler?.cancel()
        self.maxGraceTimerHandler = nil

        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelShouldQuiesceEvent:
            self.initiateGracefulShutdown()

        default:
            ()
        }

        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if self.closeConnectionOnError(error) {
            context.close(mode: .all, promise: nil)
        }
    }

    private func closeConnectionOnError(_ error: any Error) -> Bool {
        switch error {
        case is NIOHTTP2Errors.NoSuchStream:
            // Only close the connection if it's not already closing (as this is the state in which the
            // error can be safely ignored).
            return !self.state.isClosing

        case is NIOHTTP2Errors.StreamError:
            // Stream errors occur in streams, they are only propagated down the connection channel
            // pipeline for vestigial reasons.
            return false

        default:
            // Everything else is considered terminal for the connection until we know better.
            return true
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.inReadLoop = true

        let frame = self.unwrapInboundIn(data)
        switch frame.payload {
        case .ping(let data, let ack):
            // Only interested in PING ACK frames, ignore the rest.
            if ack {
                self.handlePingAck(context: context, data: data)
            }

        default:
            ()  // Only interested in PING frames, ignore the rest.
        }

        context.fireChannelRead(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        while self.flushPending {
            self.flushPending = false
            context.flush()
        }

        self.inReadLoop = false

        context.fireChannelReadComplete()
    }

    func flush(context: ChannelHandlerContext) {
        self.maybeFlush(context: context)
    }
}

// Timer handler views.
extension ServerConnectionManagementHandler {
    struct MaxIdleTimerHandlerView: @unchecked Sendable, NIOScheduledCallbackHandler {
        private let handler: ServerConnectionManagementHandler

        init(_ handler: ServerConnectionManagementHandler) {
            self.handler = handler
        }

        func handleScheduledCallback(eventLoop: some EventLoop) {
            self.handler.eventLoop.assertInEventLoop()
            self.handler.initiateGracefulShutdown()
        }
    }

    struct MaxAgeTimerHandlerView: @unchecked Sendable, NIOScheduledCallbackHandler {
        private let handler: ServerConnectionManagementHandler

        init(_ handler: ServerConnectionManagementHandler) {
            self.handler = handler
        }

        func handleScheduledCallback(eventLoop: some EventLoop) {
            self.handler.eventLoop.assertInEventLoop()
            self.handler.initiateGracefulShutdown()
        }
    }

    struct MaxGraceTimerHandlerView: @unchecked Sendable, NIOScheduledCallbackHandler {
        private let handler: ServerConnectionManagementHandler

        init(_ handler: ServerConnectionManagementHandler) {
            self.handler = handler
        }

        func handleScheduledCallback(eventLoop: some EventLoop) {
            self.handler.eventLoop.assertInEventLoop()
            self.handler.context?.close(promise: nil)
        }
    }
}

extension ServerConnectionManagementHandler {
    struct HTTP2StreamDelegate: @unchecked Sendable, NIOHTTP2StreamDelegate {
        // @unchecked is okay: the only methods do the appropriate event-loop dance.

        private let handler: ServerConnectionManagementHandler

        init(_ handler: ServerConnectionManagementHandler) {
            self.handler = handler
        }

        func streamCreated(_ id: HTTP2StreamID, channel: any Channel) {
            if self.handler.eventLoop.inEventLoop {
                self.handler._streamCreated(id, channel: channel)
            } else {
                self.handler.eventLoop.execute {
                    self.handler._streamCreated(id, channel: channel)
                }
            }
        }

        func streamClosed(_ id: HTTP2StreamID, channel: any Channel) {
            if self.handler.eventLoop.inEventLoop {
                self.handler._streamClosed(id, channel: channel)
            } else {
                self.handler.eventLoop.execute {
                    self.handler._streamClosed(id, channel: channel)
                }
            }
        }
    }

    var http2StreamDelegate: HTTP2StreamDelegate {
        HTTP2StreamDelegate(self)
    }

    private func _streamCreated(_ id: HTTP2StreamID, channel: any Channel) {
        // The connection isn't idle if a stream is open.
        self.maxIdleTimerHandler?.cancel()
        self.state.streamOpened(id)
    }

    private func _streamClosed(_ id: HTTP2StreamID, channel: any Channel) {
        guard let context = self.context else { return }

        switch self.state.streamClosed(id) {
        case .startIdleTimer:
            self.maxIdleTimerHandler?.start()
        case .close:
            // Defer closing until the next tick of the event loop.
            //
            // This point is reached because the server is shutting down gracefully and the stream count
            // has dropped to zero, meaning the connection is no longer required and can be closed.
            // However, the stream would've been closed by writing and flushing a frame with end stream
            // set. These are two distinct events in the channel pipeline. The HTTP/2 handler updates the
            // state machine when a frame is written, which in this case results in the stream closed
            // event which we're reacting to here.
            //
            // Importantly the HTTP/2 handler hasn't yet seen the flush event, so the bytes of the frame
            // with end-stream set - and potentially some other frames - are sitting in a buffer in the
            // HTTP/2 handler. If we close on this event loop tick then those frames will be dropped.
            // Delaying the close by a loop tick will allow the flush to happen before the close.
            let loopBound = NIOLoopBound(context, eventLoop: context.eventLoop)
            context.eventLoop.execute {
                loopBound.value.close(mode: .all, promise: nil)
            }

        case .none:
            ()
        }
    }
}

extension ServerConnectionManagementHandler {
    private func maybeFlush(context: ChannelHandlerContext) {
        if self.inReadLoop {
            self.flushPending = true
        } else {
            context.flush()
        }
    }

    private func initiateGracefulShutdown() {
        guard let context = self.context else { return }
        context.eventLoop.assertInEventLoop()

        // Cancel any timers if initiating shutdown.
        self.maxIdleTimerHandler?.cancel()
        self.maxAgeTimerHandler?.cancel()

        switch self.state.startGracefulShutdown() {
        case .sendGoAwayAndPing(let pingData):
            // There's a time window between the server sending a GOAWAY frame and the client receiving
            // it. During this time the client may open new streams as it doesn't yet know about the
            // GOAWAY frame.
            //
            // The server therefore sends a GOAWAY with the last stream ID set to the maximum stream ID
            // and follows it with a PING frame. When the server receives the ack for the PING frame it
            // knows that the client has received the initial GOAWAY frame and that no more streams may
            // be opened. The server can then send an additional GOAWAY frame with a more representative
            // last stream ID.
            let goAway = HTTP2Frame(
                streamID: .rootStream,
                payload: .goAway(
                    lastStreamID: .maxID,
                    errorCode: .noError,
                    opaqueData: nil
                )
            )

            let ping = HTTP2Frame(streamID: .rootStream, payload: .ping(pingData, ack: false))

            context.write(self.wrapOutboundOut(goAway), promise: nil)
            context.write(self.wrapOutboundOut(ping), promise: nil)
            self.maybeFlush(context: context)

        case .none:
            ()  // Already shutting down.
        }
    }

    private func handlePingAck(context: ChannelHandlerContext, data: HTTP2PingData) {
        switch self.state.receivedPingAck(data: data) {
        case .sendGoAway(let streamID, let close):
            let goAway = HTTP2Frame(
                streamID: .rootStream,
                payload: .goAway(lastStreamID: streamID, errorCode: .noError, opaqueData: nil)
            )

            context.write(self.wrapOutboundOut(goAway), promise: nil)
            self.maybeFlush(context: context)

            if close {
                context.close(promise: nil)
            } else {
                // RPCs may have a grace period for finishing once the second GOAWAY frame has finished.
                // If this is set close the connection abruptly once the grace period passes.
                self.maxGraceTimerHandler?.start()
            }

        case .none:
            ()
        }
    }
}
