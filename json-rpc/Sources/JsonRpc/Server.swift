import Foundation
import NIO

public final class TCPServer {
    private let group: MultiThreadedEventLoopGroup
    private let config: Config
    private var channel: Channel?
    private let closure: RPCClosure

    public init(group: MultiThreadedEventLoopGroup, config: Config = Config(), closure: @escaping RPCClosure) {
        self.group = group
        self.config = config
        self.closure = closure
        self.state = .initializing
    }

    deinit {
        assert(.stopped == self.state)
    }

    public func start(host: String, port: Int) -> EventLoopFuture<TCPServer> {
        assert(.initializing == self.state)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                return channel.pipeline.addTimeoutHandlers(self.config.timeout)
                    .flatMap {
                        channel.pipeline.addFramingHandlers(framing: self.config.framing)
                    }.flatMap {
                        channel.pipeline.addHandlers([CodableCodec<JSONRequest, JSONResponse>(),
                                                      Handler(self.closure)])
                    }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

        self.state = .starting("\(host):\(port)")
        return bootstrap.bind(host: host, port: port).flatMap { channel in
            self.channel = channel
            self.state = .started
            return channel.eventLoop.makeSucceededFuture(self)
        }
    }

    public func stop() -> EventLoopFuture<Void> {
        if .started != self.state {
            return self.group.next().makeFailedFuture(ServerError.notReady)
        }
        guard let channel = self.channel else {
            return self.group.next().makeFailedFuture(ServerError.notReady)
        }
        self.state = .stopping
        channel.closeFuture.whenComplete { _ in
            self.state = .stopped
        }
        return channel.close()
    }

    private var _state = State.initializing
    private let lock = NSLock()
    private var state: State {
        get {
            return self.lock.withLock {
                _state
            }
        }
        set {
            self.lock.withLock {
                _state = newValue
                print("\(self) \(_state)")
            }
        }
    }

    private enum State: Equatable {
        case initializing
        case starting(String)
        case started
        case stopping
        case stopped
    }

    public struct Config {
        public let timeout: TimeAmount
        public let framing: Framing

        public init(timeout: TimeAmount = TimeAmount.seconds(5), framing: Framing = .default) {
            self.timeout = timeout
            self.framing = framing
        }
    }
}

private class Handler: ChannelInboundHandler {
    public typealias InboundIn = JSONRequest
    public typealias OutboundOut = JSONResponse

    private let closure: RPCClosure

    public init(_ closure: @escaping RPCClosure) {
        self.closure = closure
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)
        self.closure(request.method, RPCObject(request.params), { result in
            let response: JSONResponse
            switch result {
            case .success(let handlerResult):
                print("rpc handler returned success", handlerResult)
                response = JSONResponse(id: request.id, result: handlerResult)
            case .failure(let handlerError):
                print("rpc handler returned failure", handlerError)
                response = JSONResponse(id: request.id, error: handlerError)
            }
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        })
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let remoteAddress = context.remoteAddress {
            print("client", remoteAddress, "error", error)
        }
        switch error {
        case CodecError.badFraming, CodecError.badJSON:
            let response = JSONResponse(id: "unknown", errorCode: .parseError, error: error)
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        case CodecError.requestTooLarge:
            let response = JSONResponse(id: "unknown", errorCode: .invalidRequest, error: error)
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        default:
            let response = JSONResponse(id: "unknown", errorCode: .internalError, error: error)
            context.channel.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
        }
        // close the client connection
        context.close(promise: nil)
    }

    public func channelActive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            print("client", remoteAddress, "connected")
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let remoteAddress = context.remoteAddress {
            print("client", remoteAddress, "disconnected")
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if (event as? IdleStateHandler.IdleStateEvent) == .read {
            self.errorCaught(context: context, error: ServerError.timeout)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

internal enum ServerError: Error {
    case notReady
    case cantBind
    case timeout
}
