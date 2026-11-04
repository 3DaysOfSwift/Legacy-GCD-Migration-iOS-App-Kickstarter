@testable import Kickstarter_iOS
@testable import KsApi

import Prelude
import XCTest

@MainActor
final class SettingsPrivacySwitchCellViewModelTests: XCTestCase {
  func testPrivacySwitchReflectsPublicProfileIncludingMissingValue() {
    let viewModel = SettingsPrivacySwitchCellViewModel()
    viewModel.configure(with: User.template |> \.showPublicProfile .~ true)
    XCTAssertFalse(viewModel.privacySwitchIsOn)
    viewModel.configure(with: User.template |> \.showPublicProfile .~ false)
    XCTAssertTrue(viewModel.privacySwitchIsOn)
    viewModel.configure(with: User.template |> \.showPublicProfile .~ nil)
    XCTAssertTrue(viewModel.privacySwitchIsOn)
  }
}
