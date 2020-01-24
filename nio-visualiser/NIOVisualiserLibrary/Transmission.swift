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
import NIOAutomation

public struct Transmission: CustomStringConvertible {
    
    public var description: String {
        var string = "Transmission: "
        
        switch self.type {
        case .matched(origin: let originID, destination: let destinationID):
            string += "Matched: \(originID) to \(destinationID);"
        case .unmatched(.origin(let originID)):
            string += "Unmatched: Origin: \(originID);"
        case .unmatched(.destination(let destinationID)):
            string += "Unmatched: Destination: \(destinationID);"
        }

        string += "Event: \(InterceptionHandler.eventToString(event: self.event))"
        
        return string
    }
    
    public enum TransmissionType: Equatable {
        
        public enum Unmatched: Equatable {
            case origin(HandlerID)
            case destination(HandlerID)
        }
        
        case matched(origin: HandlerID, destination: HandlerID)
        case unmatched(Unmatched)
    }
    
    public var type: TransmissionType
    public var event: Event
    
    public init(type: TransmissionType, event: Event) {
        self.type = type
        self.event = event
    }
}
