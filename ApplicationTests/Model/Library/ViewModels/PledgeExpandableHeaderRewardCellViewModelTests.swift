@testable import Kickstarter_iOS


import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

final class PledgeExpandableHeaderRewardCellViewModelTests: TestCase {
  // Value-output assertions do not compare reference images.
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm: PledgeExpandableHeaderRewardCellViewModelType = PledgeExpandableHeaderRewardCellViewModel()

  private let amountAttributedText = TestObserver<NSAttributedString, Never>()
  private let labelText = TestObserver<String, Never>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.amountAttributedText.observe(self.amountAttributedText.observer)
    self.vm.outputs.labelText.observe(self.labelText.observer)
  }

  func testOutputs() {
    self.amountAttributedText.assertDidNotEmitValue()
    self.labelText.assertDidNotEmitValue()

    let text = "Text"
    let amount = NSAttributedString(string: "Test string")

    self.vm.inputs.configure(with: .init(
      type: nil,
      headerText: nil,
      showHeader: false,
      text: text,
      amount: amount
    ))

    self.amountAttributedText.assertValues([amount])
    self.labelText.assertValues([text])
  }
}
