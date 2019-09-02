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

import Foundation
import XCTest
import NIOVisualiserLibrary

class Utils {
    
    // Initialises a Collector with a single Channel Handler
    // Returns the Collector along with the head and tail handlers in a 3-tuple
    static func makeCollector(with handler: ChannelHandlerInfo) -> (Collector, ChannelHandlerInfo, ChannelHandlerInfo) {
        let head = ChannelHandlerInfo(id: .init("head"), name: .init("HeadHandler"), type: .head)
        let tail = ChannelHandlerInfo(id: .init("tail"), name: .init("TailHandler"), type: .tail)
        
        let collector = Collector()
        collector.save(handlerInfos: [head, handler, tail])
        return (collector, head, tail)
    }
    
    static func assertMessageMatches(expected: Message,
                                     actual: Message,
                                     file: StaticString = #file,
                                     line: UInt = #line,
                                     channelReadMatcher: ((Any) -> Bool)? = nil,
                                     userInboundEventTriggeredMatcher: ((Any) -> Bool)? = nil,
                                     errorCaughtMatcher: ((Error) -> Bool)? = nil,
                                     writeMatcher: ((Any) -> Bool)? = nil,
                                     triggerUserOutboundEventMatcher: ((Any) -> Bool)? = nil) {
        
        XCTAssertEqual(expected.handlerID, actual.handlerID)
        
        XCTAssertEqual(expected.port, actual.port)
        
        assertEventMatches(expected: expected.event,
                           actual: actual.event,
                           file: file,
                           line: line,
                           channelReadMatcher: channelReadMatcher,
                           userInboundEventTriggeredMatcher: userInboundEventTriggeredMatcher,
                           errorCaughtMatcher: errorCaughtMatcher,
                           writeMatcher: writeMatcher,
                           triggerUserOutboundEventMatcher: triggerUserOutboundEventMatcher)
    }
    
    static func assertTransmissionMultipleEq<In: Equatable, Out: Equatable>(expected: [Transmission],
                                                                            actual: [Transmission],
                                                                            inType: In.Type = In.self,
                                                                            outType: Out.Type = Out.self,
                                                                            file: StaticString = #file,
                                                                            line: UInt = #line) {
        Utils.assertEventMatchesMultipleEq(expected: expected.map { $0.event },
                                           actual: actual.map { $0.event },
                                           inType: inType, outType: outType, file: file, line: line)
        XCTAssertNoThrow(XCTAssertEqual(expected.map { $0.type },
                                        actual.map { $0.type }), file: file, line: line)
    }
    
        
    static func assertTransmissionMatches(expected: Transmission,
                                          actual: Transmission,
                                          file: StaticString = #file,
                                          line: UInt = #line,
                                          channelReadMatcher: ((Any) -> Bool)? = nil,
                                          userInboundEventTriggeredMatcher: ((Any) -> Bool)? = nil,
                                          errorCaughtMatcher: ((Error) -> Bool)? = nil,
                                          writeMatcher: ((Any) -> Bool)? = nil,
                                          triggerUserOutboundEventMatcher: ((Any) -> Bool)? = nil) {
        
        XCTAssertEqual(expected.type, actual.type)
        
        assertEventMatches(expected: expected.event,
                           actual: actual.event,
                           file: file,
                           line: line,
                           channelReadMatcher: channelReadMatcher,
                           userInboundEventTriggeredMatcher: userInboundEventTriggeredMatcher,
                           errorCaughtMatcher: errorCaughtMatcher,
                           writeMatcher: writeMatcher,
                           triggerUserOutboundEventMatcher: triggerUserOutboundEventMatcher)
    }
    
    static func assertEventMatchesMultipleEq<In: Equatable, Out: Equatable>(expected: [Event],
                                                                            actual: [Event],
                                                                            inType: In.Type = In.self,
                                                                            outType: Out.Type = Out.self,
                                                                            file: StaticString = #file,
                                                                            line: UInt = #line) {
        XCTAssertEqual(expected.count, actual.count, file: file, line: line)
        zip(expected, actual).forEach {
            Utils.assertEventMatchesEq(expected: $0.0, actual: $0.1, inType: In.self, outType: Out.self, file: file, line: line)
        }
    }
    
    static func assertEventMatchesEq<In: Equatable, Out: Equatable>(expected: Event,
                                                                    actual: Event,
                                                                    inType: In.Type = In.self,
                                                                    outType: Out.Type = Out.self,
                                                                    file: StaticString = #file,
                                                                    line: UInt = #line) {
        switch expected {
        case .inbound(.channelRead(data: let value)):
            Utils.assertEventMatches(expected: expected, actual: actual, file: file, line: line, channelReadMatcher:  {
                guard let value = value as? In else {
                    return false
                }
                guard let other = $0 as? In else {
                    return false
                }
                return other == value
            })
        case .outbound(.write(data: let value)):
            Utils.assertEventMatches(expected: expected, actual: actual, file: file, line: line, writeMatcher:  {
                guard let value = value as? Out else {
                    return false
                }
                guard let other = $0 as? Out else {
                    return false
                }
                return other == value
            })

        default:
            Utils.assertEventMatches(expected: expected, actual: actual)
        }
    }
    
