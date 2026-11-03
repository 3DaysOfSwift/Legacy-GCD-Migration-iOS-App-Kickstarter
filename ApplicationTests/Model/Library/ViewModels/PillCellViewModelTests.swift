@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

final class PillCellViewModelTests: TestCase {
  private let text = TestObserver<String, Never>()

  private let vm: PillCellViewModelType = PillCellViewModel()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.text.observe(self.text.observer)
  }

  func testText() {
    self.text.assertDidNotEmitValue()
    self.vm.inputs.configure(with: "hi")

    self.text.assertValues(["hi"])
  }
}
