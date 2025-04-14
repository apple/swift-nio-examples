//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// HTTPBenchmarkApp - A toy HTTP server for benchmarking various real-world
// scenarios, including file transfer, concurrency, partial I/O, and lock contention.
// 
// In addition to its HTTP endpoints, when run with --run-all-benchmarks the app
// will execute all consolidated benchmarks for these main workloads and output
// a consolidated report (with timing percentiles: p0, p25, p50, p75, p90, p99, p100).
//
// The consolidated benchmarks run iteratively without needing the --collect-benchmarks flag.
// Optionally, the --use-io-uring flag allows experimentation with NIOTSEventLoopGroup 
// (and Linux's io_uring support when built with proper flags).
//
//===----------------------------------------------------------------------===//

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOTransportServices
import ArgumentParser

// MARK: - Measurement Helpers

/// Runs a block and returns its elapsed time in milliseconds.
func measure<T>(_ block: () throws -> T) rethrows -> (result: T, elapsedMs: Double) {
    let start = DispatchTime.now()
    let result = try block()
    let end = DispatchTime.now()
    let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    return (result, elapsed)
}

/// Runs a block repeatedly for a specified number of iterations,
/// collects elapsed times, computes timing percentiles, and returns these statistics along with the sample count.
func measureMultiple<T>(iterations: Int, block: () throws -> T) rethrows -> (result: T?, stats: (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double, samples: Int)) {
    var samples = [Double]()
    var lastResult: T? = nil
    for _ in 0..<iterations {
        let start = DispatchTime.now()
        lastResult = try block()
        let end = DispatchTime.now()
        let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        samples.append(elapsed)
    }
    let stats = calculateStatistics(from: samples)
    return (lastResult, (stats.p0, stats.p25, stats.p50, stats.p75, stats.p90, stats.p99, stats.p100, samples.count))
}

/// Computes percentiles (p0, p25, p50, p75, p90, p99, p100) from an array of elapsed times.
func calculateStatistics(from samples: [Double]) -> (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double) {
    let sorted = samples.sorted()
    let count = sorted.count
    let p0 = sorted.first ?? 0.0
    let p25 = sorted[Int(Double(count - 1) * 0.25)]
    let p50 = sorted[Int(Double(count - 1) * 0.50)]
    let p75 = sorted[Int(Double(count - 1) * 0.75)]
    let p90 = sorted[Int(Double(count - 1) * 0.90)]
    let p99 = sorted[Int(Double(count - 1) * 0.99)]
    let p100 = sorted.last ?? 0.0
    return (p0, p25, p50, p75, p90, p99, p100)
}

/// Returns a table formatted with the benchmark statistics.
func formatBenchmarkTable(metric: String, stats: (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double, samples: Int)) -> String {
    let paddedMetric = metric.padding(toLength: 24, withPad: " ", startingAt: 0)
    let line = String(format: "│ %@ │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7d │",
                      paddedMetric,
                      stats.p0, stats.p25, stats.p50, stats.p75, stats.p90, stats.p99, stats.p100,
                      stats.samples)
    
    let table = """
    ╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
    │ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
    ╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
    \(line)
    ╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
    """
    return table
}

// MARK: - Command-Line Interface & App Execution

struct HTTPBenchmarkApp: ParsableCommand {
    @Option(help: "The host address to bind on (default: 127.0.0.1)")
    var host: String = "127.0.0.1"
    
    @Option(help: "The port to bind on (default: 8080)")
    var port: Int = 8080
    
    @Flag(help: "Use Network.framework backend (NIOTSEventLoopGroup) and experimental io_uring support")
    var useIOUring: Bool = false
    
    @Flag(help: "Run all consolidated benchmarks (for file transfer, concurrency, partial I/O, and lock contention) and print a report")
    var runAllBenchmarks: Bool = false

