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

import Logging
import NIOCore

public final class CloseOnErrorHandler: ChannelInboundHandler, Sendable {
    public typealias InboundIn = Never

    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logger.info("unhandled error \(error), closing \(context.channel)")
        context.close(promise: nil)
    }
}
