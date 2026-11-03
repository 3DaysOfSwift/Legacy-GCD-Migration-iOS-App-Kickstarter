@testable import Kickstarter_iOS

import XCTest

@MainActor
final class EnvironmentTests: XCTestCase {
  func testInit() {
    let env = Environment()

    XCTAssertEqual(env.calendar, Calendar.current)
    XCTAssertEqual(env.language, Language(languageStrings: Locale.preferredLanguages))
    XCTAssertEqual(env.locale, Locale.current)
    XCTAssertEqual(env.countryCode, "US")
  }
}
