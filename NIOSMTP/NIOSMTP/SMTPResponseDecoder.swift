//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

final class SMTPResponseDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = SMTPResponse
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = self.unwrapInboundIn(data)
        
        if let firstFourBytes = response.readString(length: 4), let code = Int(firstFourBytes.dropLast()) {
            let remainder = response.readString(length: response.readableBytes) ?? ""
            
            let firstCharacter = firstFourBytes.first!
            let fourthCharacter = firstFourBytes.last!
            
            switch (firstCharacter, fourthCharacter) {
            case ("2", " "),
                 ("3", " "):
                let parsedMessage = SMTPResponse.ok(code, remainder)
                context.fireChannelRead(self.wrapInboundOut(parsedMessage))
            case (_, "-"):
                () // intermediate message, ignore
            default:
                context.fireChannelRead(self.wrapInboundOut(.error(firstFourBytes+remainder)))
            }
        } else {
            context.fireErrorCaught(SMTPResponseDecoderError.malformedMessage)
        }
    }
}

enum SMTPResponseDecoderError: Error {
    case malformedMessage
}
