# backpressure-file-io-channel

This example shows how you can propagate backpressure from the file system into the Channel.

First, let's establish what it means to propagate backpressure from the file system into the Channel. Let's assume we have a HTTP server
that accepts arbitrary amounts of data and writes it to the file system. If data is received faster over the network than we can write it to the
disk, then the server runs into trouble: It can now only either buffer the data in memory or (at least in theory) drop it on the floor. The former
would easily be usable as a denial of service exploit, the latter means that the server isn't able to provide its core functioniality.

Backpressure is the mechanism to resolve the the buffering issue above. The idea is that the server stops accepting more data from the client than
it can write to disk. Because HTTP runs over TCP which has flow-control built in, the TCP stacks will then lower the server's receive window
size which means that the client gets slowed down or completely stopped from sending any data. Once the server finishes writing previously
received data to disk, it starts draining the receive buffer which then make TCP's flow control raise the window sizes which allows the client
to send further data.

## Backpressure in SwiftNIO

In SwiftNIO, backpressure is propagated by stopping calls to the outbound [`read`](https://apple.github.io/swift-nio/docs/current/NIO/Protocols/_ChannelOutboundHandler.html#/s:3NIO23_ChannelOutboundHandlerP4read7contextyAA0bD7ContextC_tF) event.

By default, `Channel`s in SwiftNIO have the [`autoRead`](https://apple.github.io/swift-nio/docs/current/NIO/Structs/ChannelOptions.html#/s:3NIO14ChannelOptionsV8autoReadAC5TypesO04AutoE6OptionVvpZ)
`ChannelOption` enabled. When `autoRead` is enabled, SwiftNIO will automatically send a `read` (note, this is a very different event than the
inbound `channelRead` event that is used to deliver data) event when the previous read burst has
completed (signalled by the inbound [`channelReadComplete`](https://apple.github.io/swift-nio/docs/current/NIO/Protocols/_ChannelInboundHandler.html#/s:3NIO22_ChannelInboundHandlerP19channelReadComplete7contextyAA0bD7ContextC_tF)
event). Therefore, you may be unaware of the existence of the `read` event despite having used SwiftNIO before.

Suppressing the `read` event is one of the key demonstrations of this example. The fundamental idea is that to start with we let `read` flow
through the `ChannelPipeline` until we have an HTTP request and the first bits of its request body. Once we received the first bits of the
HTTP request body, we will _suppress_ `read` from flowing through the `ChannelPipeline` which means that SwiftNIO will stop reading
further data from the network.
When SwiftNIO stops reading further data from the network, this means that TCP flow control will kick in and slow the client down sending
more of the HTTP request body (once both the client's send and the server's receive buffer are full).
Once the disk writes of the previously received chunks have completed, we will issue a `read` event (assuming we held up at least one). From
then on, `read` events will flow freely until the next bit of the HTTP request body is received, when they'll be suppressed again.

This means however fast the client or however slow the disk is, we should be able to stream arbitarily size HTTP request bodies to disk in
constant memory.

## Example implementation

The implementation in this example creates a state machine called [`FileIOChannelWriteCoordinator.swift`](Sources/FileIOChannelWriteCoordinator.swift)
which gets notified about the events that happen (both on the `ChannelPipeline` and from `NonBlockingFileIO`). Every input to the state
machine also returns an `Action` which describes what operation needs to be done next.

The state machine is deliberately implemented completely free of any I/O or any side effects which is why it returns `Action`.

Because the state machine doesn't do any I/O, it's crucial to tell it about any relevant event that happens in the system.

The full set of inputs to the state machine are


- Tell the state machine that a new HTTP request started.
    ```swift
    internal mutating func didReceiveRequestBegin(targetPath: String) -> Action
    ```

- Tell the state machine that we received more bytes of the request body.
    ```swift
    internal mutating func didReceiveRequestBodyBytes(_ bytes: ByteBuffer) -> Action
    ```

- Tell the state machine we received the HTTP request end.
    ```swift
    internal mutating func didReceiveRequestEnd() -> Action
    ```

- Tell the state machine that we've just finished writing one previously received chunk of the HTTP request body to disk.
    ```swift
    internal mutating func didFinishWritingOneChunkToFile() -> Action
    ```
    
-  Tell the state machine we finished opening the target file.
    ```swift
    internal mutating func didOpenTargetFile(_ fileHandle: NIOFileHandle) -> Action
    ```
    
- Tell the state machine that we've hit an error.
    ```swift
    internal mutating func didError(_ error: Error) -> Action
    ```

The `Action` returned by the state machine is one of

- Do nothing, we are waiting for some event: `case nothingWeAreWaiting`
- Start writing chunks to the target file: `case startWritingToTargetFile`
- Open the file: `case openFile(String)`
- We are done, please close the file handle. If an error occured, it is sent here too: `case processingCompletedDiscardResources(NIOFileHandle?, Error?)`
- Just close the file, we have previously completed processing: `case closeFile(NIOFileHandle)`

`SaveEverythingHTTPHandler` is the `ChannelHandler` which drives the state machines with the events it receives through the
`ChannelPipeline`. Additionally, it tells the state machine about the results of the I/O operations it starts (when `Action` tells it to).
