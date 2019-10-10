import XCTest

import rdkqueueTests

var tests = [XCTestCaseEntry]()
tests += rdkqueueTests.allTests()
XCTMain(tests)
