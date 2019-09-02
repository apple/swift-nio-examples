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
import NIOVisualiserLibrary
import NIOAutomation

class CollectorData {
    static let handlerInfos: [ChannelHandlerInfo] = [
        // 0: Head
        ChannelHandlerInfo(id: HandlerID("A975CF54-DA71-4494-B2C1-30127AEBAF3D"), name: .init("Head"), type: .head),

        // 1: PrintEverythingHandler
        ChannelHandlerInfo(id: HandlerID("97B9C739-3FBF-4BF5-9C05-CB5953B8E651"), name: .init("PrintEverythingHandler"), type: .duplex),

        // 2: Interceptor
        ChannelHandlerInfo(id: HandlerID("DC35148A-4CBF-4D3E-9F60-FD6EBC3EFE0B"), name: .init("Interceptor"), type: .interceptor),

        // 3: ByteToMessageHandler<LineBasedFrameDecoder>
        ChannelHandlerInfo(id: HandlerID("CC20BDC8-443E-4FF2-820E-0EAD2C46BF75"), name: .init("LineBasedFrameDecoder"), type: .inbound),

        // 4: Interceptor
        ChannelHandlerInfo(id: HandlerID("F4B997BF-EF45-43E6-88D4-071BC3EC6816"), name: .init("Interceptor"), type: .interceptor),

        // 5: SMTPResponseDecoder
        ChannelHandlerInfo(id: HandlerID("6925437E-5BE5-4564-ACE8-172C5AFD2BF3"), name: .init("SMTPResponseDecoder"), type: .inbound),

        // 6: Interceptor
        ChannelHandlerInfo(id: HandlerID("F038CA7F-BA60-4BB8-868B-2A48971BB9C7"), name: .init("Interceptor"), type: .interceptor),

        // 7: MessageToByteHandler<SMTPRequestEncoder>
        ChannelHandlerInfo(id: HandlerID("72FACDD9-C7E7-49B6-ADDD-BEE6694C9B42"), name: .init("SMTPRequestEncoder"), type: .outbound),

        // 8: Interceptor
        ChannelHandlerInfo(id: HandlerID("0B1789C7-B683-484A-BFCB-9596C869FF69"), name: .init("Interceptor"), type: .interceptor),

        // 9: SendEmailHandler
        ChannelHandlerInfo(id: HandlerID("1C7727C8-8DD5-4AAA-8669-F46232E4F1FE"), name: .init("SendEmailHandler"), type: .inbound),

        // 10: Tail
        ChannelHandlerInfo(id: HandlerID("3E6DE474-5B98-4E3E-BA3B-91FB26694B53"), name: .init("Tail"), type: .tail)
    ]
    
    static let messages: [Message] = [
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(220, "mailtrap.io ESMTP ready")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(220, "mailtrap.io ESMTP ready")))),
        Message(handlerID: handlerInfos[9].id, port: .out, event: .outbound(.write(data: SMTPRequest.sayHello(serverName: "smtp.mailtrap.io")))),
        Message(handlerID: handlerInfos[7].id, port: .in, event: .outbound(.write(data: SMTPRequest.sayHello(serverName: "smtp.mailtrap.io")))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "STARTTLS")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "STARTTLS")))),
        Message(handlerID: handlerInfos[9].id, port: .out, event: .outbound(.write(data: SMTPRequest.beginAuthentication))),
        Message(handlerID: handlerInfos[7].id, port: .in, event: .outbound(.write(data: SMTPRequest.beginAuthentication))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(235, "2.0.0 OK")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(235, "2.0.0 OK")))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "2.1.0 Ok")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "2.1.0 Ok")))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(354, "Go ahead")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(354, "Go ahead")))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "2.0.0 Ok: queued")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(250, "2.0.0 Ok: queued")))),
        Message(handlerID: handlerInfos[5].id, port: .out, event: .inbound(.channelRead(data: SMTPResponse.ok(221, "2.0.0 Bye")))),
        Message(handlerID: handlerInfos[9].id, port: .in, event: .inbound(.channelRead(data: SMTPResponse.ok(221, "2.0.0 Bye"))))
    ]
}
