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
import Combine
import NIOVisualiserLibrary
import NIOAutomation

struct ChannelPipelineView : View {
    
    @ObservedObject var handlerInfosState: HandlerInfosState
    @ObservedObject var transmissionState: TransmissionState
    
    @State var index: Int? = 0
    
    var channelRegisteredBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelRegistered },
              set: { self.transmissionState.channelRegistered = $0 })
    }
    
    var channelUnregisteredBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelUnregistered },
              set: { self.transmissionState.channelUnregistered = $0 })
    }
    
    var channelActiveBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelActive },
              set: { self.transmissionState.channelActive = $0 })
    }
    
    var channelInactiveBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelInactive },
              set: { self.transmissionState.channelInactive = $0 })
    }
    
    var channelReadBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelRead },
              set: { self.transmissionState.channelRead = $0 })
    }
    
    var writeBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.write },
              set: { self.transmissionState.write = $0 })
    }
    
    var channelReadCompleteBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.channelReadComplete },
              set: { self.transmissionState.channelReadComplete = $0 })
    }
    
    var writabilityChangedBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.writabilityChanged },
              set: { self.transmissionState.writabilityChanged = $0 })
    }
    
    var userInboundEventTriggeredBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.userInboundEventTriggered },
              set: { self.transmissionState.userInboundEventTriggered = $0 })
    }
    
    var errorCaughtBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.errorCaught },
              set: { self.transmissionState.errorCaught = $0 })
    }
    
    var registerBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.register },
              set: { self.transmissionState.register = $0 })
    }
    
    var bindBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.bind },
              set: { self.transmissionState.bind = $0 })
    }
    
    var connectBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.connect },
              set: { self.transmissionState.connect = $0 })
    }
    
    var flushBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.flush },
              set: { self.transmissionState.flush = $0 })
    }
    
    var readBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.read },
              set: { self.transmissionState.read = $0 })
    }
    
    var closeBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.close },
              set: { self.transmissionState.close = $0 })
    }
    
    var triggerUserOutboundEventBinding: Binding<Bool> {
        .init(get: { return self.transmissionState.triggerUserOutboundEvent },
              set: { self.transmissionState.triggerUserOutboundEvent = $0 })
    }
    
    var handlerInfos: [ChannelHandlerInfo] {
        self.handlerInfosState.handlerInfos
    }
    
    var transmissions: [Transmission] {
        self.transmissionState.transmissions
    }
    
    var validIndices: [Int] {
        self.transmissionState.validIndices
    }

    var currentTransmission: Transmission? {
        guard let index = self.index else {
            return nil
        }
        if index >= 0 && index < transmissions.count {
            return transmissions[index]
        }
        return nil
    }
    
    func handlerView(_ info: ChannelHandlerInfo,
                     currentTransmission: Transmission?) -> AnyView {
        
        if (info.type == .inbound ||
            info.type == .outbound ||
            info.type == .duplex) {
            return AnyView(
                ChannelHandlerView(info: info,
                                   currentTransmission: currentTransmission)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    
    func nextIndex() -> Int? {
        return nextIndexIfValid(validIndices: self.validIndices, index: self.index)
    }
    
    func previousIndex() -> Int? {
        return previousIndexIfValid(validIndices: self.validIndices, index: self.index)
    }
    
    var body: some View {
        VStack(alignment: .center) {
            
//            Text("Transmissions: \(self.transmissions.count)")
//            Text("Valid Indices: \(self.validIndices.count)")
//            Text("Current Index: \(index.map(String.init) ?? "n/a")")
            
            Text(InterceptionHandler.eventToString(event: self.currentTransmission?.event ?? .inbound(.channelInactive)))
                .font(.system(.largeTitle, design: .monospaced))
                .foregroundColor(.green)
                .padding(.all)
                .background(Color.black)
            
            HStack(alignment: .center) {
                Spacer()
                ForEach(self.handlerInfos) { info in
                    self.handlerView(info,
                                     currentTransmission: self.currentTransmission)
                    Spacer()
                }
            }
            .border(Color.black, width: 4)
            

            
            HStack(alignment: .center) {
                Button(action: {
                    self.index = self.previousIndex()
                }) {
                    Text("Previous Transmission")
                }.disabled(self.previousIndex() == nil)
                Button(action: {
                    self.index = self.nextIndex()
                }) {
                    Text("Next Transmission")
                }.disabled(self.nextIndex() == nil)
            }
            
            VStack(alignment: .center) {
                HStack(alignment: .center) {
                    EventToggle(bool: self.channelRegisteredBinding, text: "ChannelRegistered")
                    EventToggle(bool: self.channelUnregisteredBinding, text: "ChannelUnregistered")
                    EventToggle(bool: self.channelActiveBinding, text: "ChannelActive")
                    EventToggle(bool: self.channelInactiveBinding, text: "ChannelInactive")
                    EventToggle(bool: self.channelReadBinding, text: "ChannelRead")
                    EventToggle(bool: self.channelReadCompleteBinding, text: "ChannelReadComplete")
                    EventToggle(bool: self.writabilityChangedBinding, text: "WritabilityChanged")
                    EventToggle(bool: self.userInboundEventTriggeredBinding, text: "UserInboundEventTriggered")
                    EventToggle(bool: self.errorCaughtBinding, text: "ErrorCaught")
                }
                HStack(alignment: .center) {
                    EventToggle(bool: self.registerBinding, text: "Register")
                    EventToggle(bool: self.bindBinding, text: "Bind")
                    EventToggle(bool: self.connectBinding, text: "Connect")
                    EventToggle(bool: self.writeBinding, text: "Write")
                    EventToggle(bool: self.flushBinding, text: "Flush")
                    EventToggle(bool: self.readBinding, text: "Read")
                    EventToggle(bool: self.closeBinding, text: "Close")
                    EventToggle(bool: self.triggerUserOutboundEventBinding, text: "TriggerUserOutboundEvent")
                }
            }
        }
    }
}

//#if DEBUG
//struct ChannelPipelineView_Previews : PreviewProvider {
//    static var previews: some View {
//
//        let collector = Collector()
//
//        collector.save(handlerInfos: [
//            ChannelHandlerInfo(id: .init("A"), name: .init("A"), type: .duplex),
//            ChannelHandlerInfo(id: .init("B"), name: .init("B"), type: .inbound),
//            ChannelHandlerInfo(id: .init("C"), name: .init("C"), type: .inbound),
//            ChannelHandlerInfo(id: .init("D"), name: .init("D"), type: .outbound),
//            ChannelHandlerInfo(id: .init("E"), name: .init("E"), type: .inbound)
//        ])
//
//        return ChannelPipelineView(handlerInfosState: HandlerInfosState(publisher: collector.$handlerInfos),
//                                   transmissionState: TransmissionState(publisher: collector.messagePublisher.transmissionHeuristics())
//        ).scaledToFit()
//    }
//}
//#endif
