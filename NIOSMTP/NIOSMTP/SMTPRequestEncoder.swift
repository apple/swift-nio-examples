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
import NIOFoundationCompat
import Foundation

final class SMTPRequestEncoder: MessageToByteEncoder {
    typealias OutboundIn = SMTPRequest
    
    func encode(ctx: ChannelHandlerContext, data: SMTPRequest, out: inout ByteBuffer) throws {
        switch data {
        case .sayHello(serverName: let server):
            out.write(string: "HELO \(server)")
        case .mailFrom(let from):
            out.write(string: "MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.write(string: "RCPT TO:<\(rcpt)>")
        case .data:
            out.write(string: "DATA")
        case .transferData(let email):
            let date = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let dateFormatted = dateFormatter.string(from: date)

            out.write(string: "From: \(formatMIME(emailAddress: email.senderEmail, name: email.senderName))\r\n")
            out.write(string: "To: \(formatMIME(emailAddress: email.recipientEmail, name: email.recipientName))\r\n")
            out.write(string: "Date: \(dateFormatted)\r\n")
            out.write(string: "Message-ID: <\(date.timeIntervalSince1970)\(email.senderEmail.drop { $0 != "@" })>\r\n")
            out.write(string: "Subject: \(email.subject)\r\n\r\n")
            out.write(string: email.body)
            out.write(string: "\r\n.")
        case .quit:
            out.write(string: "QUIT")
        case .beginAuthentication:
            out.write(string: "AUTH LOGIN")
        case .authUser(let user):
            let userData = Data(user.utf8)
            out.write(bytes: userData.base64EncodedData())
        case .authPassword(let password):
            let passwordData = Data(password.utf8)
            out.write(bytes: passwordData.base64EncodedData())
        }
        
        out.write(string: "\r\n")
    }
    
    func formatMIME(emailAddress: String, name: String?) -> String {
        if let name = name {
            return "\(name) <\(emailAddress)>"
        } else {
            return emailAddress
        }
    }
}
