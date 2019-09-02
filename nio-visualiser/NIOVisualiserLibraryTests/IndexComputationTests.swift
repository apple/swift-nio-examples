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

import XCTest
import NIOVisualiserLibrary

class IndexComputationTests: XCTestCase {
    
    func testNextValidIndexBasic() {
        let validIndices = [0, 2, 4]
        let currentIndex = 2
        
        XCTAssertEqual(4, nextIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testNextValidIndexNoValidIndices() {
        let validIndices: [Int] = []
        let currentIndex = 2
        
        XCTAssertNil(nextIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testNextValidIndexNotPresentIndex() {
        let validIndices = [0, 2, 4]
        let currentIndex = 3
        
        XCTAssertEqual(4, nextIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testNextValidIndexNilOnLast() {
        let validIndices = [0, 2, 4]
        let currentIndex = 4
        
        XCTAssertEqual(nil, nextIndexIfValid(validIndices: validIndices, index: currentIndex))
    }

    
    func testPreviousValidIndexBasic() {
        let validIndices = [0, 2, 4]
        let currentIndex = 2
        
        XCTAssertEqual(0, previousIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testPreviousValidIndexNoValidIndices() {
        let validIndices: [Int] = []
        let currentIndex = 2
        
        XCTAssertNil(previousIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testPreviousValidIndexNotPresentIndex() {
        let validIndices = [0, 2, 4]
        let currentIndex = 3
        
        XCTAssertEqual(2, previousIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testPrevioustValidNilOnFirst() {
        let validIndices = [0, 2, 4]
        let currentIndex = 0
        
        XCTAssertEqual(nil, previousIndexIfValid(validIndices: validIndices, index: currentIndex))
    }
    
    func testAdjacentIndexNilOnBogusIndex() {
        let validIndices = [0, 2, 4]
        XCTAssertNil(nextIndexIfValid(validIndices: validIndices, index: -1))
        XCTAssertNil(nextIndexIfValid(validIndices: validIndices, index: 5))
        XCTAssertNil(previousIndexIfValid(validIndices: validIndices, index: -1))
        XCTAssertNil(nextIndexIfValid(validIndices: validIndices, index: nil))
        XCTAssertNil(previousIndexIfValid(validIndices: validIndices, index: nil))
    }

}
