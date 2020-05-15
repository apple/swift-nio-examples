import XCTest

import connection_limiterTests

var tests = [XCTestCaseEntry]()
tests += connection_limiterTests.allTests()
XCTMain(tests)
