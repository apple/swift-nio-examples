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

import NIO
import NIOTransportServices
import NIOSSL
import NIOConcurrencyHelpers

/// `EventLoopGroupManager` can be used to manage an `EventLoopGroup`, either by creating or by sharing an existing one.
///
/// When making network client libraries with SwiftNIO that are supposed to work well on both Apple platforms (macOS,
/// iOS, tvOS, ...) as well as Linux, users often find it tedious to select the right combination of:
///
/// - an `EventLoopGroup`
/// - a bootstrap
/// - a TLS implementation
///
/// The choices to the above need to be compatible, or else the program won't work.
///
/// What makes the task even harder is that as a client library, you often want to share the `EventLoopGroup` with other
/// components. That raises the question of how to choose a bootstrap and a matching TLS implementation without even
/// knowing the concrete `EventLoopGroup` type (it may be `SelectableEventLoop` which is an internal `NIO` types).
/// `EventLoopGroupManager` should support all those use cases with a simple API.
public class EventLoopGroupManager: @unchecked Sendable {
    private let lock = NIOLock()
    private var group: Optional<EventLoopGroup>
    private let provider: Provider
    private var sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())

    public enum Provider {
        case createNew
        case shared(EventLoopGroup)
    }

    /// Initialize the `EventLoopGroupManager` with a `Provider` of `EventLoopGroup`s.
    ///
    /// The `Provider` lets you choose whether to use a `.shared(group)` or to `.createNew`.
    public init(provider: Provider) {
        self.provider = provider
        switch self.provider {
        case .shared(let group):
            self.group = group
        case .createNew:
            self.group = nil
        }
    }

    deinit {
        assert(self.group == nil, "Please call EventLoopGroupManager.syncShutdown .")
    }
}

// - MARK: Public API
extension EventLoopGroupManager {
    /// Create a "universal bootstrap" for the given host.
    ///
    /// - parameters:
    ///     - hostname: The hostname to connect to (for SNI).
    ///     - useTLS: Whether to use TLS or not.
    public func makeBootstrap(hostname: String, useTLS: Bool = true) throws -> NIOClientTCPBootstrap {
        try self.lock.withLock {
            let bootstrap: NIOClientTCPBootstrap
            if let group = self.group {
                bootstrap = try self.makeUniversalBootstrapWithExistingGroup(group, serverHostname: hostname)
            } else {
                bootstrap = try self.makeUniversalBootstrapWithSystemDefaults(serverHostname: hostname)
            }

            if useTLS {
                return bootstrap.enableTLS()
            } else {
                return bootstrap
            }
        }
    }

    /// Shutdown the `EventLoopGroupManager`.
    ///
    /// This will release all resources associated with the `EventLoopGroupManager` such as the threads that the
    /// `EventLoopGroup` runs on.
    ///
    /// This method _must_ be called when you're done with this `EventLoopGroupManager`.
    public func syncShutdown() throws {
        try self.lock.withLock {
            switch self.provider {
            case .createNew:
                try self.group?.syncShutdownGracefully()
            case .shared:
                () // nothing to do.
            }
            self.group = nil
        }
    }
}

// - MARK: Error types
extension EventLoopGroupManager {
    /// The provided `EventLoopGroup` is not compatible with this client.
    public struct UnsupportedEventLoopGroupError: Error {
        var eventLoopGroup: EventLoopGroup
    }
}

// - MARK: Internal functions
extension EventLoopGroupManager {
    // This function combines the right pieces and returns you a "universal client bootstrap"
    // (`NIOClientTCPBootstrap`). This allows you to bootstrap connections (with or without TLS) using either the
    // NIO on sockets (`NIO`) or NIO on Network.framework (`NIOTransportServices`) stacks.
    // The remainder of the code should be platform-independent.
    private func makeUniversalBootstrapWithSystemDefaults(serverHostname: String) throws -> NIOClientTCPBootstrap {
        if let group = self.group {
            return try self.makeUniversalBootstrapWithExistingGroup(group, serverHostname: serverHostname)
        }

        let group: EventLoopGroup
        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 6, *) {
            // We run on a new-enough Darwin so we can use Network.framework
            group = NIOTSEventLoopGroup()
        } else {
            // We're on Darwin but not new enough for Network.framework, so we fall back on NIO on BSD sockets.
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
        #else
        // We are on a non-Darwin platform, so we'll use BSD sockets.
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        #endif

        // Let's save it for next time.
        self.group = group
        return try self.makeUniversalBootstrapWithExistingGroup(group, serverHostname: serverHostname)
    }

    // If we already know the group, then let's just contruct the correct bootstrap.
    private func makeUniversalBootstrapWithExistingGroup(_ group: EventLoopGroup,
                                                                serverHostname: String) throws -> NIOClientTCPBootstrap {
        if let bootstrap = ClientBootstrap(validatingGroup: group) {
            return try NIOClientTCPBootstrap(bootstrap,
                                             tls: NIOSSLClientTLSProvider(context: self.sslContext,
                                                                          serverHostname: serverHostname))
        }

        #if canImport(Network)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 6, *) {
            if let makeBootstrap = NIOTSConnectionBootstrap(validatingGroup: group) {
                return NIOClientTCPBootstrap(makeBootstrap, tls: NIOTSClientTLSProvider())
            }
        }
        #endif

        throw UnsupportedEventLoopGroupError(eventLoopGroup: group)
    }
}
