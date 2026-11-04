@testable import Kickstarter_iOS
@testable import KsApi

import Prelude
import XCTest

@MainActor
final class FindFriendsCellViewModelTests: XCTestCase {
  func testFollowingAvailabilityAndMissingUser() {
    let viewModel = FindFriendsCellViewModel()
    XCTAssertNil(viewModel.isDisabled)

    viewModel.configure(with: User.template |> \.social .~ true)
    XCTAssertEqual(viewModel.isDisabled, false)

    viewModel.configure(with: nil)
    XCTAssertEqual(viewModel.isDisabled, false)

    viewModel.configure(with: User.template |> \.social .~ false)
    XCTAssertEqual(viewModel.isDisabled, true)
  }
}
