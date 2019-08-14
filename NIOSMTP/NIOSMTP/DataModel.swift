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

enum SMTPRequest {
    case sayHello(serverName: String)
    case startTLS
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
    enum TLSConfiguration {
        /// Use StartTLS, this should be the default and is secure.
        case startTLS

        /// Directly open a TLS connection. This secure however not widely supported.
        case regularTLS

        /// This should never be used. It will literally _SEND YOUR PASSWORD IN PLAINTEXT OVER THE INTERNET_.
        case unsafeNoTLS
    }
    var hostname: String
    var port: Int
    var username: String
    var password: String
    var tlsConfiguration: TLSConfiguration
}

struct Email {
    var senderName: String?
    var senderEmail: String
    
    var recipientName: String?
    var recipientEmail: String
    
    var subject: String
    
    var body: String
}
