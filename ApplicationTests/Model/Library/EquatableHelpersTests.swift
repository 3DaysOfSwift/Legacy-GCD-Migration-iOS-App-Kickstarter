@testable import Kickstarter_iOS


import XCTest

final class EquatableHelpersTests: TestCase {
  func testIsAnyOf() {
    XCTAssertTrue("one".isAny(of: "one", "two", "three"))
    XCTAssertFalse("five".isAny(of: "one", "two", "three"))
  }
}
