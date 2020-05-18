//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIO
import BackpressureChannelToFileIO

final class IntegrationTest: XCTestCase {
    private var channel: Channel!
    private var group: EventLoopGroup!
    private var fileIO: NonBlockingFileIO!
    private var threadPool: NIOThreadPool!
    private var testToChannel: FileHandle!
    private var channelToTest: FileHandle!
    private var tempDir: String!

    func testBasicRoundtrip() {
        let twoReqs = "POST /foo HTTP/1.1\r\ncontent-length: 5\r\n\r\nabcde" +
            /*     */ "POST /bar HTTP/1.1\r\ncontent-length: 3\r\n\r\nfoo"
        self.testToChannel.write(Data(twoReqs.utf8))
        let results = (0..<6).compactMap { _ in self.channelToTest.readLine() }
        guard results.count == 6 else {
            XCTFail("couldn't read results")
            return
        }

        XCTAssertEqual(Data("HTTP/1.1 200 OK\r\n".utf8), results[0])
        XCTAssertEqual(Data("HTTP/1.1 200 OK\r\n".utf8), results[3])

        XCTAssertNoThrow(XCTAssertEqual(Data("abcde".utf8),
                                        try Data(contentsOf: URL(fileURLWithPath: "\(self.tempDir!)/uploaded_file__foo"))))
        XCTAssertNoThrow(XCTAssertEqual(Data("foo".utf8),
                                        try Data(contentsOf: URL(fileURLWithPath: "\(self.tempDir!)/uploaded_file__bar"))))
    }
    
    func testWeSurviveTheChannelGoingAwayWhilstWriting() {
        let semaphore = DispatchSemaphore(value: 0)
        let destinationFilePath = "\(self.tempDir!)/uploaded_file__"
        
        // Let's write the request but not the body, that should open the file.
        self.testToChannel.write(Data("POST / HTTP/1.1\r\ncontent-length: 1\r\n\r\n".utf8))
        while !FileManager.default.fileExists(atPath: destinationFilePath) {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Then, let's block the ThreadPool so the writes won't be able to happen.
        let blockedItem = self.threadPool.runIfActive(eventLoop: self.group.next()) {
            semaphore.wait()
        }
        
        // And write a byte.
        self.testToChannel.write(Data("X".utf8))
        
        final class InjectReadHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            
            func handlerAdded(context: ChannelHandlerContext) {
                context.read()
            }
        }
        
        // Now, let's close the input side of the channel, which should actually close the whole channel, because
        // we have half-closure disabled (default).
        XCTAssertNoThrow(try self.testToChannel.close())
        self.testToChannel = nil // So tearDown doesn't close it again.
        
        // To make sure that EOF is seen, we'll inject a `read()` because otherwise there won't be reads because the
        // HTTP server implements backpressure correctly... The read injection handler has to go at the very beginning
        // of the pipeline so the HTTP server can't hold that `read()`.
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(InjectReadHandler(), position: .first).wait())
        XCTAssertNoThrow(try self.channel.closeFuture.wait())
        self.channel = nil // So tearDown doesn't close it again.
        
        // The write can't have happened yet (because the thread pool's blocked).
        XCTAssertNoThrow(XCTAssertEqual(Data(), try Data(contentsOf: URL(fileURLWithPath: destinationFilePath))))
            
        // Now, let's kick off the writes.
        semaphore.signal()
        XCTAssertNoThrow(try blockedItem.wait())
        
        // And wait for the write to actually happen :).
        while Data("X".utf8) != (try? Data(contentsOf: URL(fileURLWithPath: destinationFilePath))) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

extension IntegrationTest {
    override func setUp() {
        XCTAssertNil(self.channel)
        XCTAssertNil(self.group)
        XCTAssertNil(self.fileIO)
        XCTAssertNil(self.threadPool)
        XCTAssertNil(self.testToChannel)
        XCTAssertNil(self.channelToTest)
        
        guard let temp = try? FileManager.default.url(for: .itemReplacementDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: URL(string: "/")!,
                                                      create: true) else {
                                                        XCTFail("can't create temp dir")
                                                        return
                                                        
        }
        self.tempDir = temp.path
        self.threadPool = NIOThreadPool(numberOfThreads: 1)
        self.threadPool.start()
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.fileIO = NonBlockingFileIO(threadPool: threadPool)
        let testToChannel = Pipe()
        let channelToTest = Pipe()
        
        var maybeChannel: Channel? = nil
        XCTAssertNoThrow(try maybeChannel = NIOPipeBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: false).flatMap {
                    channel.pipeline.addHandler(SaveEverythingHTTPServer(fileIO: self.fileIO,
                                                                         uploadDirectory: self.tempDir))
                }
            }
            .withPipes(inputDescriptor: dup(testToChannel.fileHandleForReading.fileDescriptor),
                       outputDescriptor: dup(channelToTest.fileHandleForWriting.fileDescriptor))
            .wait())
        guard let channel = maybeChannel else {
            XCTFail("can't get a Channel")
            return
        }
        self.testToChannel = FileHandle(fileDescriptor: dup(testToChannel.fileHandleForWriting.fileDescriptor))
        self.channelToTest = FileHandle(fileDescriptor: dup(channelToTest.fileHandleForReading.fileDescriptor))
        self.channel = channel
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.channel?.close().wait())
        XCTAssertNoThrow(try self.testToChannel?.close())
        XCTAssertNoThrow(try self.channelToTest?.close())
        XCTAssertNoThrow(try self.group?.syncShutdownGracefully())
        XCTAssertNoThrow(try self.threadPool?.syncShutdownGracefully())
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: self.tempDir))
        
        self.channel = nil
        self.group = nil
        self.fileIO = nil
        self.threadPool = nil
        self.testToChannel = nil
        self.channelToTest = nil
        self.tempDir = nil
    }
}

extension FileHandle {
    func readLine() -> Data? {
        var target = Data()
        var char: UInt8 = .max
        repeat {
            if let c = self.readData(ofLength: 1).first {
                char = c
                target.append(c)
            } else {
                return nil
            }
        } while char != UInt8(ascii: "\n")
        return target
    }
}
