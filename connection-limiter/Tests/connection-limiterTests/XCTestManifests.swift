import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(connection_limiterTests.allTests),
    ]
}
#endif
