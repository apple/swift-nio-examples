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
import NIOVisualiserLibrary

class FilterLogicTests: XCTestCase {
    
    // MARK: -- Empty Filter Test
    func testWorksWithEmptyFilters() {
        XCTAssertTrue(shouldKeepEvent([], event: .inbound(.channelActive)))
    }
    
    // MARK: -- Single Filter Tests
    func testSingleChannelRegisteredFilterReturnsFalseWithChannelRegisteredEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelRegistered))], event: .inbound(.channelRegistered)))
    }
    
    func testSingleChannelUnregisteredFilterReturnsFalseWithChannelUnregisteredEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelUnregistered))], event: .inbound(.channelUnregistered)))
    }
    
    func testSingleChannelActiveFilterReturnsFalseWithChannelActiveEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelActive))], event: .inbound(.channelActive)))
    }
    
    func testSingleChannelInactiveFilterReturnsFalseWithChannelInactiveEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelInactive))], event: .inbound(.channelInactive)))
    }
    
    func testSingleChannelReadFilterReturnsFalseWithChannelReadEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelRead))], event: .inbound(.channelRead(data: ""))))
    }
    
    func testSingleChannelReadCompleteFilterReturnsFalseWithChannelReadCompleteEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.channelReadComplete))], event: .inbound(.channelReadComplete)))
    }
    
    func testSingleWritabilityChangedFilterReturnsFalseWithWritabilityChangedEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.writabilityChanged))], event: .inbound(.writabilityChanged(isWritable: true))))
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.writabilityChanged))], event: .inbound(.writabilityChanged(isWritable: false))))
    }
    
    func testSingleErrorCaughtFilterReturnsFalseWithErrorCaughtEvent() {
        enum MyError : Error {
            case error
        }
        XCTAssertFalse(shouldKeepEvent([(false, .inbound(.errorCaught))], event: .inbound(.errorCaught(MyError.error))))
    }
    
    func testSingleRegisterFilterReturnsFalseWithRegisterEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.register))], event: .outbound(.register)))
    }
    
    func testSingleBindFilterReturnsFalseWithBindEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.bind))], event: .outbound(.bind(address: try! .init(ipAddress: "1.2.3.4", port: 0)))))
    }
    
    func testSingleConnectFilterReturnsFalseWithConnectEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.connect))], event: .outbound(.connect(address: try! .init(ipAddress: "1.2.3.4", port: 0)))))
    }
    
    func testSingleWriteFilterReturnsFalseWithWriteEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.write))], event: .outbound(.write(data: ""))))
    }
    
    func testSingleFlushFilterReturnsFalseWithFlushEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.flush))], event: .outbound(.flush)))
    }
    
    func testSingleReadFilterReturnsFalseWithReadEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.read))], event: .outbound(.read)))
    }
    
    func testSingleCloseFilterReturnsFalseWithCloseEvent() {
        for event in [
            Event.outbound(.close(mode: .all)),
            Event.outbound(.close(mode: .input)),
            Event.outbound(.close(mode: .output))
            ] {
              XCTAssertFalse(shouldKeepEvent([(false, .outbound(.close))], event: event))
        }
    }
    
    func testSingleTriggerUserOutboundEventFilterReturnsFalseWithTriggerUserOutboundEventEvent() {
        XCTAssertFalse(shouldKeepEvent([(false, .outbound(.triggerUserOutboundEvent))], event: .outbound(.triggerUserOutboundEvent(event: ""))))
    }
    
    // MARK: -- Multiple Filter Tests
    
    func testWeCanFilterOutChannelRegisteredWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelRegistered)),
        ], event: .inbound(.channelRegistered)))
    }
    
    func testWeCanFilterOutChannelUnregisteredWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelUnregistered)),
        ], event: .inbound(.channelUnregistered)))
    }
    
    func testWeCanFilterOutChannelActiveWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelActive)),
        ], event: .inbound(.channelActive)))
    }
    
    func testWeCanFilterOutChannelInactiveWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelInactive)),
        ], event: .inbound(.channelInactive)))
    }
    
    func testWeCanFilterOutChannelReadWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelRead)),
        ], event: .inbound(.channelRead(data: ""))))
    }
    
    func testWeCanFilterOutChannelReadCompleteWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelReadComplete)),
        ], event: .inbound(.channelReadComplete)))
    }
    
    func testWeCanFilterOutChannelWritabilityChangedWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.writabilityChanged)),
        ], event: .inbound(.writabilityChanged(isWritable: true))))
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.writabilityChanged)),
        ], event: .inbound(.writabilityChanged(isWritable: false))))
    }
    
    func testWeCanFilterOutUserInboundEventTriggeredWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.userInboundEventTriggered)),
        ], event: .inbound(.userInboundEventTriggered(event: ""))))
    }
    
    func testWeCanFilterOutErrorCaughtWithMultipleFilters() {
        enum MyError : Error {
            case error
        }
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.errorCaught)),
        ], event: .inbound(.errorCaught(MyError.error))))
    }
    
    func testWeCanFilterOutRegisterWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.register)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.register)))
    }
    
    func testWeCanFilterOutBindWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.bind)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.bind(address: try! .init(ipAddress: "1.2.3.4", port: 0)))))
    }
    
    func testWeCanFilterOutConnectWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.connect)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.connect(address: try! .init(ipAddress: "1.2.3.4", port: 0)))))
    }
    
    func testWeCanFilterOutWriteWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.write)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.write(data: ""))))
    }
    
    func testWeCanFilterOutFlushWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.flush)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.flush)))
    }
    
    func testWeCanFilterOutReadWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.read)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.read)))
    }
    
    func testWeCanFilterOutCloseWithMultipleFilters() {
        for event in [
            Event.outbound(.close(mode: .all)),
            Event.outbound(.close(mode: .input)),
            Event.outbound(.close(mode: .output))
            ] {
                XCTAssertFalse(shouldKeepEvent([
                    (false, .outbound(.close)),
                    (false, .inbound(.channelRead)),
                ], event: event))
        }
    }
    
    func testWeCanFilterOutTriggerUserOutboundEventWithMultipleFilters() {
        XCTAssertFalse(shouldKeepEvent([
            (false, .outbound(.triggerUserOutboundEvent)),
            (false, .inbound(.channelRead)),
        ], event: .outbound(.triggerUserOutboundEvent(event: ""))))
    }
}
