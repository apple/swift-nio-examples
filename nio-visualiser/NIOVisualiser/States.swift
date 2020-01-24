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

import Combine
import NIO
import Dispatch
import NIOVisualiserLibrary
import NIOAutomation


class TransmissionState: ObservableObject {
    var anyCancellable: AnyCancellable! = nil
    let objectWillChange: ObservableObjectPublisher
    
    var transmissions: [Transmission] = [] {
        didSet {
            dispatchPrecondition(condition: DispatchPredicate.onQueueAsBarrier(DispatchQueue.main))
            self.objectWillChange.send()
        }
    }
    
    var validIndices: [Int] {
        self.transmissions.enumerated().filter { (n,x) in
            return shouldKeepEvent([
                (self.channelRegistered, .inbound(.channelRegistered)),
                (self.channelUnregistered, .inbound(.channelUnregistered)),
                (self.channelActive, .inbound(.channelActive)),
                (self.channelInactive, .inbound(.channelInactive)),
                (self.channelRead, .inbound(.channelRead)),
                (self.channelReadComplete, .inbound(.channelReadComplete)),
                (self.writabilityChanged, .inbound(.writabilityChanged)),
                (self.userInboundEventTriggered, .inbound(.userInboundEventTriggered)),
                (self.errorCaught, .inbound(.errorCaught)),
                (self.register, .outbound(.register)),
                (self.bind, .outbound(.bind)),
                (self.connect, .outbound(.connect)),
                (self.write, .outbound(.write)),
                (self.flush, .outbound(.flush)),
                (self.read, .outbound(.read)),
                (self.close, .outbound(.close)),
                (self.triggerUserOutboundEvent, .outbound(.triggerUserOutboundEvent))
            ], event: x.event)
        }.map({ $0.0 })
    }
    
    var channelRegistered: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var channelUnregistered: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var channelActive: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var channelInactive: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var channelRead: Bool = true {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var channelReadComplete: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var writabilityChanged: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var userInboundEventTriggered: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var write: Bool = true {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var errorCaught: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var register: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var bind: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var connect: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var flush: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var read: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var close: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var triggerUserOutboundEvent: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }

    init<P: Publisher>(publisher: P) where P.Output == Transmission, P.Failure == Never {
        self.objectWillChange = .init()
        self.anyCancellable = publisher.receive(on: DispatchQueue.main).sink { transmission in
            dispatchPrecondition(condition: DispatchPredicate.onQueueAsBarrier(DispatchQueue.main))
            self.transmissions.append(transmission)
        }
    }
}

class HandlerInfosState: ObservableObject {
    var anyCancellable: AnyCancellable!
    var objectWillChange: ObservableObjectPublisher
    
    var handlerInfos: [ChannelHandlerInfo] = [] {
        didSet {
            dispatchPrecondition(condition: DispatchPredicate.onQueueAsBarrier(DispatchQueue.main))
            self.objectWillChange.send()
        }
    }

    init<P: Publisher>(publisher: P) where P.Output == [ChannelHandlerInfo], P.Failure == Never {
        self.objectWillChange = .init()
        self.anyCancellable = publisher.receive(on: DispatchQueue.main).sink { handlerInfos in
            dispatchPrecondition(condition: DispatchPredicate.onQueueAsBarrier(DispatchQueue.main))
            self.handlerInfos = handlerInfos
        }
    }
}
