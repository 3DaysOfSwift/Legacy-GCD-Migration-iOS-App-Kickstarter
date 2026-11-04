@testable import Kickstarter_iOS
@testable import KsApi

import Prelude
import XCTest

@MainActor
final class SettingsFollowCellViewModelTests: XCTestCase {
  func testFollowingSwitchAndUpdates() {
    let viewModel = SettingsFollowCellViewModel()
    XCTAssertNil(viewModel.followTapped(on: true))
    viewModel.configureWith(user: User.template |> \.social .~ false)
    XCTAssertEqual(viewModel.followingPrivacyOn, false)
    XCTAssertEqual(viewModel.followTapped(on: true)?.social, true)
    XCTAssertNil(viewModel.followTapped(on: false))
    viewModel.configureWith(user: User.template |> \.social .~ true)
    XCTAssertEqual(viewModel.followingPrivacyOn, true)
  }
}
