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

import NIO
import NIOAutomation

/// ChannelInboundHandler that prints all inbound events that pass through the pipeline by default,
/// overridable by providing your own closure for custom logging. See DebugOutboundEventsHandler for outbound events.
public class InterceptionHandler: ChannelDuplexHandler {
    
    public typealias OutboundIn = Any
    public typealias OutboundOut = Any
    public typealias InboundIn = Any
    public typealias InboundOut = Any
    
    var info: ChannelHandlerInfo
    var collector: Collector
    
    public init(_ info: ChannelHandlerInfo, collector: Collector) {
        self.info = info
        self.collector = collector
    }
    
    public func channelRegistered(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelRegistered))
        context.fireChannelRegistered()
    }
    
    public func channelUnregistered(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelUnregistered))
        context.fireChannelUnregistered()
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelActive))
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelInactive))
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelRead(data: self.unwrapInboundIn(data))))
        context.fireChannelRead(data)
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.channelReadComplete))
        context.fireChannelReadComplete()
    }
    
    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.writabilityChanged(isWritable: context.channel.isWritable)))
        context.fireChannelWritabilityChanged()
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.userInboundEventTriggered(event: event)))
        context.fireUserInboundEventTriggered(event)
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        collector.storeEvent(handlerInfo: self.info, event: .inbound(.errorCaught(error)))
        context.fireErrorCaught(error)
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.write(data: self.unwrapOutboundIn(data))))
        context.write(data, promise: promise)
    }
    
    public func register(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.register))
        context.register(promise: promise)
    }
    
    public func bind(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.bind(address: address)))
        context.bind(to: address, promise: promise)
    }
    
    public func connect(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.connect(address: address)))
        context.connect(to: address, promise: promise)
    }
    
    public func flush(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.flush))
        context.flush()
    }
    
    public func read(context: ChannelHandlerContext) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.read))
        context.read()
    }
    
    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.close(mode: mode)))
        context.close(mode: mode, promise: promise)
    }
    
    public func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        collector.storeEvent(handlerInfo: self.info, event: .outbound(.triggerUserOutboundEvent(event: event)))
        context.triggerUserOutboundEvent(event, promise: promise)
    }
    
    private static func formatByteBuffer(_ buffer: ByteBuffer) -> String {
        return {
            let isPrintable = buffer.readableBytesView.allSatisfy {
                isprint(.init($0)) != 0
            }
            let isASCII = buffer.readableBytesView.allSatisfy {
                isascii(.init($0)) != 0
            }
            
            if isPrintable {
                return String(decoding: buffer.readableBytesView, as: Unicode.UTF8.self)
            } else if isASCII {
                return String(decoding: buffer.readableBytesView.map {
                    if isprint(.init($0)) != 0 {
                        return $0
                    } else {
                        return UInt8(ascii: ".")
                    }
                }, as: Unicode.UTF8.self)
            } else {
                var desc = "["
                for byte in buffer.readableBytesView {
                    let hexByte = String(byte, radix: 16)
                    desc += " \(hexByte.count == 1 ? "0" : "")\(hexByte)"
                }
                desc += " ]"
                return desc
            }
        }()
    }
    
    private static func formatData(_ data: Any) -> String {
        switch data {
        case let data as ByteBuffer:
            return formatByteBuffer(data)
        case let data as IOData:
            switch data {
            case .byteBuffer(let buffer):
                return formatByteBuffer(buffer)
            case .fileRegion(let region):
                return String(describing: region)
            }
        default:
            return String(describing: data)
        }
        
    }
    
    public static func eventToString(event: Event) -> String {
        switch event {
        case .inbound(let event):
            switch event {
            case .channelRead(data: let data):
                return formatData(data)
            default:
                return String(describing: event)
            }

        case .outbound(let event):
            switch event {
            case .write(data: let data):
                return formatData(data)
            default:
                return String(describing: event)
            }
        }
    }
}
