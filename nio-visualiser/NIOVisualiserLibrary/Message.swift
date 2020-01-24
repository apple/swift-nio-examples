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

public struct Message: CustomStringConvertible {
    public var description: String {
        var message = "Message( "
        
        message += "handlerID: \(self.handlerID), "
        message += "port: \(self.port.description), "
        message += "event: \(InterceptionHandler.eventToString(event: self.event)) )"
        
        return message
    }
    
    public var handlerID: HandlerID
    public var port: ChannelHandlerPort
    public var event: Event
    
    public init(handlerID: HandlerID, port: ChannelHandlerPort, event: Event) {
        self.handlerID = handlerID
        self.port = port
        self.event = event
    }
}
