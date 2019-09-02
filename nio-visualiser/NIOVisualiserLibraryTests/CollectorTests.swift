//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIO
import NIOVisualiserLibrary

class CollectorTests: XCTestCase {

    // MARK: - Tests for Inbound Handler
    func testDirectInboundEventIsLoggedWhenDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)

        for event in [
                Event.inbound(.channelActive),
                Event.inbound(.channelInactive),
                Event.inbound(.channelRegistered),
                Event.inbound(.channelUnregistered),
                Event.inbound(.channelReadComplete),
                Event.inbound(.writabilityChanged(isWritable: true)),
                Event.inbound(.writabilityChanged(isWritable: false))
            ] {
            let (c, h, _) = Utils.makeCollector(with: handler)

            c.storeEvent(handlerInfo: h, event: event)

            XCTAssertEqual(1, c.messages.count)

            let expectedMessage = Message(handlerID: handler.id, port: .in, event: event)

            Utils.assertMessageMatches(expected: c.messages.first!, actual: expectedMessage)
        }
    }
    
    func testDirectInboundReadEventIsLoggedWhenDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, _) = Utils.makeCollector(with: handler)

        let event = Event.inbound(.channelRead(data: ()))
        
        c.storeEvent(handlerInfo: h, event: event)

        XCTAssertEqual(1, c.messages.count)
        
        let expectedMessage = Message(handlerID: handler.id, port: .in, event: event)
        
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: expectedMessage,
                                   channelReadMatcher: { $0 is () })
    }

    func testDirectInboundUserInboundEventTriggeredEventIsLoggedWhenDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, _) = Utils.makeCollector(with: handler)

        let event = Event.inbound(.userInboundEventTriggered(event: ()))
        
        c.storeEvent(handlerInfo: h, event: event)

        XCTAssertEqual(1, c.messages.count)
        
        let expectedMessage = Message(handlerID: handler.id, port: .in, event: event)
        
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: expectedMessage,
                                   userInboundEventTriggeredMatcher: { $0 is () })
    }

    func testDirectInboundErrorCaughtEventIsLoggedWhenDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, _) = Utils.makeCollector(with: handler)

        enum MyError: Error, Equatable {
            case expectedError
        }

        let error = MyError.expectedError

        let event = Event.inbound(.errorCaught(error))
        
        c.storeEvent(handlerInfo: h, event: event)
        
        let expectedMessage = Message(handlerID: handler.id, port: .in, event: event)

        XCTAssertEqual(1, c.messages.count)
        
        Utils.assertMessageMatches(expected: c.messages.first!,
                                        actual: expectedMessage,
                                        errorCaughtMatcher: { ($0 as? MyError) == error })
    }

    func testDirectInboundEventIsLoggedWhenNotDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)

        for event in [
            Event.inbound(.channelActive),
            Event.inbound(.channelInactive),
            Event.inbound(.channelRegistered),
            Event.inbound(.channelUnregistered),
            Event.inbound(.channelReadComplete),
            Event.inbound(.writabilityChanged(isWritable: true)),
            Event.inbound(.writabilityChanged(isWritable: false))
            ] {
                let (c, h, t) = Utils.makeCollector(with: handler)

                c.storeEvent(handlerInfo: h, event: event)
                c.storeEvent(handlerInfo: t, event: event)

                XCTAssertEqual(2, c.messages.count)
                Utils.assertMessageMatches(expected: c.messages.first!,
                                           actual: Message(handlerID: handler.id, port: .in, event: event))
                Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                           actual: Message(handlerID: handler.id, port: .out, event: event))
        }
    }

    func testDirectInboundReadEventIsLoggedWhenNotDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, t) = Utils.makeCollector(with: handler)

        let event = Event.inbound(.channelRead(data: ()))
        
        c.storeEvent(handlerInfo: h, event: event)
        c.storeEvent(handlerInfo: t, event: event)

        XCTAssertEqual(2, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   channelReadMatcher: { $0 is () })

        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                   actual: Message(handlerID: handler.id, port: .out, event: event),
                                   channelReadMatcher: { $0 is () })
    }

    func testDirectInboundUserInboundEventTriggeredEventIsLoggedWhenNotDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, t) = Utils.makeCollector(with: handler)
        
        let event = Event.inbound(.userInboundEventTriggered(event: ()))

        c.storeEvent(handlerInfo: h, event: event)
        c.storeEvent(handlerInfo: t, event: event)

        XCTAssertEqual(2, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   userInboundEventTriggeredMatcher: { $0 is () })

        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                   actual: Message(handlerID: handler.id, port: .out, event: event),
                                   userInboundEventTriggeredMatcher: { $0 is () })
    }

    func testDirectInboundErrorCaughtEventIsLoggedWhenNotDroppedByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)
        let (c, h, t) = Utils.makeCollector(with: handler)

        enum MyError: Error, Equatable {
            case expectedError
        }

        let error = MyError.expectedError
        
        let event = Event.inbound(.errorCaught(error))

        c.storeEvent(handlerInfo: h, event: event)
        c.storeEvent(handlerInfo: t, event: event)

        XCTAssertEqual(2, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   errorCaughtMatcher: { ($0 as? MyError) == error })

        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                   actual: Message(handlerID: handler.id, port: .out, event: event),
                                   errorCaughtMatcher: { ($0 as? MyError) == error })
    }

    // MARK: - Outbound Event fired by Inbound Handler
    func testDirectOutboundEventIsLoggedWhenFiredByInboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .inbound)

        // Inbound event received by inbound handler
        for inboundEvent in [
            Event.inbound(.channelActive),
            Event.inbound(.channelInactive),
            Event.inbound(.channelRegistered),
            Event.inbound(.channelUnregistered),
            Event.inbound(.channelReadComplete),
            Event.inbound(.writabilityChanged(isWritable: true)),
            Event.inbound(.writabilityChanged(isWritable: false))
            ] {
                // Outbound event fired by outbound handler
                for outboundEvent in [
                    Event.outbound(.register),
                    Event.outbound(.flush),
                    Event.outbound(.read),
                    Event.outbound(.bind(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
                    Event.outbound(.connect(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
                    Event.outbound(.close(mode: CloseMode.output)),
                    Event.outbound(.close(mode: CloseMode.input)),
                    Event.outbound(.close(mode: CloseMode.all))
                    ] {
                        let (c, h, _) = Utils.makeCollector(with: handler)

                        c.storeEvent(handlerInfo: h, event: inboundEvent)
                        c.storeEvent(handlerInfo: h, event: outboundEvent)

                        XCTAssertEqual(2, c.messages.count)
                        Utils.assertMessageMatches(expected: c.messages.first!,
                                                   actual: Message(handlerID: handler.id, port: .in, event: inboundEvent))
                        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                                   actual: Message(handlerID: handler.id, port: .out, event: outboundEvent))
                }
        }
    }

    //MARK: - Tests for Outbound Handler
    func testDirectOutboundEventIsLoggedWhenDroppedByOutboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)

        for event in [
            Event.outbound(.register),
            Event.outbound(.flush),
            Event.outbound(.read),
            Event.outbound(.bind(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.connect(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.close(mode: CloseMode.output)),
            Event.outbound(.close(mode: CloseMode.input)),
            Event.outbound(.close(mode: CloseMode.all))
            ] {
                let (c, _, t) = Utils.makeCollector(with: handler)

                c.storeEvent(handlerInfo: t, event: event)

                XCTAssertEqual(1, c.messages.count)
                Utils.assertMessageMatches(expected: c.messages.first!,
                                           actual: Message(handlerID: handler.id, port: .in, event: event))
        }
    }

    func testDirectOutboundWriteEventIsLoggedWhenDroppedByHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)
        let (c, _, t) = Utils.makeCollector(with: handler)

        let event = Event.outbound(.write(data: ()))
        
        c.storeEvent(handlerInfo: t, event: event)

        XCTAssertEqual(1, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   writeMatcher: { $0 is () })
    }

    func testDirectOutboundEventIsLoggedWhenNotDroppedByOutboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)

        for event in [
            Event.outbound(.register),
            Event.outbound(.flush),
            Event.outbound(.read),
            Event.outbound(.bind(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.connect(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.close(mode: CloseMode.output)),
            Event.outbound(.close(mode: CloseMode.input)),
            Event.outbound(.close(mode: CloseMode.all))
            ] {
                let (c, h, t) = Utils.makeCollector(with: handler)

                c.storeEvent(handlerInfo: t, event: event)
                c.storeEvent(handlerInfo: h, event: event)

                XCTAssertEqual(2, c.messages.count)
                Utils.assertMessageMatches(expected: c.messages.first!,
                                           actual: Message(handlerID: handler.id, port: .in, event: event))
                Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                           actual: Message(handlerID: handler.id, port: .out, event: event))
        }
    }

    func testDirectOutboundWriteEventIsLoggedWhenNotDroppedByHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)
        let (c, h, t) = Utils.makeCollector(with: handler)

        let event = Event.outbound(.write(data: ()))
        
        c.storeEvent(handlerInfo: t, event: event)
        c.storeEvent(handlerInfo: h, event: event)

        XCTAssertEqual(2, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   writeMatcher: { $0 is () })

        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                   actual: Message(handlerID: handler.id, port: .out, event: event),
                                   writeMatcher: { $0 is () })

    }

    func testDirectOutboundTriggerUserOutboundEventEventIsLoggedWhenNotDroppedByHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)
        let (c, h, t) = Utils.makeCollector(with: handler)

        let event = Event.outbound(.triggerUserOutboundEvent(event: ()))
        
        c.storeEvent(handlerInfo: t, event: event)
        c.storeEvent(handlerInfo: h, event: event)

        XCTAssertEqual(2, c.messages.count)
        Utils.assertMessageMatches(expected: c.messages.first!,
                                   actual: Message(handlerID: handler.id, port: .in, event: event),
                                   triggerUserOutboundEventMatcher: { $0 is () })

        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                   actual: Message(handlerID: handler.id, port: .out, event: event),
                                   triggerUserOutboundEventMatcher: { $0 is () })
    }

    // MARK: - Inbound Event fired by Outbound Handler
    func testDirectInboundEventIsLoggedWhenFiredByOutboundHandler() {
        let handler = ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .outbound)

        // Inbound event received by inbound handler
        for outboundEvent in [
            Event.outbound(.register),
            Event.outbound(.flush),
            Event.outbound(.read),
            Event.outbound(.bind(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.connect(address: try! SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0))),
            Event.outbound(.close(mode: CloseMode.output)),
            Event.outbound(.close(mode: CloseMode.input)),
            Event.outbound(.close(mode: CloseMode.all))
            ] {
                // Outbound event fired by outbound handler
                for inboundEvent in [
                    Event.inbound(.channelActive),
                    Event.inbound(.channelInactive),
                    Event.inbound(.channelRegistered),
                    Event.inbound(.channelUnregistered),
                    Event.inbound(.channelReadComplete),
                    Event.inbound(.writabilityChanged(isWritable: true)),
                    Event.inbound(.writabilityChanged(isWritable: false))
                    ] {
                        let (c, _, t) = Utils.makeCollector(with: handler)

                        c.storeEvent(handlerInfo: t, event: outboundEvent)
                        c.storeEvent(handlerInfo: t, event: inboundEvent)

                        XCTAssertEqual(2, c.messages.count)
                        Utils.assertMessageMatches(expected: c.messages.first!,
                                                   actual: Message(handlerID: handler.id, port: .in, event: outboundEvent))

                        Utils.assertMessageMatches(expected: c.messages.dropFirst(1).first!,
                                                   actual: Message(handlerID: handler.id, port: .out, event: inboundEvent))
                }
        }
    }
}
