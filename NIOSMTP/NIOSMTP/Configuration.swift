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

import NIOTransportServices

extension NIOTSConnectionBootstrap {
    static var config: ServerConfiguration {
        #warning("You need to configure an SMTP server in code.")
        // if you don't want to use your real SMTP server, do try out https://mailtrap.io they offer you an
        // SMTP server that can be used for testing for free.
        return ServerConfiguration(hostname: "you.need.to.configure.your.providers.smtp.server",
                                   port: 465,
                                   username: "put your username here",
                                   password: "and your password goes here")
    }

    func tlsConfig() -> NIOTSConnectionBootstrap {
        // in case you don't want to use TLS which is a bad idea and _WILL SEND YOUR PASSWORD IN PLAIN TEXT_
        // just `return self`.
        return self.tlsOptions(.init())
    }
}
