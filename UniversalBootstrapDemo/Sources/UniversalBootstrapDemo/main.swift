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
import Foundation
import NIO
import NIOTransportServices

struct UniversalBootstrapDemo: ParsableCommand {
    struct NoNetworkFrameworkError: Error {}

    static let configuration = CommandConfiguration(
        abstract: """
                     Demonstrates using NIO's universal bootstrap. Try for example

                         UniversalBootstrapDemo https://httpbin.org/get
                  """)

    @Flag(help: "Force using NIO on Network.framework.")
    var forceTransportServices = false

    @Flag(help: "Force using NIO on BSD sockets.")
    var forceBSDSockets = false

    @Argument(help: "The URL.")
    var url: String = "https://httpbin.org/get"

    func run() throws {
        var group: EventLoopGroup? = nil
        if self.forceTransportServices {
            #if canImport(Network)
            if #available(macOS 10.14, *) {
                group = NIOTSEventLoopGroup()
            } else {
                print("Sorry, your OS is too old for Network.framework.")
                Self.exit(withError: NoNetworkFrameworkError())
            }
            #else
            print("Sorry, no Network.framework on your OS.")
            Self.exit(withError: NoNetworkFrameworkError())
            #endif
        }
        if self.forceBSDSockets {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
        defer {
            try? group?.syncShutdownGracefully()
        }

        let provider: EventLoopGroupManager.Provider = group.map { .shared($0) } ?? .createNew
        let httpClient = ExampleHTTPLibrary(groupProvider: provider)
        defer {
            try! httpClient.shutdown()
        }
        try httpClient.makeRequest(url: url)
    }
}

UniversalBootstrapDemo.main()
