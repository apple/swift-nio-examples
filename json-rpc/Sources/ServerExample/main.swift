//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import JSONRPC
import NIOCore
import NIOPosix

private final class Calculator: Sendable {
    func handle(method: String, params: RPCObject, callback: (RPCResult) -> Void) {
        switch method.lowercased() {
        case "add":
            self.add(params: params, callback: callback)
        case "subtract":
            self.subtract(params: params, callback: callback)
        default:
            callback(.failure(RPCError(.invalidMethod)))
        }
    }

    func add(params: RPCObject, callback: (RPCResult) -> Void) {
        let values = extractNumbers(params)
        guard values.count > 1 else {
            return callback(.failure(RPCError(.invalidParams("expected 2 arguments or more"))))
        }
        return callback(.success(.integer(values.reduce(0, +))))
    }

    func subtract(params: RPCObject, callback: (RPCResult) -> Void) {
        let values = extractNumbers(params)
        guard values.count > 1 else {
            return callback(.failure(RPCError(.invalidParams("expected 2 arguments or more"))))
        }
        return callback(.success(.integer(values[1...].reduce(values[0], -))))
    }

    func extractNumbers(_ object: RPCObject) -> [Int] {
        switch object {
        case .list(let items):
            return items.map {
                switch $0 {
                case .integer(let value):
                    return value
                default:
                    return nil
                }
            }.compactMap { $0 }
        default:
            return []
        }
    }
}

private func trap(signal sig: Signal, handler: @escaping (Signal) -> Void) -> DispatchSourceSignal {
    let queue = DispatchQueue(label: "ExampleServer")
    let signalSource = DispatchSource.makeSignalSource(signal: sig.rawValue, queue: queue)
    signal(sig.rawValue, SIG_IGN)
    signalSource.setEventHandler(handler: {
        signalSource.cancel()
        handler(sig)
    })
    signalSource.resume()
    return signalSource
}

private enum Signal: Int32 {
    case HUP = 1
    case INT = 2
    case QUIT = 3
    case ABRT = 6
    case KILL = 9  // ignore-unacceptable-language
    case ALRM = 14
    case TERM = 15
}

private let group = DispatchGroup()
private let address = ("127.0.0.1", 8000)
private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
// start server
private let calculator = Calculator()
private let server = TCPServer(group: eventLoopGroup, closure: calculator.handle)
_ = try! server.start(host: address.0, port: address.1).wait()

// trap
group.enter()
let signalSource = trap(signal: Signal.INT) { signal in
    print("intercepted signal: \(signal)")
    server.stop().whenComplete { _ in
        group.leave()
    }
}

group.wait()
// cleanup
signalSource.cancel()
