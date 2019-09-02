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
import NIO

public enum Event {
    public enum EventType: Equatable {
        case inbound(InboundEvent.EventType)
        case outbound(OutboundEvent.EventType)
    }
    case inbound(InboundEvent)
    case outbound(OutboundEvent)
    
    public var eventType: EventType {
        switch self {
        case .inbound(let inboundEvent):
            switch inboundEvent {
            case .channelRegistered:
                return .inbound(.channelRegistered)
            case .channelUnregistered:
                return .inbound(.channelUnregistered)
            case .channelActive:
                return .inbound(.channelActive)
            case .channelInactive:
                return .inbound(.channelInactive)
            case .channelRead:
                return .inbound(.channelRead)
            case .channelReadComplete:
                return .inbound(.channelReadComplete)
            case .writabilityChanged:
                return .inbound(.writabilityChanged)
            case .userInboundEventTriggered:
                return .inbound(.userInboundEventTriggered)
            case .errorCaught:
                return .inbound(.errorCaught)
            }
        case .outbound(let outboundEvent):
            switch outboundEvent {
            case .register:
                return .outbound(.register)
            case .bind:
                return .outbound(.bind)
            case .connect:
                return .outbound(.connect)
            case .write:
                return .outbound(.write)
            case .flush:
                return .outbound(.flush)
            case .read:
                return .outbound(.read)
            case .close:
                return .outbound(.close)
            case .triggerUserOutboundEvent:
                return .outbound(.triggerUserOutboundEvent)
            }
        }
    }
}

public enum InboundEvent {
    public enum EventType {
        case channelRegistered
        case channelUnregistered
        case channelActive
        case channelInactive
        case channelRead
        case channelReadComplete
        case writabilityChanged
        case userInboundEventTriggered
        case errorCaught
    }
    case channelRegistered
    case channelUnregistered
    case channelActive
    case channelInactive
    case channelRead(data: Any)
    case channelReadComplete
    case writabilityChanged(isWritable: Bool)
    case userInboundEventTriggered(event: Any)
    case errorCaught(Error)
}

public enum OutboundEvent {
    public enum EventType {
        case register
        case bind
        case connect
        case write
        case flush
        case read
        case close
        case triggerUserOutboundEvent
    }
    case register
    case bind(address: SocketAddress)
    case connect(address: SocketAddress)
    case write(data: Any)
    case flush
    case read
    case close(mode: CloseMode)
    case triggerUserOutboundEvent(event: Any)
}
