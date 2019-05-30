import XCTest

import JSONRPCTests

var tests = [XCTestCaseEntry]()
tests += JSONRPCTests.__allTests()

XCTMain(tests)