    func run() throws {
        // If the consolidated benchmarks flag is set, run the benchmarks and exit.
        if runAllBenchmarks {
            try runConsolidatedBenchmarks()
            return
        }
        
        // Otherwise, start the HTTP server.
        let group: EventLoopGroup
        if useIOUring {
            #if canImport(NIOTransportServices)
            print("Using NIOTSEventLoopGroup (Network.framework, potential io_uring on Linux)")
            group = NIOTSEventLoopGroup(loopCount: System.coreCount)
            #else
            throw RuntimeError.message("Network.framework backend not available on this platform.")
            #endif
        } else {
            group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }
        
        let bootstrap: ServerBootstrap
        if useIOUring {
            #if canImport(NIOTransportServices)
            bootstrap = NIOTSListenerBootstrap(group: group as! NIOTSEventLoopGroup)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    return channel.pipeline.addHandler(BenchmarkRequestHandler())
                }
            #else
            fatalError("NIOTSEventLoopGroup not available on this platform.")
            #endif
        } else {
            bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(BenchmarkRequestHandler())
                    }
                }
        }
        
        // Bind to host and port.
        let channel = try bootstrap.bind(host: host, port: port).wait()
        print("HTTPBenchmarkApp running on \(host):\(port)")
        try channel.closeFuture.wait()
        try group.syncShutdownGracefully()
    }
    
    /// Runs consolidated benchmarks for the main endpoints (file transfer, concurrency, partial I/O, lock contention)
    /// and prints a consolidated report.
    func runConsolidatedBenchmarks() throws {
        print("Running consolidated benchmarks...\n")
        
        // File Transfer Benchmark: Simulate streaming a large file by reading it in chunks.
        // We simulate this by iterating over a large buffer.
        let largeFileSizeMB = 100
        let totalBytes = largeFileSizeMB * 1024 * 1024
        let largeFileBenchmark = try measureMultiple(iterations: 10) {
            var buffer = ByteBufferAllocator().buffer(capacity: totalBytes)
            buffer.writeBytes([UInt8](repeating: 0x41, count: totalBytes))
            var localBuffer = buffer
            let chunkSize = 64 * 1024
            while localBuffer.readableBytes > 0 {
                _ = localBuffer.readSlice(length: min(chunkSize, localBuffer.readableBytes))
            }
        }
        let largeFileReport = formatBenchmarkTable(metric: "LargeFile (ms)", stats: largeFileBenchmark.stats)
        
        // Concurrency Benchmark: Sum operations using concurrent tasks.
        let concurrencyBenchmark = try measureMultiple(iterations: 10) {
            let numberOfTasks = 100
            let iterationsPerTask = 10_000
            let group = DispatchGroup()
            var totalSum = 0
            for _ in 0..<numberOfTasks {
                group.enter()
                DispatchQueue.global().async {
                    var sum = 0
                    for i in 0..<iterationsPerTask {
                        sum += i
                    }
                    totalSum += sum
                    group.leave()
                }
            }
            group.wait()
        }
        let concurrencyReport = formatBenchmarkTable(metric: "Concurrency (ms)", stats: concurrencyBenchmark.stats)
        
        // Partial I/O Benchmark: Simulate sending a text response in multiple small chunks.
        let partialIOBenchmark = try measureMultiple(iterations: 10) {
            let totalChunks = 50
            let baseChunk = "ChunkData"
            let bodyContent = (0..<totalChunks).map { "\(baseChunk)-\($0)" }.joined(separator: "\n")
            var result = ""
            let chunkSize = bodyContent.count / totalChunks
            var offset = 0
            while offset < bodyContent.count {
                let end = min(offset + chunkSize, bodyContent.count)
                let startIndex = bodyContent.index(bodyContent.startIndex, offsetBy: offset)
                let endIndex = bodyContent.index(bodyContent.startIndex, offsetBy: end)
                result.append(String(bodyContent[startIndex..<endIndex]))
                offset = end
            }
        }
        let partialIOReport = formatBenchmarkTable(metric: "Partial IO (ms)", stats: partialIOBenchmark.stats)
        
        // Lock Contention Benchmark: Repeatedly update a shared counter using a lock.
        let lockContentionBenchmark = try measureMultiple(iterations: 10) {
            let tasks = 100
            let iterations = 10_000
            let group = DispatchGroup()
            let lock = NIOLock()
            var sharedCounter = 0
            for _ in 0..<tasks {
                group.enter()
                DispatchQueue.global().async {
                    for _ in 0..<iterations {
                        lock.withLock { sharedCounter += 1 }
                    }
                    group.leave()
                }
            }
            group.wait()
        }
        let lockContentionReport = formatBenchmarkTable(metric: "Lock Contention (ms)", stats: lockContentionBenchmark.stats)
        
        // Consolidate the report.
        let report = """
        Consolidated Benchmark Report:
        
        \(largeFileReport)
        
        \(concurrencyReport)
        
        \(partialIOReport)
        
        \(lockContentionReport)
        """
        print(report)
    }
}

enum RuntimeError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let str): return str
        }
    }
}

