
import NIO

class LimitHandler: ChannelDuplexHandler {
    
    typealias OutboundIn = Channel
    typealias InboundIn = Channel
    
    let connectionLimit: Int
    var currentConnections = 0
    
    init(connectionLimit: Int) {
        self.connectionLimit = connectionLimit
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channel = self.unwrapInboundIn(data)
        context.fireChannelRead(data)
        self.currentConnections += 1
        channel.closeFuture.whenSuccess {
            context.read()
        }
    }
    
    func read(context: ChannelHandlerContext) {
        guard self.currentConnections < self.connectionLimit else {
            return
        }
        context.read()
    }
    
}

class EchoChannelHandler: ChannelInboundHandler {
    
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var input = self.unwrapInboundIn(data)
        var buffer = context.channel.allocator.buffer(capacity: input.readableBytes + 6)
        buffer.writeString("Echo: ")
        buffer.writeBuffer(&input)
        let output = self.wrapInboundOut(buffer)
        context.writeAndFlush(output, promise: nil)
    }
    
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
try ServerBootstrap(group: group)
.serverChannelInitializer({ (channel) -> EventLoopFuture<Void> in
    channel.pipeline.addHandler(LimitHandler(connectionLimit: 1))
})
.serverChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
.serverChannelOption(ChannelOptions.backlog, value: 1)
.childChannelInitializer { (channel) -> EventLoopFuture<Void> in
    channel.pipeline.addHandler(EchoChannelHandler())
}
.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
.bind(host: "127.0.0.1", port: 4321)
.wait()
.closeFuture
.wait()
