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

public enum ChannelHandlerPort: Equatable, CustomStringConvertible {
    public var description: String {
        switch self {
        case .in:
            return "in"
        case .out:
            return "out"
        }
    }
    
    case `in`
    case out
}
