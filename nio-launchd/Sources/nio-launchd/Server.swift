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
import ArgumentParser
import launch

struct Server: ParsableCommand {

    func getServerFileDescriptorFromLaunchd() throws -> CInt {
        let fds = UnsafeMutablePointer<UnsafeMutablePointer<CInt>>.allocate(capacity: 1)
        defer {
            fds.deallocate()
        }

        var count: Int = 0
        let ret = launch_activate_socket("Listeners", fds, &count)

        // Check the return code.
        guard ret == 0 else {
            print("error: launch_activate_socket returned with a non-zero exit code \(ret)")
            throw ExitCode(-1)
        }

        // launchd allows arbitary number of listeners but we only expect one in this example.
        guard count == 1 else {
            print("error: expected launch_activate_socket to return exactly one file descriptor")
            throw ExitCode(-1)
        }

        // This is safe because we already checked that we have exactly one result.
        let fd = fds.pointee.pointee

        defer {
            free(&fds.pointee.pointee)
        }

        return fd
    }

    func run() throws {
        // Get the server socket from launchd so we can bootstrap our echo server.
        let fd = try getServerFileDescriptorFromLaunchd()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are appled to the accepted Channels
            .childChannelInitializer { channel in
                // Ensure we don't read faster than we can write by adding the BackPressureHandler into the pipeline.
                channel.pipeline.addHandler(BackPressureHandler()).flatMap { v in
                    channel.pipeline.addHandler(EchoHandler())
                }
            }

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        // Bootstrap using the socket we got from launchd.
        let server = try bootstrap.withBoundSocket(fd).wait()
        try server.closeFuture.wait()
    }
}

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.write(data, promise: nil)
    }

    // Flush it out. This can make use of gathering writes if multiple buffers are pending
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }
}
