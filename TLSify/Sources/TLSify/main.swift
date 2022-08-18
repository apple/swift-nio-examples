//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import NIO
import NIOSSL
import Logging

import TLSifyLib

var rootLogger = Logger(label: "TLSify")
rootLogger.logLevel = .debug

struct TLSifyCommand: ParsableCommand {
    @Option(name: .shortAndLong, help: "The host to listen to.")
    var listenHost: String = "localhost"

    @Argument(help: "The port to listen to.")
    var listenPort: Int

    @Argument(help: "The host to connect to.")
    var connectHost: String
    
    @Argument(help: "The port to connect to.")
    var connectPort: Int

    @Option(name: .long, help: "TLS certificate verfication: full (default)/no-hostname/none.")
    var tlsCertificateValidation: String = "full"

    @Option(help: "The ALPN protocols to send.")
    var alpn: [String] = []

    func run() throws {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        switch self.tlsCertificateValidation {
        case "none":
            tlsConfig.certificateVerification = .none
        case "no-hostname":
            tlsConfig.certificateVerification = .noHostnameVerification
        default:
            tlsConfig.certificateVerification = .fullVerification
        }
        tlsConfig.applicationProtocols = self.alpn
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        MultiThreadedEventLoopGroup.withCurrentThreadAsEventLoop { el in
            ServerBootstrap(group: el)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.addHandler(TLSProxy(host: self.connectHost,
                                                         port: self.connectPort,
                                                         sslContext: sslContext,
                                                         logger: rootLogger))
                }
                .bind(host: self.listenHost, port: self.listenPort)
            .map { channel in
                rootLogger.info("Listening on \(channel.localAddress!)")
            }
            .whenFailure { error in
                rootLogger.error("Couldn't bind to \(self.listenHost):\(self.listenPort): \(error)")
                el.shutdownGracefully { error in
                    if let error = error {
                        preconditionFailure("EL shutdown failed: \(error)")
                    }
                }
            }
        }
    }
}

TLSifyCommand.main()
