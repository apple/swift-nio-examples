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

import SwiftUI
import NIOVisualiserLibrary
import NIOAutomation

struct ChannelHandlerView : View {
    
    var info: ChannelHandlerInfo
    
    var currentTransmission: Transmission?
    
    var text: String {
        if let currentTransmission = currentTransmission {
            return InterceptionHandler.eventToString(event: currentTransmission.event)
        } else {
            return ""
        }
    }
    
    var port: ChannelHandlerPort? {
        if let currentTransmission = self.currentTransmission {
            switch currentTransmission.type {
            case .matched(origin: self.info.id, destination: _):
                return .out
            case .matched(origin: _, destination: self.info.id):
                return .in
            case .unmatched(.origin(self.info.id)):
                return .out
            case .unmatched(.destination(self.info.id)):
                return .in
            default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    var flashInboundIn: Bool {
        
        if let currentTransmission = currentTransmission {

            switch currentTransmission.event {
            case .inbound(_):
                switch currentTransmission.type {
                case .matched(origin: _, destination: let destinationID),
                     .unmatched(.destination(let destinationID)):
                    if info.id == destinationID {
                        return true
                    } else {
                        return false
                    }
                case .unmatched(.origin(_)):
                    return false
                }
            case .outbound(_):
                return false
            }
        }

        return false
    }
    
    var flashInboundOut: Bool {
        
        if let currentTransmission = currentTransmission {

            switch currentTransmission.event {
            case .inbound(_):
                switch currentTransmission.type {
                case .matched(origin: let originID, destination: _),
                     .unmatched(.origin(let originID)):
                    if info.id == originID {
                        return true
                    } else {
                        return false
                    }
                case .unmatched(.destination(_)):
                    return false
                }
            case .outbound(_):
                return false
            }
        }

        return false
    }
    
    var flashOutboundIn: Bool {
        
        if let currentTransmission = currentTransmission {

            switch currentTransmission.event {
            case .outbound(_):
                switch currentTransmission.type {
                case .matched(origin: _, destination: let destinationID),
                     .unmatched(.destination(let destinationID)):
                    if info.id == destinationID {
                        return true
                    } else {
                        return false
                    }
                case .unmatched(.origin(_)):
                    return false
                }
            case .inbound(_):
                return false
            }
        }

        return false
    }
    
    var flashOutboundOut: Bool {
        
        if let currentTransmission = currentTransmission {

            switch currentTransmission.event {
            case .outbound(_):
                switch currentTransmission.type {
                case .matched(origin: let originID, destination: _),
                     .unmatched(.origin(let originID)):
                    if info.id == originID {
                        return true
                    } else {
                        return false
                    }
                case .unmatched(.destination(_)):
                    return false
                }
            case .inbound(_):
                return false
            }
        }

        return false
    }
    
    var flashInbound: Bool {
        flashInboundIn || flashInboundOut
    }
    
    var flashOutbound: Bool {
        flashOutboundIn || flashOutboundOut
    }
    
    var flash: Bool {
        flashInbound || flashOutbound
    }
    
    var body: some View {
        VStack(alignment: .center) {
            
            Text(info.name.description)
                .font(.title)
                .lineLimit(4)
                .frame(width: 400, height: 40, alignment: .center)
                .padding(.all)
            
            if info.type == .duplex {
                ChannelHandlerSimplePortView(flash: flashInbound, text: text, port: self.port)
                ChannelHandlerSimplePortView(flash: flashOutbound, text: text, port: self.port)
            } else if info.type == .inbound {
                ChannelHandlerSimplePortView(flash: flash, text: text, port: self.port)
                ChannelHandlerSimplePortView(flash: flashOutbound, text: text, port: self.port).opacity(0)
            } else if info.type == .outbound {
                ChannelHandlerSimplePortView(flash: flashInbound, text: text, port: self.port).opacity(0)
                ChannelHandlerSimplePortView(flash: flash, text: text, port: self.port)
            }
            
        }
        .padding(.all)
    }
}

#if DEBUG
struct ChannelHandlerView_Previews : PreviewProvider {
    static var previews: some View {
        let duplex = ChannelHandlerInfo(id: .init("A"),
                                      name: .init("A"),
                                      type: .duplex)
        
        let inbound = ChannelHandlerInfo(id: .init("B"),
                                        name: .init("B"),
                                        type: .inbound)
        
        let outbound = ChannelHandlerInfo(id: .init("C"),
                                          name: .init("C"),
                                          type: .outbound)
        
        return
            Group {
                HStack(alignment: .top) {
                    
                    ChannelHandlerView(info: outbound)
                    ChannelHandlerView(info: inbound)
                    ChannelHandlerView(info: duplex)
                }.environment(\.colorScheme, .light)
                HStack(alignment: .top) {
                    
                    ChannelHandlerView(info: outbound)
                    ChannelHandlerView(info: inbound)
                    ChannelHandlerView(info: duplex)
                }.environment(\.colorScheme, .dark)
        }
    }
}
#endif

