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

enum FilterAction {
    case filterOut
    case leaveIn
}

public func shouldKeepEvent(_ filters: [(Bool, Event.EventType)], event: Event) -> Bool {
    func filterOut(_ bool: Bool, _ eventType: Event.EventType, _ event: Event) -> Bool {
        return !bool && eventType == event.eventType
    }
    

    return !filters.contains {
        filterOut($0.0, $0.1, event)
    }
}

private func adjacentIndexIfValid(validIndices: [Int],
                          index: Int?,
                          adjacentIndex: ([Int]) -> (Int) -> Int?,
                          findFirst: ([Int], Int) -> Int?) -> Int? {
    return { () -> Int? in
        guard let index = index, index >= 0 else {
            return nil
        }
        if let currentIndexsIndex = validIndices.firstIndex(of: index) {
            return adjacentIndex(validIndices)(currentIndexsIndex)
        } else {
            return findFirst(validIndices, index)
        }
    }().flatMap { validIndices.indices.contains($0) ? validIndices[$0] : nil }
}


public func previousIndexIfValid(validIndices: [Int], index: Int?) -> Int? {
    return adjacentIndexIfValid(validIndices: validIndices, index: index, adjacentIndex: Array<Int>.index(before:), findFirst: { validIndices, index in
        validIndices.lastIndex(where: { $0 < index })
    })
}


public func nextIndexIfValid(validIndices: [Int], index: Int?) -> Int? {
    return adjacentIndexIfValid(validIndices: validIndices, index: index, adjacentIndex: Array<Int>.index(after:), findFirst: { validIndices, index in
        validIndices.firstIndex(where: { $0 > index })
    })
}
