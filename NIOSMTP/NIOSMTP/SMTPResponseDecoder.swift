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

/// `SMTPResponseDecoder` decodes exactly one SMTP response from already newline-framed input messages.
///
/// To use `SMTPResponseDecoder` you must insert a handler that does the newline based framing in front of the
/// `SMTPResponseDecoder`. Usually, you would insert `LineBasedFrameDecoder` immediately followed by
/// `SMTPResponseDecoder` into the `ChannelPipeline` to do the job.
///
/// ### Example
///
/// For example, the following threee incoming events, will be decoded into exactly one
/// `.SMTPResponse.ok(250, "okay")`:
///
/// 1. `250-smtp.foo.com at your service`
/// 2. `250-SIZE 35882577`
/// 3. `250 okay`
///
/// On the TCP level, those three messages will have arrived in one of more TCP packets (and also separated by `\r\n`).
/// `LineBasedFrameDecoder` then took care of the framing and forwarded them as three separate events.
///
/// The reason that those three incoming events only produce only one outgoing event is because the first two are
/// partial SMTP responses (starting with `250-`). The last message always ends with a space character after the
/// response code (`250 `).
///
/// ### Why is `SMTPResponseDecoder` not a `ByteToMessageDecoder`?
///
/// On a first look, `SMTPResponseDecoder` looks like a great candidate to be a `ByteToMessageDecoder` and yet it is
/// not one. The reason is that `ByteToMessageDecoder`s are great if the input is a _stream of bytes_ which means
/// that the incoming framing of the messages has no meaning because they are arbitrary chunks of a TCP stream.
///
/// `SMTPResponseDecoder`'s job is actually simpler because it expects its inbound messages to be already framed. The
/// framing for SMTP is based on newlines (`\r\n`) and `SMTPResponseDecoder` expects to receive exactly one line at a
/// time. That is usually achieved by inserting `SMTPResponseDecoder` right after a `LineBasedFrameDecoder` into the
/// `ChannelPipeline`. That is quite nice because we separate the concerns quite nicely: `LineBasedFrameDecoder` does
/// only the newline-based framing and `SMTPResponseDecoder` just decodes pre-framed SMTP responses.
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
