import JSONRPC
import NIO

guard CommandLine.arguments.count > 1 else {
    fatalError("invalid arguments")
}

let address = ("127.0.0.1", 8000)
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let client = TCPClient(group: eventLoopGroup)
_ = try! client.connect(host: address.0, port: address.1).wait()
// perform the method call
let method = CommandLine.arguments[1]
let params = CommandLine.arguments[2...].map { Int($0) }.compactMap { $0 }
let result = try! client.call(method: method, params: RPCObject(params)).wait()
switch result {
case .success(let response):
    print("\(response)")
case .failure(let error):
    print("failed with \(error)")
}
// shutdown
try! client.disconnect().wait()
