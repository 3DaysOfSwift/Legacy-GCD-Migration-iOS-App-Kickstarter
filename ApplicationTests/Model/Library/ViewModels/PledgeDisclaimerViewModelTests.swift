@testable import Kickstarter_iOS


import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

final class PledgeDisclaimerViewModelTests: TestCase {
  private let vm: PledgeDisclaimerViewModelType = PledgeDisclaimerViewModel()

  private let notifyDelegateLinkTappedWithURL = TestObserver<URL, Never>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm.outputs.notifyDelegateLinkTappedWithURL
      .observe(self.notifyDelegateLinkTappedWithURL.observer)
  }

  func testPresentTrustAndSafety() {
    self.notifyDelegateLinkTappedWithURL.assertDidNotEmitValue()

    let url = URL(string: "http://www.kickstarter.com")!
    self.vm.inputs.linkTapped(url: url)

    self.notifyDelegateLinkTappedWithURL.assertValues([url])
  }
}
