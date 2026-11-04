@testable import Kickstarter_iOS
import XCTest

final class SettingsDeleteOrRequestCellViewModelTests: XCTestCase {
  func testPolicyURLUsesLanguageAndDefaultsToEnglish() {
    let viewModel = SettingsDeleteOrRequestCellViewModel()
    XCTAssertEqual(viewModel.policyURL(languageCode: "fr")?.absoluteString,
                   "https://legal.kickstarter.com/policies/fr/?modal=take-control")
    XCTAssertEqual(viewModel.policyURL(languageCode: nil)?.absoluteString,
                   "https://legal.kickstarter.com/policies/en/?modal=take-control")
  }
}
