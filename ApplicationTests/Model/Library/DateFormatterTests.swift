@testable import Kickstarter_iOS

import XCTest

final class DateFormatterTests: XCTestCase {
  func testMonthYear() {
    XCTAssertEqual("MMMMyyyy", DateFormatter.monthYear)
  }
}
