# UniversalBootstrapDemo

This little package demonstrates how you can use SwiftNIO's universal bootstraps. That allows you to fully support Network.framework on
Apple platforms (if new enough) as well as BSD Sockets on Linux (and older Apple platforms).

## Understanding this example

This example mainly consists of three files:

- [`EventLoopGroupManager.swift`](Sources/UniversalBootstrapDemo/EventLoopGroupManager.swift) which is the main and most important component of this example. It demonstrates a way how you can manage your `EventLoopGroup`, select a matching bootstrap, as well as a TLS implementation.
- [`ExampleHTTPLibrary.swift`](Sources/UniversalBootstrapDemo/ExampleHTTPLibrary.swift) which is an example of how you could implement a basic HTTP library using `EventLoopGroupManager`.
- [`main.swift`](Sources/UniversalBootstrapDemo/main.swift) which is just the driver to run the example programs.

## Examples

### Platform best

To use the best networking available on your platform, try

    swift run UniversalBootstrapDemo https://httpbin.org/get

The output would be for example:

```
# Channel
NIOTransportServices.NIOTSConnectionChannel
```

Ah, we're running on a `NIOTSConnectionChannel` which means Network.framework was used to provide the underlying TCP connection.


```
# ChannelPipeline
                     [I] ↓↑ [O]
                         ↓↑ HTTPRequestEncoder  [handler0]
     HTTPResponseDecoder ↓↑ HTTPResponseDecoder [handler1]
    PrintToStdoutHandler ↓↑                     [handler2]
```
 
 Note, that there is no `NIOSSLClientHandler` in the pipeline despite using HTTPS. That is because Network.framework does also providing
 the TLS support.

```
# HTTP response body
{
  "args": {}, 
  "headers": {
    "Host": "httpbin.org", 
    "X-Amzn-Trace-Id": "Root=1-5eb1a4aa-4004f9686506e319aebd44a1"
  }, 
  "origin": "86.158.121.11", 
  "url": "https://httpbin.org/get"
}
```

### Running with an `EventLoopGroup` selected by somebody else

To imitate your library needing to support an `EventLoopGroup` of unknown backing that was passed in from a client, you may want to try

    swift run UniversalBootstrapDemo --force-bsd-sockets https://httpbin.org/get

The new output is now

```
# Channel
SocketChannel { BaseSocket { fd=9 }, active = true, localAddress = Optional([IPv4]192.168.4.26/192.168.4.26:60266), remoteAddress = Optional([IPv4]35.170.216.115/35.170.216.115:443) }
```

Which uses BSD sockets.

```
# ChannelPipeline
                     [I] ↓↑ [O]
     NIOSSLClientHandler ↓↑ NIOSSLClientHandler [handler3]
                         ↓↑ HTTPRequestEncoder  [handler0]
     HTTPResponseDecoder ↓↑ HTTPResponseDecoder [handler1]
    PrintToStdoutHandler ↓↑                     [handler2]
```

And the `ChannelPipeline` now also contains the `NIOSSLClientHandler` because SwiftNIOSSL now has to take care of TLS encryption.

```
# HTTP response body
{
  "args": {}, 
  "headers": {
    "Host": "httpbin.org", 
    "X-Amzn-Trace-Id": "Root=1-5eb1a543-8fcbadf00a2b9990969c35c0"
  }, 
  "origin": "86.158.121.11", 
  "url": "https://httpbin.org/get"
}
```
