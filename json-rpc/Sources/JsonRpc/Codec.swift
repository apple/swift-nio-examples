import Foundation
import NIO
import NIOFoundationCompat

private let maxPayload = 1_000_000 // 1MB

internal extension ChannelPipeline {
    func addTimeoutHandlers(_ timeout: TimeAmount) -> EventLoopFuture<Void> {
        return self.addHandlers([IdleStateHandler(readTimeout: timeout), HalfCloseOnTimeout()])
    }
}

internal extension ChannelPipeline {
    func addFramingHandlers(framing: Framing) -> EventLoopFuture<Void> {
        switch framing {
        case .jsonpos:
            let framingHandler = JSONPosCodec()
            return self.addHandlers([ByteToMessageHandler(framingHandler),
                                     MessageToByteHandler(framingHandler)])
        case .brute:
            let framingHandler = BruteForceCodec<JSONResponse>()
            return self.addHandlers([ByteToMessageHandler(framingHandler),
                                     MessageToByteHandler(framingHandler)])
        case .default:
            let framingHandler = NewlineEncoder()
            return self.addHandlers([ByteToMessageHandler(framingHandler),
                                     MessageToByteHandler(framingHandler)])
        }
    }
}

// aggregate bytes till delimiter and add delimiter at end
internal final class NewlineEncoder: ByteToMessageDecoder, MessageToByteEncoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let delimiter1 = UInt8(ascii: "\r")
    private let delimiter2 = UInt8(ascii: "\n")

    private var lastIndex = 0

    // inbound
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes < maxPayload else {
            throw CodecError.requestTooLarge
        }
        guard buffer.readableBytes >= 3 else {
            return .needMoreData
        }

        // try to find a payload by looking for a \r\n delimiter
        let readableBytesView = buffer.readableBytesView.dropFirst(self.lastIndex)
        guard let index = readableBytesView.firstIndex(of: delimiter2) else {
            self.lastIndex = buffer.readableBytes
            return .needMoreData
        }
        guard readableBytesView[index - 1] == delimiter1 else {
            return .needMoreData
        }

        // slice the buffer
        let length = index - buffer.readerIndex - 1
        let slice = buffer.readSlice(length: length)!
        buffer.moveReaderIndex(forwardBy: 2)
        self.lastIndex = 0
        // call next handler
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        while try self.decode(context: context, buffer: &buffer) == .continue {}
        if buffer.readableBytes > buffer.readerIndex {
            throw CodecError.badFraming
        }
        return .needMoreData
    }

    // outbound
    public func encode(data: OutboundIn, out: inout ByteBuffer) throws {
        var payload = data
        // original data
        out.writeBuffer(&payload)
        // add delimiter
        out.writeBytes([delimiter1, delimiter2])
    }
}

// https://www.poplatek.fi/payments/jsonpos/transport
// JSON/RPC messages are framed with the following format (in the following byte-by-byte order):
// 8 bytes: ASCII lowercase hex-encoded length (LEN) of the actual JSON/RPC message (receiver MUST accept both uppercase and lowercase)
// 1 byte: a colon (":", 0x3a), not included in LEN
// LEN bytes: a JSON/RPC message, no leading or trailing whitespace
// 1 byte: a newline (0x0a), not included in LEN
internal final class JSONPosCodec: ByteToMessageDecoder, MessageToByteEncoder {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let newline = UInt8(ascii: "\n")
    private let colon = UInt8(ascii: ":")

    // inbound
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes < maxPayload else {
            throw CodecError.requestTooLarge
        }
        guard buffer.readableBytes >= 10 else {
            return .needMoreData
        }

        let readableBytesView = buffer.readableBytesView
        // assuming we have the format <length>:<payload>\n
        let lengthView = readableBytesView.prefix(8) // contains <length>
        let fromColonView = readableBytesView.dropFirst(8) // contains :<payload>\n
        let payloadView = fromColonView.dropFirst() // contains <payload>\n
        let hex = String(decoding: lengthView, as: Unicode.UTF8.self)