// MARK: - BenchmarkRequestHandler
// This class handles HTTP requests. In this version, it provides the usual endpoints.
// (In consolidated benchmark mode, the runConsolidatedBenchmarks() method is used instead.)
final class BenchmarkRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    // For the HTTP server endpoints, no individual measurement is done here.
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var buffer):
            bodyBuffer?.writeBuffer(&buffer)
        case .end:
            guard let head = requestHead else { return }
            // Dispatch based on URI.
            if head.uri.hasPrefix("/large-file") {
                handleLargeFile(context: context, head: head)
            } else if head.uri.hasPrefix("/concurrency") {
                handleConcurrency(context: context, head: head)
            } else if head.uri.hasPrefix("/partial-io") {
                handlePartialIO(context: context, head: head)
            } else if head.uri.hasPrefix("/lock-contention") {
                handleLockContention(context: context, head: head)
            } else {
                sendResponse(context: context, status: .notFound, body: "Not Found")
            }
            requestHead = nil
            bodyBuffer = nil
        }
    }
    
    private func handleLargeFile(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let sizeMB: Int = {
            if let range = head.uri.range(of: "size=") {
                let param = head.uri[range.upperBound...]
                return Int(param) ?? 100
            }
            return 100
        }()
        let totalBytes = sizeMB * 1024 * 1024
        var buffer = context.channel.allocator.buffer(capacity: totalBytes)
        buffer.writeBytes([UInt8](repeating: 0x41, count: totalBytes))
        // For the HTTP endpoint, we simply stream the buffer.
        streamBuffer(buffer, context: context, head: head)
        sendResponse(context: context, status: .ok, body: "Large file transfer initiated.")
    }
    
    private func streamBuffer(_ buffer: ByteBuffer, context: ChannelHandlerContext, head: HTTPRequestHead) {
        var localBuffer = buffer
        let chunkSize = 64 * 1024
        var bytesRemaining = localBuffer.readableBytes
        
        var responseHead = HTTPResponseHead(version: head.version, status: .ok)
        responseHead.headers.add(name: "Content-Length", value: "\(localBuffer.readableBytes)")
        responseHead.headers.add(name: "Content-Type", value: "application/octet-stream")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        
        func sendNextChunk() {
            let currentChunkSize = min(chunkSize, bytesRemaining)
            if currentChunkSize > 0, let chunk = localBuffer.readSlice(length: currentChunkSize) {
                context.write(wrapOutboundOut(.body(.byteBuffer(chunk))), promise: nil)
                bytesRemaining -= currentChunkSize
                context.eventLoop.scheduleTask(in: .milliseconds(1)) {
                    sendNextChunk()
                }
            } else {
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
        sendNextChunk()
    }
    
    private func handleConcurrency(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let numberOfTasks = 100
        let iterationsPerTask = 10_000
        let group = DispatchGroup()
        var totalSum = 0
        for _ in 0..<numberOfTasks {
            group.enter()
            DispatchQueue.global().async {
                var sum = 0
                for i in 0..<iterationsPerTask {
                    sum += i
                }
                totalSum += sum
                group.leave()
            }
        }
        group.wait()
        sendResponse(context: context, status: .ok, body: "Concurrent sum result: \(totalSum)")
    }
    
    private func handlePartialIO(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let totalChunks = 50
        let baseChunk = "ChunkData"
        let bodyContent = (0..<totalChunks).map { "\(baseChunk)-\($0)" }.joined(separator: "\n")
        var responseHead = HTTPResponseHead(version: head.version, status: .ok)
        responseHead.headers.add(name: "Content-Length", value: "\(bodyContent.utf8.count)")
        responseHead.headers.add(name: "Content-Type", value: "text/plain")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        var offset = 0
        let chunkSize = bodyContent.utf8.count / totalChunks
        func sendNextChunk() {
            if offset < bodyContent.utf8.count {
                let end = min(offset + chunkSize, bodyContent.utf8.count)
                let startIndex = bodyContent.index(bodyContent.startIndex, offsetBy: offset)
                let endIndex = bodyContent.index(bodyContent.startIndex, offsetBy: end)
                let chunkString = String(bodyContent[startIndex..<endIndex])
                var chunkBuffer = context.channel.allocator.buffer(capacity: chunkString.utf8.count)
                chunkBuffer.writeString(chunkString)
                offset = end
                context.write(wrapOutboundOut(.body(.byteBuffer(chunkBuffer))), promise: nil)
                context.eventLoop.scheduleTask(in: .milliseconds(50)) {
                    sendNextChunk()
                }
            } else {
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
        sendNextChunk()
        sendResponse(context: context, status: .ok, body: "Partial I/O initiated.")
    }
    
    private func handleLockContention(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let tasks = 100
        let iterations = 10_000
        let group = DispatchGroup()
        let lock = NIOLock()
        var sharedCounter = 0
        for _ in 0..<tasks {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    lock.withLock { sharedCounter += 1 }
                }
                group.leave()
            }
        }
        group.wait()
        sendResponse(context: context, status: .ok, body: "Lock contention test completed. Counter: \(sharedCounter)")
    }
    
    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1), status: status)
        responseHead.headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        responseHead.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        var bodyBuffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        bodyBuffer.writeString(body)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(bodyBuffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}

// MARK: - Application Entry

HTTPBenchmarkApp.main()
