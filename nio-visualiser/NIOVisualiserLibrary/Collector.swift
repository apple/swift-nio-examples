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
import Combine
import NIOAutomation

public class Collector: ObservableObject {
    
    public init() {}
    
    public var messages: [Message] = []
    
    // TODO: tests for messagePublisher
    public var messagePublisher = PassthroughSubject<Message, Never>()
    
    @Published public var handlerInfos: [ChannelHandlerInfo] = []

    var handlerIDToIndex = [HandlerID : Int]()
    
    public func save(handlerInfos: [ChannelHandlerInfo]) {
        self.handlerInfos = handlerInfos
        
        for (index, info) in handlerInfos.enumerated() {
            handlerIDToIndex[info.id] = index
        }
    }
    
    public func storeEvent(handlerInfo: ChannelHandlerInfo, event: Event) {
        switch event {
        case .inbound(let event):
            self.storeInbound(handlerInfo: handlerInfo, event: event)
        case .outbound(let event):
            self.storeOutbound(handlerInfo: handlerInfo, event: event)
        }
    }
    
    private func storeInbound(handlerInfo: ChannelHandlerInfo, event: InboundEvent) {
        predictInboundSource(handlerInfo: handlerInfo, event: event)
        predictInboundDestination(handlerInfo: handlerInfo, event: event)
    }
    
    private func predictInboundSource(handlerInfo: ChannelHandlerInfo, event: InboundEvent) {
        
        let index = handlerIDToIndex[handlerInfo.id]!
        
        
        switch handlerInfo.type {
        case .interceptor,
             .tail:
            let sourceInfo = handlerInfos[index-1]
            
            switch sourceInfo.type {
            case .inbound,
                 .duplex:
                let message = Message(handlerID: sourceInfo.id,
                                      port: .out,
                                      event: .inbound(event))
                self.messages.append(message)
                self.messagePublisher.send(message)
            case .outbound:
                if let lastMessage = messages.last {
                    if lastMessage.handlerID == sourceInfo.id {
                        let message = Message(handlerID: sourceInfo.id,
                                              port: .out,
                                              event: .inbound(event))
                        self.messages.append(message)
                        self.messagePublisher.send(message)
                    }
                }
            default:
                ()
            }
        default:
            ()
        }
    }
    
    private func predictInboundDestination(handlerInfo: ChannelHandlerInfo, event: InboundEvent) {
        let index = handlerIDToIndex[handlerInfo.id]!
        
        switch handlerInfo.type {
        case .interceptor,
             .head:
            let destinationInfo = handlerInfos[index+1]
            
            switch destinationInfo.type {
            case .inbound,
                 .duplex:
                let message = Message(handlerID: destinationInfo.id,
                                      port: .in,
                                      event: .inbound(event))
                self.messages.append(message)
                self.messagePublisher.send(message)
            default:
                ()
            }
        default:
            ()
        }
    }
    
    private func storeOutbound(handlerInfo: ChannelHandlerInfo, event: OutboundEvent) {
        predictOutboundSource(handlerInfo: handlerInfo, event: event)
        predictOutboundDestination(handlerInfo: handlerInfo, event: event)
    }
    
    private func predictOutboundSource(handlerInfo: ChannelHandlerInfo, event: OutboundEvent) {
        let index = handlerIDToIndex[handlerInfo.id]!
        
        switch handlerInfo.type {
        case .interceptor,
             .head:
            let sourceInfo = handlerInfos[index+1]
            
            switch sourceInfo.type {
            case .outbound,
                 .duplex:
                let message = Message(handlerID: sourceInfo.id,
                                      port: .out,
                                      event: .outbound(event))
                self.messages.append(message)
                self.messagePublisher.send(message)
            case .inbound:
                if let lastMessage = messages.last {
                    if lastMessage.handlerID == sourceInfo.id {
                        let message = Message(handlerID: sourceInfo.id,
                                              port: .out,
                                              event: .outbound(event))
                        self.messages.append(message)
                        self.messagePublisher.send(message)
                    }
                }
            default:
                ()
            }
        default:
            ()
        }
    }
    
    private func predictOutboundDestination(handlerInfo: ChannelHandlerInfo, event: OutboundEvent) {
        let index = handlerIDToIndex[handlerInfo.id]!
        
        switch handlerInfo.type {
        case .interceptor,
             .tail:
            let destinationInfo = handlerInfos[index-1]
            
            switch destinationInfo.type {
            case .outbound,
                 .duplex:
                let message = Message(handlerID: destinationInfo.id,
                                      port: .in,
                                      event: .outbound(event))
                self.messages.append(message)
                self.messagePublisher.send(message)
            default:
                ()
            }
        default:
            ()
        }
    }
}
