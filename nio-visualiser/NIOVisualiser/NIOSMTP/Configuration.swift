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

import NIOTransportServices

struct Configuration {
    static let shared: Configuration = {
        // If you don't want to use your real SMTP server, do try out https://mailtrap.io they offer you an
        // SMTP server that can be used for testing for free.
        let serverConfig = ServerConfiguration(hostname: "smtp.mailtrap.io",
                                               port: 25,
                                               username: "",
                                               password: "")

        // In case you don't want to use TLS which is a bad idea and _WILL SEND YOUR PASSWORD IN PLAIN TEXT_
        // just disable this.
        let useTLS = false

        return Configuration(serverConfig: serverConfig, useTLS: useTLS)
    }()

    var serverConfig: ServerConfiguration
    var useTLS: Bool
}
