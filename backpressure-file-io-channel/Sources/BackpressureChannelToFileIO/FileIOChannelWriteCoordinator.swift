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

import NIO

internal struct FileIOCoordinatorState {
    /// The actions for the driver of the state machine to perform.
    internal struct Action {
        enum MainAction {
            /// Do nothing, we are waiting for some event.
            case nothingWeAreWaiting

            /// Start writing chunks to the target file.
            case startWritingToTargetFile

            /// Open the file.
            case openFile(String)

            /// We are done, please close the file handle. If an error occured, it is sent here too.
            case processingCompletedDiscardResources(NIOFileHandle?, Error?)

            /// Just close the file, we have previously completed processing.
            case closeFile(NIOFileHandle)
        }

        /// The main action to perform.
        var main: MainAction

        /// Apart from the main action, do we also need to call `context.read()`?
        var callRead: Bool
    }

    private enum State {
        struct BufferState {
            var bufferedWrites: CircularBuffer<ByteBuffer>
            var heldUpRead: Bool
            var seenRequestEnd: Bool

            mutating func append(_ buffer: ByteBuffer) {
                self.bufferedWrites.append(buffer)
            }

            var isEmpty: Bool {
                return self.bufferedWrites.isEmpty
            }

            mutating func removeFirst() -> ByteBuffer {
                return self.bufferedWrites.removeFirst()
            }
        }

        /// We're totally idle, waiting for the next request.
        case idle

        /// We commanded a file to be opened, now waiting for that to happen.
        case openingFile(BufferState)

        /// We commanded a write to disk to happen, now waiting for that to complete.
        case writing(NIOFileHandle, BufferState)

        /// We're waiting for someone to pull the next bit of data (to then be written to disk).
        case readyToWrite(NIOFileHandle, BufferState)

        /// We encountered an error during a disk write. We must sit on this for a bit until the disk write completes,
        /// then we can discard the resources and close the file handle (which must not happen during writes).
        case errorWhilstWriting(NIOFileHandle, Error)

        /// We're in an error state, hold no resources, and will never recover. We'll stay here until we are no more.
        case error(Error)
    }

    private var state = State.idle

    private func illegalTransition(_ function: String = #function) -> Never {
        preconditionFailure("illegal transition \(function) in \(self)")
    }
}

// MARK: - State machine inputs
extension FileIOCoordinatorState {
    /// Tell the state machine that a new request started.
    internal mutating func didReceiveRequestBegin(targetPath: String) -> Action {
        switch self.state {
        case .idle:
            self.state = .openingFile(.init(bufferedWrites: [], heldUpRead: false, seenRequestEnd: false))
            return Action(main: .openFile(targetPath), callRead: false)
        case .error:
            return Action(main: .nothingWeAreWaiting /* for the channel to go away */, callRead: false)
        default:
            self.illegalTransition()
        }
    }

    /// Tell the state machine that we received more bytes of the request body.
    internal mutating func didReceiveRequestBodyBytes(_ bytes: ByteBuffer) -> Action {
        switch self.state {
        case .idle:
            self.illegalTransition()
        case .openingFile(var buffers):
            buffers.append(bytes)
            self.state = .openingFile(buffers)
        case .readyToWrite(let fileHandle, var buffers):
            buffers.append(bytes)
            // We go straight to `.writing` because we expect the driver to pull the next chunk using `pullNextChunk`.
            self.state = .writing(fileHandle, buffers)
            return Action(main: .startWritingToTargetFile, callRead: false)
        case .writing(let fileHandle, var buffers):
            buffers.append(bytes)
            self.state = .writing(fileHandle, buffers)
        case .error, .errorWhilstWriting:
            ()
        }
        return Action(main: .nothingWeAreWaiting /* for the file to open or the previous writes to complete */,
                      callRead: false)
    }

    /// Tell the state machine that we've just finished writing one chunk.
    internal mutating func didFinishWritingOneChunkToFile() -> Action {
        switch self.state {
        case .idle, .openingFile, .readyToWrite:
            self.illegalTransition()
        case .writing(let fileHandle, var buffers):
            if buffers.isEmpty {
                let heldUpRead = buffers.heldUpRead
                buffers.heldUpRead = false
                if buffers.seenRequestEnd {
                    self.state = .idle
                    return Action(main: .processingCompletedDiscardResources(fileHandle, nil), callRead: heldUpRead)
                } else {
                    self.state = .readyToWrite(fileHandle, buffers)
                    return Action(main: .nothingWeAreWaiting /* for more data or EOF */, callRead: heldUpRead)
                }
            } else {
                self.state = .writing(fileHandle, buffers)
                return Action(main: .startWritingToTargetFile, callRead: false)
            }
        case .errorWhilstWriting(let fileHandle, let error):
            // Okay, the write finally completed, let's discard the resources.
            self.state = .error(error)
            return Action(main: .processingCompletedDiscardResources(fileHandle, error), callRead: false)
        case .error:
            self.illegalTransition() // if an error happened whilst writing then we should be in the above case.
        }
    }

