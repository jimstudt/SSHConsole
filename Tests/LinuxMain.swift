import XCTest

import SSHConsoleTests

var tests = [XCTestCaseEntry]()
tests += SSHConsoleTests.allTests()
XCTMain(tests)
