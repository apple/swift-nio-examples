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

public struct HandlerID: Hashable {
    let uuid: String
    
    public init(_ uuid: String) {
        self.uuid = uuid
    }
}


private struct HandlerIDIterator: IteratorProtocol {
    
    public typealias Element = HandlerID
    
    public mutating func next() -> HandlerID? {
        return HandlerID(UUID().uuidString)
    }
    
    public init() {}
}

public struct ChannelHandlerInfo: Equatable, Identifiable {
    
    public static func == (lhs: ChannelHandlerInfo, rhs: ChannelHandlerInfo) -> Bool {
        lhs.id.uuid == rhs.id.uuid
    }
    
    public enum HandlerType: CustomStringConvertible {
        public var description: String {
            switch self {
            case .inbound:
                return "Inbound Handler"
            case .outbound:
                return "Outbound Handler"
            case .duplex:
                return "Duplex Handler"
            case .head:
                return "Head Interception Handler"
            case .tail:
                return "Tail Interception Handler"
            case .interceptor:
                return "Interception Handler"
            }
        }
        
        case inbound
        case outbound
        case duplex
        case head
        case tail
        case interceptor
    }
    
    public struct Name: CustomStringConvertible {
        public var description: String {
            return string
        }
        
        public let string: String
        
        public init(_ string: String) {
            self.string = string
        }
    }
    
    public let id: HandlerID
    public let name: Name
    public let type: HandlerType
    
    public init(id: HandlerID, name: Name, type: HandlerType) {
        self.id = id
        self.name = name
        self.type = type
    }
}



public func pipelineAutomation(handlers: [ChannelHandler],
                               makeInterceptionHandler: (ChannelHandlerInfo) -> ChannelHandler,
                               completionHandler: ([ChannelHandlerInfo]) -> Void) -> [ChannelHandler] {
    // Initialise the HandlerIDIterator used for obtaining handler ids
    var idIterator = HandlerIDIterator()

    // Use boolean flag to set first handler type as head
    var isFirst = true

    // Obtain a list of tuples of handlers and their types
    var handlersAndInfos = handlers.flatMap { handler -> [(ChannelHandler, ChannelHandlerInfo)] in

        // Save value of isFirst and set it to false
        let isHead = isFirst
        isFirst = false

        // Create info for Interception Handler
        let handlerInfo = ChannelHandlerInfo(id: isHead ? .init("Head") : idIterator.next()!, name: isHead ? .init("Head") : .init("Interceptor"), type: isHead ? .head : .interceptor)

        // Create Interception Handler
        let interceptionHandler = makeInterceptionHandler(handlerInfo)

        // Obtain ID for real handler
        let id = idIterator.next()!

        // Obtain name for real handler
        var name = "\(type(of: handler))"

        if name.contains("<") {
            name = name.split(separator: "<", maxSplits: 2, omittingEmptySubsequences: true)[1].dropLast().description
        }

        // Compute type for real handler
        let inbound = handler is _ChannelInboundHandler
        let outbound = handler is _ChannelOutboundHandler
        let duplex = inbound && outbound

        var type: ChannelHandlerInfo.HandlerType

        if (duplex) {
            type = .duplex
        } else if (inbound) {
            type = .inbound
        } else if (outbound){
            type = .outbound
        } else {
            preconditionFailure("unknown handler type")
        }

        let info = ChannelHandlerInfo(id: id, name: .init(name), type: type)

        return [(interceptionHandler, handlerInfo), (handler, info)]
    }

    // Create tail handler
    let tailInfo = ChannelHandlerInfo(id: .init("Tail"), name: .init("Tail"), type: .tail)
    let tailHandler = makeInterceptionHandler(tailInfo)

    // Append tail handler to list of handlers
    handlersAndInfos.append((tailHandler, tailInfo))

    // Send handler infos to collector
    completionHandler(handlersAndInfos.map { $0.1 })

    return handlersAndInfos.map { $0.0 }
}