    /// Tell the state machine we received the HTTP request end.
    internal mutating func didReceiveRequestEnd() -> Action {
        switch self.state {
        case .idle:
            self.illegalTransition()
        case .openingFile(var buffers):
            precondition(!buffers.seenRequestEnd, "double .end received")
            buffers.seenRequestEnd = true
            self.state = .openingFile(buffers)
        case .readyToWrite(let fileHandle, var buffers):
            precondition(!buffers.seenRequestEnd, "double .end received")
            buffers.seenRequestEnd = true
            if buffers.isEmpty {
                self.state = .idle
                let heldUpRead = buffers.heldUpRead
                buffers.heldUpRead = false // because we're delivering it now.
                return Action(main: .processingCompletedDiscardResources(fileHandle, nil), callRead: heldUpRead)
            } else {
                self.illegalTransition()
            }
        case .writing(let fileHandle, var buffers):
            precondition(!buffers.seenRequestEnd, "double .end received")
            buffers.seenRequestEnd = true
            self.state = .writing(fileHandle, buffers)
        case .error, .errorWhilstWriting:
            ()
        }
        return Action(main: .nothingWeAreWaiting /* for the writes to the file to complete */, callRead: false)
    }

    /// Tell the state machine we finished opening the target file.
    internal mutating func didOpenTargetFile(_ fileHandle: NIOFileHandle) -> Action {
        switch self.state {
        case .idle, .readyToWrite, .writing, .errorWhilstWriting:
            self.illegalTransition()
        case .openingFile(var buffers):
            if buffers.isEmpty {
                let heldUpRead = buffers.heldUpRead
                buffers.heldUpRead = false // because we're replaying it now.

                if buffers.seenRequestEnd {
                    // That's a zero length file
                    self.state = .idle
                    return Action(main: .processingCompletedDiscardResources(fileHandle, nil), callRead: heldUpRead)
                } else {
                    self.state = .readyToWrite(fileHandle, buffers)
                    return Action(main: .nothingWeAreWaiting /* for more data or EOF */, callRead: heldUpRead)
                }
            } else {
                self.state = .writing(fileHandle, buffers)
                return Action(main: .startWritingToTargetFile, callRead: false)
            }
        case .error:
            return Action(main: .closeFile(fileHandle), callRead: false)
        }
    }

    /// Tell the state machine that we've hit an error.
    internal mutating func didError(_ error: Error) -> Action {
        switch self.state {
        // Straight to error in these states:
        case .idle:
            self.state = .error(error)
            return Action(main: .nothingWeAreWaiting /* the channel to go away */, callRead: false)
        case .openingFile:
            self.state = .error(error)
            return Action(main: .processingCompletedDiscardResources(nil, error), callRead: false)
        case .readyToWrite(let fileHandle, _):
            self.state = .error(error)
            return Action(main: .processingCompletedDiscardResources(fileHandle, error), callRead: false)

        // We need to go via .errorWhilstWriting
        case .writing(let fileHandle, _):
            self.state = .errorWhilstWriting(fileHandle, error)
            return Action(main: .nothingWeAreWaiting /* for the write to complete */, callRead: false)

        // Error states: We stay where we are
        case .errorWhilstWriting:
            return Action(main: .nothingWeAreWaiting /* for the write to complete */, callRead: false)
        case .error:
            // We'll stay in the existing error state
            return Action(main: .nothingWeAreWaiting /* the channel to go away */, callRead: false)
        }
    }
}

// MARK: - State machine queries
extension FileIOCoordinatorState {
    /// Are we in a final state of the state machine? Mostly useful to catch bugs.
    internal var inFinalState: Bool {
        switch self.state {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    /// Should we read more data from the network to make further progress?
    internal mutating func shouldWeReadMoreDataFromNetwork() -> Bool {
        switch self.state {
        case .idle, .readyToWrite:
            // Yes, we're idle or waiting to write the next chunk so more data would be useful.
            return true
        case .openingFile(var buffers):
            // No, we're waiting for the target file to open.
            buffers.heldUpRead = true
            self.state = .openingFile(buffers)
            return false
        case .writing(let fileHandle, var buffers):
            // No, we're already writing what we received before.
            buffers.heldUpRead = true
            self.state = .writing(fileHandle, buffers)
            return false
        case .error, .errorWhilstWriting:
            // No, hit an error.
            return false
        }
    }

    internal mutating func pullNextChunkToWrite() -> (NIOFileHandle, ByteBuffer) {
        switch self.state {
        case .error, .idle, .openingFile, .readyToWrite, .errorWhilstWriting:
            self.illegalTransition()
        case .writing(let fileHandle, var buffers):
            let first = buffers.removeFirst()
            self.state = .writing(fileHandle, buffers)
            return (fileHandle, first)
        }
    }
}

extension FileIOCoordinatorState: CustomStringConvertible {
    var description: String {
        return "\(self.state)"
    }
}
