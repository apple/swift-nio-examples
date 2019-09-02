//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Combine

typealias HeuristicsPublisher = Publishers.CompactMap<Publishers.Concatenate<Publishers.Map<PassthroughSubject<Message, Never>, WrappedMessage>, Publishers.Sequence<[WrappedMessage], PassthroughSubject<Message, Never>.Failure>>, Transmission>

public enum WrappedMessage {
    case payload(Message)
    case done
}

extension Publisher where Output == Message {
    public func transmissionHeuristics() -> Publishers.CompactMap<Publishers.Concatenate<Publishers.Map<Self, WrappedMessage>, Publishers.Sequence<[WrappedMessage], Self.Failure>>, Transmission> {
        var bufferedMessage: Message? = nil
        return self.map {
            WrappedMessage.payload($0)
        }
        .append(WrappedMessage.done)
        .compactMap { wrappedMessage -> Transmission? in
            let existingLastMessage = bufferedMessage
            bufferedMessage = nil
            switch wrappedMessage {
            case (.payload(let currentMessage)):
                guard let previousMessage = existingLastMessage else {
                    bufferedMessage = currentMessage
                    return nil
                }
                
                switch (previousMessage.port, currentMessage.port) {
                case (.out, .in)
                    where currentMessage.event.eventType == previousMessage.event.eventType:
                    return Transmission(type: .matched(origin: previousMessage.handlerID, destination: currentMessage.handlerID), event: currentMessage.event)
                case (.out, _):
                    bufferedMessage = currentMessage
                    return Transmission(type: .unmatched(.origin(previousMessage.handlerID)), event: previousMessage.event)
                case (.in, _):
                    bufferedMessage = currentMessage
                    return Transmission(type: .unmatched(.destination(previousMessage.handlerID)), event: previousMessage.event)
                }
            case .done:
                guard let previousMessage = existingLastMessage else {
                    return nil
                }
                
                switch previousMessage.port {
                case .in:
                    return Transmission(type: .unmatched(.destination(previousMessage.handlerID)), event: previousMessage.event)
                case .out:
                    return Transmission(type: .unmatched(.origin(previousMessage.handlerID)), event: previousMessage.event)
                }
            }
            
        }
    }
}

extension Publisher where Self.Failure == Never {
    func accumulate() -> Publishers.FlatMap<Publishers.Sequence<[[Output]], Never>, Self> {
        var existingItems: [Self.Output] = []
        return self.flatMap { newItem in
            existingItems.append(newItem)
            return Publishers.Sequence(sequence: [existingItems])
        }
    }
}

extension Publisher {
    public func syncCollect() throws -> [Output] {
        let syncQ = DispatchQueue(label: "syncQ")
        var result: Result<[Output], Error> = .success([])
        let group = DispatchGroup()
        group.enter()
        
        let c = self.collect().sink(receiveCompletion: { completion in
            if case .failure(let error) = completion {
                syncQ.sync {
                    result = .failure(error)
                }
            }
            group.leave()
        }, receiveValue: { (value: [Output]) in
            syncQ.sync {
                switch result {
                case .failure(let error):
                    preconditionFailure("received value \(value) whilst in error state for \(error)")
                case .success(let output):
                    precondition(output.count == 0, "received two values: \(output) before and now \(value)")
                    result = .success(value)
                }
            }
        })
        group.wait()
        withExtendedLifetime(c) {}
        switch (syncQ.sync { result }) {
        case .failure(let error):
            throw error
        case .success(let output):
            return output
        }
    }
}
