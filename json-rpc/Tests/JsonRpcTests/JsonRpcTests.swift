@testable import JSONRPC
import NIO
import XCTest

final class JSONRPCTests: XCTestCase {
    func testSuccess() {
        let expectedMethod = "foo"
        let expectedParams = RPCObject(["bar", "baz"])
        let expectedResponse = RPCObject("yay")
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = TCPServer(group: eventLoopGroup) { method, params, callback in
            XCTAssertEqual(expectedMethod, method, "expected method to match")
            XCTAssertEqual(expectedParams, params, "expected params to match")
            callback(.success(expectedResponse))
        }
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        let result = try! client.call(method: expectedMethod, params: expectedParams).wait()
        switch result {
        case .success(let response):
            XCTAssertEqual(expectedResponse, response, "expected result ot match")
        case .failure(let error):
            XCTFail("expected to succeed but failed with \(error)")
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testFailure() {
        let expectedMethod = "foo"
        let expectedParams = RPCObject(["bar", "baz"])
        let expectedFailure = RPCError(.invalidMethod)
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = TCPServer(group: eventLoopGroup) { method, params, callback in
            XCTAssertEqual(expectedMethod, method, "expected method to match")
            XCTAssertEqual(expectedParams, params, "expected params to match")
            callback(.failure(expectedFailure))
        }
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        let result = try! client.call(method: expectedMethod, params: expectedParams).wait()
        switch result {
        case .success(let response):
            XCTFail("expected to fail but succeeded with \(response)")
        case .failure(let error):
            XCTAssertEqual(TCPClient.Error(JSONError(expectedFailure)), error, "expected failure ot match")
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testCustomFailure() {
        let expectedMethod = "foo"
        let expectedParams = RPCObject(["bar", "baz"])
        let customError = "boom"
        let expectedFailure = RPCError(.applicationError(customError))
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = TCPServer(group: eventLoopGroup) { method, params, callback in
            XCTAssertEqual(expectedMethod, method, "expected method to match")
            XCTAssertEqual(expectedParams, params, "expected params to match")
            callback(.failure(expectedFailure))
        }
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        let result = try! client.call(method: expectedMethod, params: expectedParams).wait()
        switch result {
        case .success(let response):
            XCTFail("expected to fail but succeeded with \(response)")
        case .failure(let error):
            XCTAssertEqual(TCPClient.Error(JSONError(expectedFailure)), error, "expected failure ot match")
            XCTAssertEqual(customError, error.description, "expected failure ot match")
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testParamTypes() {
        let expectedParams = [RPCObject("foo"),
                              RPCObject(1),
                              RPCObject(true),
                              RPCObject(["foo", "bar"]),
                              RPCObject(["foo": "bar"]),
                              RPCObject([1, 2]),
                              RPCObject(["foo": 1, "bar": 2])]
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let expectedResponse = RPCObject("ok")
        expectedParams.forEach { expectedParams in
            // start server
            let server = TCPServer(group: eventLoopGroup) { _, params, callback in
                XCTAssertEqual(expectedParams, params, "expected params to match")
                callback(.success(expectedResponse))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = TCPClient(group: eventLoopGroup)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.call(method: "test", params: expectedParams).wait()
            switch result {
            case .success(let response):
                XCTAssertEqual(expectedResponse, response, "expected result ot match")
            case .failure(let error):
                XCTFail("expected to succeed but failed with \(error)")
            }
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testResponseTypes() {
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let expectedResponse = [RPCObject("foo"),
                                RPCObject(1),
                                RPCObject(true),
                                RPCObject(["foo", "bar"]),
                                RPCObject(["foo": "bar"]),
                                RPCObject([1, 2]),
                                RPCObject(["foo": 1, "bar": 2])]
        expectedResponse.forEach { expectedResponse in
            // start server
            let server = TCPServer(group: eventLoopGroup) { _, _, callback in
                callback(.success(expectedResponse))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = TCPClient(group: eventLoopGroup)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.call(method: "test", params: .none).wait()
            switch result {
            case .success(let response):
                XCTAssertEqual(expectedResponse, response, "expected result ot match")
            case .failure(let error):
                XCTFail("expected to succeed but failed with \(error)")
            }
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testConcurrency() {
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = TCPServer(group: eventLoopGroup) { method, _, callback in
            callback(.success(RPCObject(method)))
        }
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        let group = DispatchGroup()
        (0 ... Int.random(in: 100 ... 500)).forEach { i in
            group.enter()
            DispatchQueue.global().async {
                let result = try! client.call(method: "\(i)", params: .none).wait()
                switch result {
                case .success(let response):
                    XCTAssertEqual(RPCObject("\(i)"), response, "expected result ot match")
                case .failure(let error):
                    XCTFail("expected to succeed but failed with \(error)")
                }
                group.leave()
            }
        }
        group.wait()
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testBadServerResponse1() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = BadServer(group: eventLoopGroup, framing: framing)
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = TCPClient(group: eventLoopGroup, config: TCPClient.Config(timeout: TimeAmount.milliseconds(100), framing: framing))
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.call(method: "{boom}", params: .none).wait()
            switch result {
            case .success(let response):
                XCTFail("expected to fail but succeeded with \(response)")
            case .failure(let error):
                XCTAssertEqual(TCPClient.Error.Kind.invalidServerResponse, error.kind, "expected error ot match")
            }
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testBadServerResponse2() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = BadServer(group: eventLoopGroup, framing: framing)
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = TCPClient(group: eventLoopGroup, config: TCPClient.Config(timeout: TimeAmount.milliseconds(100), framing: framing))
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.call(method: "boom", params: .none).wait()
            switch result {
            case .success(let response):
                XCTFail("expected to fail but succeeded with \(response)")
            case .failure(let error):
                XCTAssertEqual(TCPClient.Error.Kind.invalidServerResponse, error.kind, "expected error ot match")
            }
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testBadServerResponse3() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = BadServer(group: eventLoopGroup, framing: framing)
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = TCPClient(group: eventLoopGroup, config: TCPClient.Config(timeout: TimeAmount.milliseconds(100), framing: framing))
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.call(method: "do not encode", params: .none).wait()
            switch result {
            case .success(let response):
                XCTFail("expected to fail but succeeded with \(response)")
            case .failure(let error):
                XCTAssertEqual(TCPClient.Error.Kind.invalidServerResponse, error.kind, "expected error ot match")
            }
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testServerDisconnect() {
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = BadServer(group: eventLoopGroup, framing: .default)
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        XCTAssertThrowsError(try client.call(method: "disconnect", params: .none).wait()) { error in
            XCTAssertEqual(error as! ClientError, ClientError.connectionResetByPeer)
        }
        // perform another method call
        XCTAssertThrowsError(try client.call(method: "disconnect", params: .none).wait()) { error in
            XCTAssertEqual(error as! NIO.ChannelError, NIO.ChannelError.ioOnClosedChannel)
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testClientTimeout() {
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = BadServer(group: eventLoopGroup, framing: .default)
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = TCPClient(group: eventLoopGroup, config: TCPClient.Config(timeout: TimeAmount.milliseconds(100)))
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform the method call
        XCTAssertThrowsError(try client.call(method: "timeout", params: .none).wait()) { error in
            XCTAssertEqual(error as! ClientError, ClientError.timeout)
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }

    func testBadClientRequest1() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = TCPServer(group: eventLoopGroup, config: TCPServer.Config(timeout: TimeAmount.milliseconds(100), framing: framing)) { _, _, callback in
                callback(.success(RPCObject("yay")))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = BadClient(group: eventLoopGroup, framing: framing)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.request(string: "{boom}").wait()
            XCTAssertNil(result.result, "expected to fail but succeeded with \(result.result!)")
            XCTAssertNotNil(result.error, "expected error to be non-nil")
            XCTAssertEqual(result.error!.code, JSONErrorCode.parseError.rawValue, "expected error ot match")
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testBadClientRequest2() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = TCPServer(group: eventLoopGroup, config: TCPServer.Config(timeout: TimeAmount.milliseconds(100), framing: framing)) { _, _, callback in
                callback(.success(RPCObject("yay")))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = BadClient(group: eventLoopGroup, framing: framing)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.request(string: "boom").wait()
            XCTAssertNil(result.result, "expected to fail but succeeded with \(result.result!)")
            XCTAssertNotNil(result.error, "expected error to be non-nil")
            XCTAssertEqual(result.error!.code, JSONErrorCode.parseError.rawValue, "expected error ot match")
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testBadClientRequest3() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = TCPServer(group: eventLoopGroup, config: TCPServer.Config(timeout: TimeAmount.milliseconds(100), framing: framing)) { _, _, callback in
                callback(.success(RPCObject("yay")))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = BadClient(group: eventLoopGroup, framing: framing)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.request(string: "do not encode").wait()
            XCTAssertNil(result.result, "expected to fail but succeeded with \(result.result!)")
            XCTAssertNotNil(result.error, "expected error to be non-nil")
            XCTAssertEqual(result.error!.code, JSONErrorCode.parseError.rawValue, "expected error ot match")
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testBadClientRequest4() {
        Framing.allCases.forEach { framing in
            print("===== testing with \(framing) framing")
            let address = ("127.0.0.1", 8000)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            // start server
            let server = TCPServer(group: eventLoopGroup, config: TCPServer.Config(timeout: TimeAmount.milliseconds(100), framing: framing)) { _, _, callback in
                callback(.success(RPCObject("yay")))
            }
            _ = try! server.start(host: address.0, port: address.1).wait()
            // connect client
            let client = BadClient(group: eventLoopGroup, framing: framing)
            _ = try! client.connect(host: address.0, port: address.1).wait()
            // perform the method call
            let result = try! client.request(string: String(repeating: "*", count: 1_000_001)).wait()
            XCTAssertNil(result.result, "expected to fail but succeeded with \(result.result!)")
            XCTAssertNotNil(result.error, "expected error to be non-nil")
            XCTAssertEqual(result.error!.code, JSONErrorCode.invalidRequest.rawValue, "expected error ot match")
            // shutdown
            try! client.disconnect().wait()
            try! server.stop().wait()
        }
    }

    func testDisconnectAfterBadClientRequest() {
        let address = ("127.0.0.1", 8000)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        // start server
        let server = TCPServer(group: eventLoopGroup, config: TCPServer.Config(timeout: TimeAmount.milliseconds(100))) { _, _, callback in
            callback(.success(RPCObject("yay")))
        }
        _ = try! server.start(host: address.0, port: address.1).wait()
        // connect client
        let client = BadClient(group: eventLoopGroup, framing: .default)
        _ = try! client.connect(host: address.0, port: address.1).wait()
        // perform a bad method call
        let response = try! client.request(string: "boom").wait()
        XCTAssertNil(response.result, "expected to fail but succeeded with \(response.result!)")
        XCTAssertNotNil(response.error, "expected error to be non-nil")
        XCTAssertEqual(response.error!.code, JSONErrorCode.parseError.rawValue, "expected error ot match")
        // perform another call
        let request = JSONRequest(id: UUID().uuidString, method: "foo", params: .none)
        let json = try! JSONEncoder().encode(request)
        XCTAssertThrowsError(try client.request(string: String(data: json, encoding: .utf8)!).wait()) { error in
            XCTAssertEqual(error as! NIO.ChannelError, NIO.ChannelError.ioOnClosedChannel)
        }
        // shutdown
        try! client.disconnect().wait()
        try! server.stop().wait()
    }
}

private class BadServer {
    private let group: EventLoopGroup
    private let framing: Framing
    private var channel: Channel?

    public init(group: EventLoopGroup, framing: Framing) {
        self.group = group
        self.framing = framing
    }

    func start(host: String, port: Int) -> EventLoopFuture<BadServer> {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in channel.pipeline.addHandler(Handler(framing: self.framing)) }
        return bootstrap.bind(host: host, port: port).flatMap { channel in
            self.channel = channel
            return channel.eventLoop.makeSucceededFuture(self)
        }
    }

    func stop() -> EventLoopFuture<Void> {
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(TestError.badState)
        }
        channel.close(promise: nil)
        return channel.closeFuture
    }

    private class Handler: ChannelInboundHandler {
        public typealias InboundIn = ByteBuffer
        public typealias OutboundOut = ByteBuffer

        private let framing: Framing

        public init(framing: Framing) {
            self.framing = framing
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            let data = decode(&buffer, self.framing)
            do {
                let request = try JSONDecoder().decode(JSONRequest.self, from: data)
                if "timeout" == request.method {
                    return
                }
                if "disconnect" == request.method {
                    return context.channel.close(promise: nil)
                }
                let encoded = "do not encode" != request.method ? encode(request.method, self.framing) : request.method
                var bufffer2 = context.channel.allocator.buffer(capacity: encoded.utf8.count)
                bufffer2.writeBytes(encoded.utf8)
                context.writeAndFlush(NIOAny(bufffer2), promise: nil)
            } catch {
                context.fireErrorCaught(error)
            }
        }
    }
}

private class BadClient {
    public let group: EventLoopGroup
    private let framing: Framing
    private var channel: Channel?

    public init(group: EventLoopGroup, framing: Framing) {
        self.group = group
        self.framing = framing
        self.channel = nil
    }

    public func connect(host: String, port: Int) -> EventLoopFuture<BadClient> {
        let bootstrap = ClientBootstrap(group: self.group)
            .channelInitializer { channel in channel.pipeline.addHandler(Handler(framing: self.framing)) }
        return bootstrap.connect(host: host, port: port).flatMap { channel in
            self.channel = channel
            return channel.eventLoop.makeSucceededFuture(self)
        }
    }

    public func disconnect() -> EventLoopFuture<Void> {
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(TestError.badState)
        }
        channel.close(promise: nil)
        return channel.closeFuture
    }

    public func request(string: String) -> EventLoopFuture<JSONResponse> {
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(TestError.badState)
        }
        let promise: EventLoopPromise<JSONResponse> = channel.eventLoop.makePromise()
        let encoded = string != "do not encode" ? encode(string, self.framing) : string
        var buffer = channel.allocator.buffer(capacity: encoded.utf8.count)
        buffer.writeString(encoded)
        let future = channel.writeAndFlush(RequestWrapper(promise: promise, request: buffer))
        future.cascadeFailure(to: promise)
        return future.flatMap {
            promise.futureResult
        }
    }

    private class Handler: ChannelInboundHandler, ChannelOutboundHandler {
        public typealias InboundIn = ByteBuffer
        public typealias OutboundIn = RequestWrapper
        public typealias OutboundOut = ByteBuffer

        private let framing: Framing
        private var queue = CircularBuffer<EventLoopPromise<JSONResponse>>()

        public init(framing: Framing) {
            self.framing = framing
        }

        public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let wrapper = self.unwrapOutboundIn(data)
            queue.append(wrapper.promise)
            context.write(wrapOutboundOut(wrapper.request), promise: promise)
        }

        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let promise = queue.removeFirst()
            var buffer = unwrapInboundIn(data)
            let data = decode(&buffer, self.framing)
            do {
                let response = try JSONDecoder().decode(JSONResponse.self, from: data)
                promise.succeed(response)
            } catch {
                promise.fail(error)
            }
        }
    }

    private struct RequestWrapper {
        let promise: EventLoopPromise<JSONResponse>
        let request: ByteBuffer
    }
}

private enum TestError: Error {
    case badState
}

private func encode(_ text: String, _ framing: Framing) -> String {
    switch framing {
    case .default:
        return text + "\r\n"
    case .jsonpos:
        return String(text.utf8.count, radix: 16).leftPadding(toLength: 8, withPad: "0") +
            ":" +
            text +
            "\n"
    case .brute:
        return text
    }
}

private func decode(_ buffer: inout ByteBuffer, _ framing: Framing) -> Data {
    switch framing {
    case .default:
        return buffer.readData(length: buffer.readableBytes - 2)!
    case .jsonpos:
        buffer.moveReaderIndex(to: 9)
        return buffer.readData(length: buffer.readableBytes - 1)!
    case .brute:
        return buffer.readData(length: buffer.readableBytes)!
    }
}
