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
        case idle
        case openingFile(BufferState)
        case writing(NIOFileHandle, BufferState)
        case readyToWrite(NIOFileHandle, BufferState)
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
    internal mutating func didStartRequest(targetPath: String) -> Action {
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
            self.state = .writing(fileHandle, buffers)
            return Action(main: .startWritingToTargetFile, callRead: false)
        case .writing(let fileHandle, var buffers):
            buffers.append(bytes)
            self.state = .writing(fileHandle, buffers)
        case .error:
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
        case .error:
            return Action(main: .nothingWeAreWaiting /* for the channel to go away */, callRead: false)
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
                return Action(main: .processingCompletedDiscardResources(fileHandle, nil), callRead: buffers.heldUpRead)
            } else {
                self.illegalTransition()
            }
        case .writing(let fileHandle, var buffers):
            precondition(!buffers.seenRequestEnd, "double .end received")
            buffers.seenRequestEnd = true
            self.state = .writing(fileHandle, buffers)
        case .error:
            ()
        }
        return Action(main: .nothingWeAreWaiting /* for the writes to the file to complete */, callRead: false)
    }

    /// Tell the state machine we finished opening the target file.
    internal mutating func didOpenTargetFile(_ fileHandle: NIOFileHandle) -> Action {
        switch self.state {
        case .idle, .readyToWrite, .writing:
            self.illegalTransition()
        case .openingFile(let buffers):
            if buffers.isEmpty {
                if buffers.seenRequestEnd {
                    // That's a zero length file
                    self.state = .idle
                    return Action(main: .processingCompletedDiscardResources(fileHandle, nil), callRead: buffers.heldUpRead)
                } else {
                    self.state = .readyToWrite(fileHandle, buffers)
                    return Action(main: .nothingWeAreWaiting /* for more data or EOF */, callRead: buffers.heldUpRead)
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
        let oldState = self.state
        self.state = .error(error)
        switch oldState {
        case .idle, .error:
            return Action(main: .nothingWeAreWaiting /* for a new request / the channel to go away */, callRead: false)
        case .openingFile:
            return Action(main: .processingCompletedDiscardResources(nil, error), callRead: false)
        case .readyToWrite(let fileHandle, _), .writing(let fileHandle, _):
            return Action(main: .processingCompletedDiscardResources(fileHandle, error), callRead: false)
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
        case .error:
            // No, hit an error.
            return false
        }
    }

    internal mutating func pullNextChunkToWrite() -> (NIOFileHandle, ByteBuffer) {
        switch self.state {
        case .error, .idle, .openingFile, .readyToWrite:
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
