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
@testable import BackpressureChannelToFileIO

final class StateMachineTest: XCTestCase {
    var coordinator: FileIOCoordinatorState!

    func testErrorArrivesWhilstWriting() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/test")
            .assertOpenFile({ path in
                XCTAssertEqual("/test", path)
            })
            .assertDoNotCallRead() // We're waiting for the file to open, so we better don't buffer more.
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertCallRead() // Now, we want the body bytes
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead() // We're now processing them, so let's wait again

        // Now, we're currently `.writing`, so let's inject the error.
        self.coordinator.didError(DummyError())
            .assertNothing() // We should be told to do nothing and sit tight.
            .assertDoNotCallRead()

        // But now, we're done writing which should surface the error:
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssert(error is DummyError)
            })
    }

    func testErrorArrivesWhilstOpeningFile() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/test")
            .assertOpenFile({ path in
                XCTAssertEqual("/test", path)
            })
            .assertDoNotCallRead() // We're waiting for the file to open, so we better don't buffer more.

        self.coordinator.didError(DummyError())
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNil(fileHandle) // haven't got one yet
                XCTAssert(error is DummyError)
            })
            .assertDoNotCallRead()

        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertCloseFile({ fileHandle in
                XCTAssertNotNil(fileHandle)
            })
            .assertDoNotCallRead()
    }

    func testQuickRunthroughWithoutErrors() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/")
            .assertOpenFile({ XCTAssertEqual("/", $0) })
            .assertDoNotCallRead()
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertNothing()
            .assertCallRead()
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertNothing()
            .assertCallRead()
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestEnd()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssertNil(error)
            })
            .assertDoNotCallRead() // We didn't hold a read, no need to replay one.
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
    }

    func testWeBufferCorrectlyEvenIfWeHoldReads() {
        // Let's kickstart this and go right into the body streaming bit
        self.moveToBodyStreamingState()

        // Let's get 3 chunks queued up (despite we shouldn't get any)
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteY)
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertNothing()
            .assertDoNotCallRead()

        // Okay, and finally, let's drain one
        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()

        // Let's enqueue another one, again we shouldn't have to
        self.coordinator.didReceiveRequestBodyBytes(self.byteY)
            .assertNothing()
            .assertDoNotCallRead()

        // Let's drain them all
        XCTAssertEqual(self.byteY, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertEqual(self.byteY, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertNothing()
            .assertCallRead() // Cool, ready for reads again.

        self.moveFromBodyStreamingToEnd(expectError: false)
    }

    func testBufferingWhilstFileIsOpening() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/")
            .assertOpenFile({ XCTAssertEqual("/", $0) })
            .assertDoNotCallRead()

        // Let's get 2 chunks queued up (despite we shouldn't get any)
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didReceiveRequestBodyBytes(self.byteY)
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertStartWriting()
            .assertDoNotCallRead()

        // Let's drain them all
        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertEqual(self.byteY, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertNothing()
            .assertCallRead()

        self.moveFromBodyStreamingToEnd(expectError: false)
    }

    func testErrorWhilstWaitingForBytes() {
        self.moveToBodyStreamingState()

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didError(DummyError())
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssert(error is DummyError)
            })
            .assertDoNotCallRead()

        self.moveFromBodyStreamingToEnd(expectError: true)
    }

    func testErrorWhilstWriting() {
        self.moveToBodyStreamingState()

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()
        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssert(error is DummyError)
            })

        self.moveFromBodyStreamingToEnd(expectError: true)
    }

    func testMultipleErrorsWhilstWriting() {
        struct SecondError: Error {}
        self.moveToBodyStreamingState()

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()

        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didError(SecondError())
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didFinishWritingOneChunkToFile()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssert(error is DummyError)
            })

        self.moveFromBodyStreamingToEnd(expectError: true)
    }

    func testErrorWhilstIdleButStillReceivingStuff() {
        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didReceiveRequestBegin(targetPath: "/foo")
            .assertDoNotCallRead()
            .assertNothing()

        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertDoNotCallRead()
            .assertNothing()

        self.coordinator.didReceiveRequestEnd()
            .assertDoNotCallRead()
            .assertNothing()
    }

    func testReceiveWholeRequestBeforeFileOpens() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/")
            .assertDoNotCallRead()
            .assertOpenFile({ XCTAssertEqual("/", $0) })

        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didReceiveRequestEnd()
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertCallRead()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssertNil(error)
            })
    }

    func testReceiveWholeRequestBeforeFileOpensEmptyFile() {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/")
            .assertDoNotCallRead()
            .assertOpenFile({ XCTAssertEqual("/", $0) })

        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestEnd()
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertCallRead()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssertNil(error)
            })
    }

    func testRequestEndWhilstWriting() {
        self.moveToBodyStreamingState()

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()

        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestEnd()
            .assertNothing()
            .assertDoNotCallRead()

        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssertNil(error)
            })

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
    }

    func testRequestEndWhilstWritingBufferedStuff() {
        self.moveToBodyStreamingState()

        // Let's buffer 3 chunks
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertStartWriting()
            .assertDoNotCallRead()
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBodyBytes(self.byteY)
            .assertNothing()
            .assertDoNotCallRead()
        self.coordinator.didReceiveRequestBodyBytes(self.byteX)
            .assertNothing()
            .assertDoNotCallRead()

        // And an end
        self.coordinator.didReceiveRequestEnd()
            .assertNothing()
            .assertDoNotCallRead()

        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()

        XCTAssertEqual(self.byteY, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertStartWriting()
            .assertDoNotCallRead()

        XCTAssertEqual(self.byteX, self.coordinator.pullNextChunkToWrite().1)
        self.coordinator.didFinishWritingOneChunkToFile()
            .assertDiscardResources({ fileHandle, error in
                XCTAssertNotNil(fileHandle)
                XCTAssertNil(error)
            })
            .assertCallRead()

        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
    }

    func testMiddleIsNotAFinalState() {
        self.moveToBodyStreamingState()

        XCTAssertFalse(self.coordinator.inFinalState)

        self.moveFromBodyStreamingToEnd(expectError: false)
    }

    func testErrorWhilstInError() {
        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()

        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()
    }

    func testRequestBeginInError() {
        self.coordinator.didError(DummyError())
            .assertNothing()
            .assertDoNotCallRead()

        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didReceiveRequestBegin(targetPath: "/f")
            .assertNothing()
            .assertDoNotCallRead()
    }
}

