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

// original source is swift-nio-extras which doesn't have a Pod yet :\
// https://github.com/apple/swift-nio-extras/blob/master/Sources/NIOExtras/LineBasedFrameDecoder.swift

import NIO

public protocol NIOExtrasError: Equatable, Error { }

/// Errors that are raised in NIOExtras.
public enum NIOExtrasErrors {
    
    /// Error indicating that after an operation some unused bytes are left.
    public struct LeftOverBytesError: NIOExtrasError {
        public let leftOverBytes: ByteBuffer
    }
}


/// A decoder that splits incoming `ByteBuffer`s around line end
/// character(s) (`'\n'` or `'\r\n'`).
///
/// Let's, for example, consider the following received buffer:
///
///     +----+-------+------------+
///     | AB | C\nDE | F\r\nGHI\n |
///     +----+-------+------------+
///
/// A instance of `LineBasedFrameDecoder` will split this buffer
/// as follows:
///
///     +-----+-----+-----+
///     | ABC | DEF | GHI |
///     +-----+-----+-----+
///
public class LineBasedFrameDecoder: ByteToMessageDecoder {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public var cumulationBuffer: ByteBuffer?
    // keep track of the last scan offset from the buffer's reader index (if we didn't find the delimiter)
    private var lastScanOffset = 0
    private var handledLeftovers = false
    
    public init() { }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let frame = try self.findNextFrame(buffer: &buffer) {
            ctx.fireChannelRead(wrapInboundOut(frame))
            return .continue
        } else {
            return .needMoreData
        }
    }
    
    private func findNextFrame(buffer: inout ByteBuffer) throws -> ByteBuffer? {
        let view = buffer.readableBytesView.dropFirst(self.lastScanOffset)
        // look for the delimiter
        if let delimiterIndex = view.firstIndex(of: 0x0A) { // '\n'
            let length = delimiterIndex - buffer.readerIndex
            let dropCarriageReturn = delimiterIndex > view.startIndex && view[delimiterIndex - 1] == 0x0D // '\r'
            let buff = buffer.readSlice(length: dropCarriageReturn ? length - 1 : length)
            // drop the delimiter (and trailing carriage return if appicable)
            buffer.moveReaderIndex(forwardBy: dropCarriageReturn ? 2 : 1)
            // reset the last scan start index since we found a line
            self.lastScanOffset = 0
            return buff
        }
        // next scan we start where we stopped
        self.lastScanOffset = buffer.readableBytes
        return nil
    }
    
    public func handlerRemoved(ctx: ChannelHandlerContext) {
        self.handleLeftOverBytes(ctx: ctx)
    }
    
    public func channelInactive(ctx: ChannelHandlerContext) {
        self.handleLeftOverBytes(ctx: ctx)
    }
    
    private func handleLeftOverBytes(ctx: ChannelHandlerContext) {
        if let buffer = self.cumulationBuffer, buffer.readableBytes > 0 && !self.handledLeftovers {
            self.handledLeftovers = true
            ctx.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
    }
}

#if !swift(>=4.2)
private extension ByteBufferView {
func firstIndex(of element: UInt8) -> Int? {
return self.index(of: element)
}
}
#endif
