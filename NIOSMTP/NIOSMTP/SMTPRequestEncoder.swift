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
    
    func encode(data: SMTPRequest, out: inout ByteBuffer) throws {
        switch data {
        case .sayHello(serverName: let server):
            out.writeString("EHLO \(server)")
        case .startTLS:
            out.writeString("STARTTLS")
        case .mailFrom(let from):
            out.writeString("MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.writeString("RCPT TO:<\(rcpt)>")
        case .data:
            out.writeString("DATA")
        case .transferData(let email):
            let date = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let dateFormatted = dateFormatter.string(from: date)

            out.writeString("From: \(formatMIME(emailAddress: email.senderEmail, name: email.senderName))\r\n")
            out.writeString("To: \(formatMIME(emailAddress: email.recipientEmail, name: email.recipientName))\r\n")
            out.writeString("Date: \(dateFormatted)\r\n")
            out.writeString("Message-ID: <\(date.timeIntervalSince1970)\(email.senderEmail.drop { $0 != "@" })>\r\n")
            out.writeString("Subject: \(email.subject)\r\n\r\n")
            out.writeString(email.body)
            out.writeString("\r\n.")
        case .quit:
            out.writeString("QUIT")
        case .beginAuthentication:
            out.writeString("AUTH LOGIN")
        case .authUser(let user):
            let userData = Data(user.utf8)
            out.writeBytes(userData.base64EncodedData())
        case .authPassword(let password):
            let passwordData = Data(password.utf8)
            out.writeBytes(passwordData.base64EncodedData())
        }
        
        out.writeString("\r\n")
    }
    
    func formatMIME(emailAddress: String, name: String?) -> String {
        if let name = name {
            return "\(name) <\(emailAddress)>"
        } else {
            return emailAddress
        }
    }
}
