//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// HTTPBenchmarkApp - A toy HTTP server for benchmarking various real-world
// scenarios, including file transfer, concurrency, partial I/O, and lock contention.
//
// In addition to its HTTP endpoints, when run with --run-all-benchmarks the app
// will execute consolidated benchmarks and output a report.
// Optionally, the --use-io-uring flag enables NIOTSEventLoopGroup (Linux io_uring).
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

#if canImport(NIOTransportServices)
import NIOTransportServices
#endif

/// Runs a block and returns its elapsed time in milliseconds.
func measure<T>(_ block: () throws -> T) rethrows -> (result: T, elapsedMs: Double) {
    let start = DispatchTime.now()
    let result = try block()
    let end = DispatchTime.now()
    let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    return (result, elapsed)
}

/// Computes percentiles (p0, p25, p50, p75, p90, p99, p100) from an array of elapsed times.
func calculateStatistics(
    from samples: [Double]
) -> (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double) {
    let sorted = samples.sorted()
    let count = sorted.count
    return (
        p0: sorted.first ?? 0.0,
        p25: sorted[Int(Double(count - 1) * 0.25)],
        p50: sorted[Int(Double(count - 1) * 0.50)],
        p75: sorted[Int(Double(count - 1) * 0.75)],
        p90: sorted[Int(Double(count - 1) * 0.90)],
        p99: sorted[Int(Double(count - 1) * 0.99)],
        p100: sorted.last ?? 0.0
    )
}

/// Runs a block repeatedly, collects elapsed times, returns last result and stats.
func measureMultiple<T>(
    iterations: Int,
    block: () throws -> T
) rethrows -> (
    result: T?,
    stats: (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double, samples: Int)
) {
    var samples = [Double]()
    var lastResult: T? = nil
    for _ in 0..<iterations {
        let (_, elapsed) = try measure {
            lastResult = try block()
            return lastResult!
        }
        samples.append(elapsed)
    }
    let stats = calculateStatistics(from: samples)
    return (lastResult, (stats.p0, stats.p25, stats.p50, stats.p75, stats.p90, stats.p99, stats.p100, samples.count))
}

/// Formats a table of benchmark stats.
func formatBenchmarkTable(
    metric: String,
    stats: (p0: Double, p25: Double, p50: Double, p75: Double, p90: Double, p99: Double, p100: Double, samples: Int)
) -> String {
    let padded = metric.padding(toLength: 24, withPad: " ", startingAt: 0)
    let line = String(
        format: "│ %@ │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7.2f │ %7d │",
        padded,
        stats.p0,
        stats.p25,
        stats.p50,
        stats.p75,
        stats.p90,
        stats.p99,
        stats.p100,
        stats.samples
    )
    return """
        ╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
        │ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
        ╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
        \(line)
        ╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
        """
}

struct HTTPBenchmarkApp: ParsableCommand {
    @Option(help: "Host to bind on") var host: String = "127.0.0.1"
    @Option(help: "Port to bind on") var port: Int = 8080
    @Option(help: "Number of samples for each consolidated benchmark") var samples: Int = 10
    @Flag(help: "Enable io_uring backend (requires NIOTransportServices)") var useIOUring: Bool = false
    @Flag(help: "Run all consolidated benchmarks and exit") var runAllBenchmarks: Bool = false

    func run() throws {
        if runAllBenchmarks {
            try runConsolidatedBenchmarks(iterations: samples)
            return
        }

        // EventLoopGroup selection
        let group: EventLoopGroup = {
            #if canImport(Network)
            if useIOUring {
                return NIOTSEventLoopGroup(loopCount: System.coreCount)
            }
            #endif
            return MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }()

        // Bootstrap server
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(BenchmarkRequestHandler())
                }
            }

        let server = try bootstrap.bind(host: host, port: port).wait()
        print("HTTPBenchmarkApp running on \(host):\(port)")
        try server.closeFuture.wait()
        try group.syncShutdownGracefully()
    }

    func runConsolidatedBenchmarks(iterations: Int) throws {
        print("Running consolidated benchmarks...\n")

        let (_, stats1) = measureMultiple(iterations: iterations) {
            let total = 100 * 1024 * 1024
            var buf = ByteBufferAllocator().buffer(capacity: total)
            buf.writeBytes([UInt8](repeating: 0x41, count: total))
            var local = buf
            let chunk = 64 * 1024
            while local.readableBytes > 0 {
                _ = local.readSlice(length: min(chunk, local.readableBytes))
            }
        }
        print(formatBenchmarkTable(metric: "LargeFile (ms)", stats: stats1))

        let (_, stats2) = measureMultiple(iterations: iterations) {
            let tasks = 100
            let iters = 10_000
            let dg = DispatchGroup()
            let lock = NIOLock()
            for _ in 0..<tasks {
                dg.enter()
                DispatchQueue.global().async {
                    for i in 0..<iters { lock.withLock { _ = i } }
                    dg.leave()
                }
            }
            dg.wait()
        }
        print(formatBenchmarkTable(metric: "Concurrency (ms)", stats: stats2))

        let (_, stats3) = measureMultiple(iterations: iterations) {
            let chunks = 50
            let data = (0..<chunks).map { "Chunk-\($0)" }.joined(separator: "\n")
            var offset = 0
            let size = data.utf8.count
            let step = size / chunks
            while offset < size { offset = min(offset + step, size) }
        }
        print(formatBenchmarkTable(metric: "Partial IO (ms)", stats: stats3))

        let (_, stats4) = measureMultiple(iterations: iterations) {
            let tasks = 100
            let iters = 10_000
            let dg = DispatchGroup()
            let lock = NIOLock()
            for _ in 0..<tasks {
                dg.enter()
                DispatchQueue.global().async {
                    for _ in 0..<iters { lock.withLock { _ = 0 } }
                    dg.leave()
                }
            }
            dg.wait()
        }
        print(formatBenchmarkTable(metric: "Lock Contention (ms)", stats: stats4))
    }
}

extension BenchmarkRequestHandler: @unchecked Sendable {}

final class BenchmarkRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var head: HTTPRequestHead?
    private var buffer: ByteBuffer?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let h):
            head = h
            buffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var b): buffer?.writeBuffer(&b)
        case .end:
            guard let h = head else { return }
            sendSimpleResponse(context: context, status: .ok, body: h.uri)
            head = nil
            buffer = nil
        }
    }

    private func sendSimpleResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var rh = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: status)
        rh.headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        rh.headers.add(name: "Content-Type", value: "text/plain")
        var bb = context.channel.allocator.buffer(capacity: body.utf8.count)
        bb.writeString(body)
        context.write(wrapOutboundOut(.head(rh)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(bb))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}

HTTPBenchmarkApp.main()