extension StateMachineTest {
    override func setUp() {
        XCTAssertNil(self.coordinator)
        self.coordinator = FileIOCoordinatorState()
    }

    override func tearDown() {
        XCTAssertNotNil(self.coordinator)
        XCTAssert(self.coordinator.inFinalState)
        self.coordinator = nil
    }

    func moveToBodyStreamingState(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork(), file: file, line: line)
        self.coordinator.didReceiveRequestBegin(targetPath: "/")
            .assertOpenFile({ XCTAssertEqual("/", $0) }, file: file, line: line)
            .assertDoNotCallRead(file: file, line: line)
        XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork())
        self.coordinator.didOpenTargetFile(self.fakeFileHandle)
            .assertNothing(file: file, line: line)
            .assertCallRead(file: file, line: line)
        XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork())
    }

    func moveFromBodyStreamingToEnd(expectError: Bool, file: StaticString = #file, line: UInt = #line) {
        if expectError {
            XCTAssertFalse(self.coordinator.shouldWeReadMoreDataFromNetwork(), file: file, line: line)
            self.coordinator.didReceiveRequestEnd()
                .assertNothing(file: file, line: line)
                .assertDoNotCallRead()
        } else {
            XCTAssertTrue(self.coordinator.shouldWeReadMoreDataFromNetwork(), file: file, line: line)
            self.coordinator.didReceiveRequestEnd()
                .assertDiscardResources({ fileHandle, error in
                    XCTAssertNotNil(fileHandle, file: file, line: line)
                    XCTAssertNil(error, file: file, line: line)
                }, file: file, line: line)
                .assertDoNotCallRead(file: file, line: line) // We haven't held a read...
        }
    }
}

extension StateMachineTest {
    var byteX: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 1)
        buffer.writeString("X")
        return buffer
    }

    var byteY: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 1)
        buffer.writeString("Y")
        return buffer
    }

    var fakeFileHandle: NIOFileHandle {
        let handle = NIOFileHandle(descriptor: .max)
        _ = try! handle.takeDescriptorOwnership() // we're not actually using this file handle
        return handle
    }

    struct DummyError: Error {}
}

extension FileIOCoordinatorState.Action {
    @discardableResult
    func assertOpenFile(_ check: (String) throws -> Void,
                        file: StaticString = #file,
                        line: UInt = #line) -> Self {
        if case .openFile(let path) = self.main {
            XCTAssertNoThrow(try check(path))
        } else {
            XCTFail("action \(self) not \(#function)", file: file, line: line)
        }
        return self
    }

    @discardableResult
    func assertDiscardResources(_ check: (NIOFileHandle?, Error?) throws -> Void,
                                file: StaticString = #file,
                                line: UInt = #line) -> Self {
        if case .processingCompletedDiscardResources(let fileHandle, let error) = self.main {
            XCTAssertNoThrow(try check(fileHandle, error))
        } else {
            XCTFail("action \(self) not \(#function)", file: file, line: line)
        }
        return self
    }

    @discardableResult
    func assertCloseFile(_ check: (NIOFileHandle) throws -> Void,
                         file: StaticString = #file,
                         line: UInt = #line) -> Self {
        if case .closeFile(let fileHandle) = self.main {
            XCTAssertNoThrow(try check(fileHandle))
        } else {
            XCTFail("action \(self) not \(#function)", file: file, line: line)
        }
        return self
    }

    @discardableResult
    func assertNothing(file: StaticString = #file,
                       line: UInt = #line) -> Self {
        if case .nothingWeAreWaiting = self.main {
            () // cool
        } else {
            XCTFail("action \(self) not \(#function)", file: file, line: line)
        }
        return self
    }

    @discardableResult
    func assertStartWriting(file: StaticString = #file,
                            line: UInt = #line) -> Self {
        if case .startWritingToTargetFile = self.main {
            () // cool
        } else {
            XCTFail("action \(self) not \(#function)", file: file, line: line)
        }
        return self
    }

    @discardableResult
    func assertCallRead(file: StaticString = #file,
                       line: UInt = #line) -> Self {
        XCTAssertTrue(self.callRead, file: file, line: line)
        return self
    }

    @discardableResult
    func assertDoNotCallRead(file: StaticString = #file,
                       line: UInt = #line) -> Self {
        XCTAssertFalse(self.callRead, "callRead unexpectedly true", file: file, line: line)
        return self
    }


}