    static func assertEventMatches(expected: Event,
                                   actual: Event,
                                   file: StaticString = #file,
                                   line: UInt = #line,
                                   channelReadMatcher: ((Any) -> Bool)? = nil,
                                   userInboundEventTriggeredMatcher: ((Any) -> Bool)? = nil,
                                   errorCaughtMatcher: ((Error) -> Bool)? = nil,
                                   writeMatcher: ((Any) -> Bool)? = nil,
                                   triggerUserOutboundEventMatcher: ((Any) -> Bool)? = nil) {
        
        switch (expected, actual) {
        case (.inbound(.channelRegistered), .inbound(.channelRegistered)),
             (.inbound(.channelUnregistered), .inbound(.channelUnregistered)),
             (.inbound(.channelActive), .inbound(.channelActive)),
             (.inbound(.channelInactive), .inbound(.channelInactive)),
             (.inbound(.channelReadComplete), .inbound(.channelReadComplete)),
             (.inbound(.writabilityChanged(isWritable: true)), .inbound(.writabilityChanged(isWritable: true))),
             (.inbound(.writabilityChanged(isWritable: false)), .inbound(.writabilityChanged(isWritable: false))):
            ()
        case (.inbound(.channelRead(_)), .inbound(.channelRead(_))):
            // Check if channel read matcher was passed in
            if let channelReadMatcher = channelReadMatcher {
                switch actual {
                case .inbound(.channelRead(data: let data)):
                    if !channelReadMatcher(data) {
                        XCTFail("message is the right kind but doesn't match", file: file, line: line)
                    }
                default:
                    XCTFail("expected message to be .inbound(.read(...)) but found \(actual)", file: file, line: line)
                }
            } else {
                XCTFail("please use channelReadMatcher to validate .inbound(.read(...))", file: file, line: line)
            }
        case (.inbound(.userInboundEventTriggered(_)), .inbound(.userInboundEventTriggered(_))):
            // Check if user inbound event triggered matcher was passed in
            if let userInboundEventTriggeredMatcher = userInboundEventTriggeredMatcher {
                switch actual {
                case .inbound(.userInboundEventTriggered(event: let event)):
                    if !userInboundEventTriggeredMatcher(event) {
                        XCTFail("message is the right kind but doesn't match", file: file, line: line)
                    }
                default:
                    XCTFail("expected message to be .inbound(.userInboundEventTriggered(...)) but found \(actual)", file: file, line: line)
                }
            } else {
                XCTFail("please use userInboundEventTriggeredMatcher to validate .inbound(.userInboundEventTriggered(...))", file: file, line: line)
            }
        case (.inbound(.errorCaught(_)), .inbound(.errorCaught(_))):
            // Check if error caught matcher was passed in
            if let errorCaughtMatcher = errorCaughtMatcher {
                switch actual {
                case .inbound(.errorCaught(let error)):
                    if !errorCaughtMatcher(error) {
                        XCTFail("message is the right kind but doesn't match", file: file, line: line)
                    }
                default:
                    XCTFail("expected message to be .inbound(.errorCaught(...)) but found \(actual)", file: file, line: line)
                }
            } else {
                XCTFail("please use errorCaughtMatcher to validate .inbound(.errorCaught(...))", file: file, line: line)
            }
        case (.outbound(.register), .outbound(.register)),
             (.outbound(.flush), .outbound(.flush)),
             (.outbound(.read), .outbound(.read)):
            ()
        case (.outbound(.bind(address: let lhs)), .outbound(.bind(address: let rhs))),
             (.outbound(.connect(address: let lhs)), .outbound(.connect(address: let rhs))):
            XCTAssertEqual(lhs, rhs, "Expected SocketAddress: \(lhs) does not match actual: \(rhs)", file: file, line: line)
        case (.outbound(.close(mode: let lhs)), .outbound(.close(mode: let rhs))):
            XCTAssertEqual(lhs, rhs, "Expected CloseMode: \(lhs) does not match actual: \(rhs)", file: file, line: line)
        case (.outbound(.triggerUserOutboundEvent(_)), .outbound(.triggerUserOutboundEvent(_))):
            // Check if write matcher was passed in
            if let triggerUserOutboundEventMatcher = triggerUserOutboundEventMatcher {
                switch actual {
                case .outbound(.triggerUserOutboundEvent(event: let event)):
                    if !triggerUserOutboundEventMatcher(event) {
                        XCTFail("message is the right kind but doesn't match", file: file, line: line)
                    }
                default:
                    XCTFail("expected message to be .outbound(.triggerUserOutboundEvent(...)) but found \(actual)", file: file, line: line)
                }
            } else {
                XCTFail("please use triggerUserOutboundEventMatcher to validate .outbound(.triggerUserOutboundEvent(...))", file: file, line: line)
            }
        case (.outbound(.write(_)), .outbound(.write(_))):
            // Check if write matcher was passed in
            if let writeMatcher = writeMatcher {
                switch actual {
                case .outbound(.write(data: let data)) where writeMatcher(data):
                    if !writeMatcher(data) {
                        XCTFail("message is the right kind but doesn't match", file: file, line: line)
                    }
                default:
                    XCTFail("expected message to be .outbound(.write(...)) but found \(actual)", file: file, line: line)
                }
            } else {
                XCTFail("please use writeMatcher to validate .outbound(.write(...))", file: file, line: line)
            }
        default: XCTFail("test case event type match failed, expected: \(expected); actual: \(actual)", file: file, line: line)
        }
        
    }
}


