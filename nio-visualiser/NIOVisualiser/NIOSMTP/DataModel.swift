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

enum SMTPRequest {
    case sayHello(serverName: String)
    case beginAuthentication
    case authUser(String)
    case authPassword(String)
    case mailFrom(String)
    case recipient(String)
    case data
    case transferData(Email)
    case quit
}

enum SMTPResponse {
    case ok(Int, String)
    case error(String)
}

struct ServerConfiguration {
    var hostname: String
    var port: Int
    var username: String
    var password: String
}

struct Email: CustomStringConvertible {
    
    var description: String {
        var message = ""
        
        if let senderName = senderName {
            message.append("Sender Name: \(senderName);")
        }
        
        message.append("Sender Email: \(senderEmail);")
        
        if let recipientName = recipientName {
            message.append("Recepient Name: \(recipientName);")
        }
        
        message.append("Recepient Email: \(recipientEmail);")
        
        message.append("Subject: \(subject);")
        
        message.append("Body: \(body);")
        
        return message
    }
    
    var senderName: String?
    var senderEmail: String
    
    var recipientName: String?
    var recipientEmail: String
    
    var subject: String
    
    var body: String
}
