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
import Combine
import NIOVisualiserLibrary

class HeuristicsTests: XCTestCase {
    func makeWrite(handler: String, data: Any) -> Message {
        return Message(handlerID: .init(handler),
                       port: .out,
                       event: .outbound(.write(data: data)))
    }
    
    func makeChannelRead(handler: String, data: Any) -> Message {
        return Message(handlerID: .init(handler),
                       port: .in,
                       event: .inbound(.channelRead(data: data)))
    }
        
    func testOnlyOneMessage() {
        let publisher = Publishers.Sequence<[Message], Never>(sequence: [
            self.makeWrite(handler: "A", data: "foo"),
        ])
        
        let expected: [Transmission] = [
            .init(type: .unmatched(.origin(.init("A"))), event: .outbound(.write(data: "foo"))),
        ]
        XCTAssertNoThrow(Utils.assertTransmissionMultipleEq(expected: expected,
                                                            actual: try publisher.transmissionHeuristics().syncCollect(),
                                                            inType: String.self,
                                                            outType: String.self))
    }
    
    func testWriteThenChannelReadDontGetMatched() {
        let publisher = Publishers.Sequence<[Message], Never>(sequence: [
            self.makeWrite(handler: "A", data: "write"),
            self.makeChannelRead(handler: "B", data: 1)
        ])
        
        let expected: [Transmission] = [
            .init(type: .unmatched(.origin(.init("A"))), event: .outbound(.write(data: "write"))),
            .init(type: .unmatched(.destination(.init("B"))), event: .inbound(.channelRead(data: 1))),
        ]
        
        XCTAssertNoThrow(Utils.assertTransmissionMultipleEq(expected: expected,
                                                            actual: try publisher.transmissionHeuristics().syncCollect(),
                                                            inType: Int.self,
                                                            outType: String.self))
    }

}
