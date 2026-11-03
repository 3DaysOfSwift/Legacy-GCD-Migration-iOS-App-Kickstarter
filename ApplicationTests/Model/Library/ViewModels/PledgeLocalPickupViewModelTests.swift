@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

final class PledgeLocalPickupViewModelTests: TestCase {
  private let vm: PledgeLocalPickupViewModelType = PledgeLocalPickupViewModel()

  private let locationLabelText = TestObserver<String, Never>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.locationLabelText.observe(self.locationLabelText.observer)
  }

  func testLocationLabelText() {
    self.locationLabelText.assertDidNotEmitValue()

    let data = PledgeLocalPickupViewData(locationName: "new york city")

    self.vm.inputs.configure(with: data)

    self.locationLabelText.assertValues(["new york city"])
  }
}
