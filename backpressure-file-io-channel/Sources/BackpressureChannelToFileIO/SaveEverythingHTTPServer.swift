//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1
import Logging

public final class SaveEverythingHTTPServer {
    private var state = FileIOCoordinatorState() {
        didSet {
            self.logger.trace("new state \(self.state)")
        }
    }

    private let fileIO: NonBlockingFileIO
    private let uploadDirectory: String
    private let logger: Logger

    public init(fileIO: NonBlockingFileIO, uploadDirectory: String, logger: Logger? = nil) {
        self.fileIO = fileIO
        if let logger = logger {
            self.logger = logger
        } else {
            self.logger = Logger(label: "\(#file)")
        }
        self.uploadDirectory = uploadDirectory
    }
    
    deinit {
        assert(self.state.inFinalState, "illegal state on handler removal: \(self.state)")
    }

}

// MARK: - The handler for the Actions the state machine recommends to do
extension SaveEverythingHTTPServer {
    func runAction(_ action: FileIOCoordinatorState.Action, context: ChannelHandlerContext) {
        self.logger.trace("doing action \(action)")
        switch action.main {
        case .closeFile(let fileHandle):
            try! fileHandle.close()
        case .processingCompletedDiscardResources(let fileHandle, let maybeError):
            try! fileHandle?.close()
            self.logger.debug("fully handled request: \(maybeError.debugDescription)")
            self.requestFullyProcessed(context: context, result: maybeError.map { .failure($0) } ?? .success(()))
        case .openFile(let path):
            self.fileIO.openFile(path: path,
                                 mode: .write,
                                 flags: .allowFileCreation(posixMode: 0o600),
                                 eventLoop: context.eventLoop).flatMap { fileHandle in
                        self.fileIO.changeFileSize(fileHandle: fileHandle,
                                                   size: 0,
                                                   eventLoop: context.eventLoop).map { fileHandle }
            }.whenComplete { result in
                switch result {
                case .success(let fileHandle):
                    self.runAction(self.state.didOpenTargetFile(fileHandle),
                                   context: context)
                case .failure(let error):
                    self.runAction(self.state.didError(error),
                                   context: context)
                }
            }
        case .nothingWeAreWaiting:
            ()
        case .startWritingToTargetFile:
            let (fileHandle, bytes) = self.state.pullNextChunkToWrite()
            self.fileIO.write(fileHandle: fileHandle, buffer: bytes, eventLoop: context.eventLoop).whenComplete { result in
                switch result {
                case .success(()):
                    self.runAction(self.state.didFinishWritingOneChunkToFile(), context: context)
                case .failure(let error):
                    self.runAction(self.state.didError(error), context: context)
                }
            }
        }
        if action.callRead {
            context.read()
        }
    }
}

// MARK: - Finishing the request
extension SaveEverythingHTTPServer {
    func requestFullyProcessed(context: ChannelHandlerContext, result: Result<Void, Error>) {
        switch result {
        case .success:
            context.write(self.wrapOutboundOut(HTTPServerResponsePart.head(.init(version: .init(major: 1,
                                                                                                minor: 1),
                                                                                 status: .ok,
                                                                                 headers: ["content-length": "0"]))),
                          promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)), promise: nil)
        case .failure(let error):
            let errorPage = "ERROR on \(context.channel): \(error)"
            context.write(self.wrapOutboundOut(HTTPServerResponsePart.head(.init(version: .init(major: 1,
                                                                                                minor: 1),
                                                                                 status: .internalServerError,
                                                                                 headers: ["connection": "close",
                                                                                           "content-length": "\(errorPage.utf8.count)"]))),
                          promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: errorPage.utf8.count)
            buffer.writeString(errorPage)
            context.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil))).whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}

// MARK: - ChannelHandler conformance
extension SaveEverythingHTTPServer: ChannelDuplexHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundIn = Never
    public typealias OutboundOut = HTTPServerResponsePart

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logger.info("error on channel: \(error)")
        self.runAction(self.state.didError(error), context: context)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)

        switch reqPart {
        case .head(let request):
            self.runAction(self.state.didReceiveRequestBegin(targetPath: self.filenameForURI(request.uri)), context: context)
        case .body(let bytes):
            self.runAction(self.state.didReceiveRequestBodyBytes(bytes), context: context)
        case .end:
            self.runAction(self.state.didReceiveRequestEnd(), context: context)
        }
    }

    public func read(context: ChannelHandlerContext) {
        if self.state.shouldWeReadMoreDataFromNetwork() {
            context.read()
        }
    }
}

// MARK: - Helpers
extension SaveEverythingHTTPServer {
    func filenameForURI(_ uri: String) -> String {
        var result = "\(self.uploadDirectory)/uploaded_file_"
        result.append(contentsOf: uri.map { char in
            switch char {
            case "A" ... "Z", "a" ... "z", "0" ... "9":
                return char
            default:
                return "_"
            }
        })
        return result
    }
}