        guard let payloadSize = Int(hex, radix: 16) else {
            throw CodecError.badFraming
        }
        guard self.colon == fromColonView.first! else {
            throw CodecError.badFraming
        }
        guard payloadView.count >= payloadSize + 1, self.newline == payloadView.last else {
            return .needMoreData
        }

        // slice the buffer
        assert(payloadView.startIndex == readableBytesView.startIndex + 9)
        let slice = buffer.getSlice(at: payloadView.startIndex, length: payloadSize)!
        buffer.moveReaderIndex(to: payloadSize + 10)
        // call next handler
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        while try self.decode(context: context, buffer: &buffer) == .continue {}
        if buffer.readableBytes > buffer.readerIndex {
            throw CodecError.badFraming
        }
        return .needMoreData
    }

    // outbound
    public func encode(data: OutboundIn, out: inout ByteBuffer) throws {
        var payload = data
        // length
        out.writeString(String(payload.readableBytes, radix: 16).leftPadding(toLength: 8, withPad: "0"))
        // colon
        out.writeBytes([colon])
        // payload
        out.writeBuffer(&payload)
        // newline
        out.writeBytes([newline])
    }
}

// no delimeter is provided, brute force try to decode the json
internal final class BruteForceCodec<T>: ByteToMessageDecoder, MessageToByteEncoder where T: Decodable {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let last = UInt8(ascii: "}")

    private var lastIndex = 0

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes < maxPayload else {
            throw CodecError.requestTooLarge
        }

        // try to find a payload by looking for a json payload, first rough cut is looking for a trailing }
        let readableBytesView = buffer.readableBytesView.dropFirst(self.lastIndex)
        guard let _ = readableBytesView.firstIndex(of: last) else {
            self.lastIndex = buffer.readableBytes
            return .needMoreData
        }

        // try to confirm its a json payload by brute force decoding
        let length = buffer.readableBytes
        let data = buffer.getData(at: buffer.readerIndex, length: length)!
        do {
            _ = try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            self.lastIndex = buffer.readableBytes
            return .needMoreData
        }

        // slice the buffer
        let slice = buffer.readSlice(length: length)!
        self.lastIndex = 0
        // call next handler
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        while try self.decode(context: context, buffer: &buffer) == .continue {}
        if buffer.readableBytes > buffer.readerIndex {
            throw CodecError.badFraming
        }
        return .needMoreData
    }

    // outbound
    public func encode(data: OutboundIn, out: inout ByteBuffer) throws {
        var payload = data
        out.writeBuffer(&payload)
    }
}

// bytes to codable and back
internal final class CodableCodec<In, Out>: ChannelInboundHandler, ChannelOutboundHandler where In: Decodable, Out: Encodable {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = In
    public typealias OutboundIn = Out
    public typealias OutboundOut = ByteBuffer

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // inbound
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let data = buffer.readData(length: buffer.readableBytes)!
        do {
            print("--> decoding \(String(decoding: data[data.startIndex ..< min(data.startIndex + 100, data.endIndex)], as: UTF8.self))")
            let decodable = try self.decoder.decode(In.self, from: data)
            // call next handler
            context.fireChannelRead(wrapInboundOut(decodable))
        } catch let error as DecodingError {
            context.fireErrorCaught(CodecError.badJSON(error))
        } catch {
            context.fireErrorCaught(error)
        }
    }

    // outbound
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let encodable = self.unwrapOutboundIn(data)
            let data = try encoder.encode(encodable)
            print("<-- encoding \(String(decoding: data, as: UTF8.self))")
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.write(wrapOutboundOut(buffer), promise: promise)
        } catch let error as EncodingError {
            promise?.fail(CodecError.badJSON(error))
        } catch {
            promise?.fail(error)
        }
    }
}

internal final class HalfCloseOnTimeout: ChannelInboundHandler {
    typealias InboundIn = Any

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent {
            // this will trigger ByteToMessageDecoder::decodeLast which is required to
            // recognize partial frames
            context.fireUserInboundEventTriggered(ChannelEvent.inputClosed)
        }
        context.fireUserInboundEventTriggered(event)
    }
}

internal enum CodecError: Error {
    case badFraming
    case badJSON(Error)
    case requestTooLarge
}
