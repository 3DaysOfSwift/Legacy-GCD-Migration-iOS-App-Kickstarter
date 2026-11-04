@testable import Kickstarter_iOS
import XCTest

@MainActor
final class RewardAddOnSelectionContinueCTAViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testButtonStatesAndTitlesUpdateWhenReconfigured() {
    let view = RewardAddOnSelectionContinueCTAView(frame: .zero)
    view.configure(with: (0, false, false, nil))
    XCTAssertFalse(view.continueButton.isEnabled)
    XCTAssertEqual(view.continueButton.title(for: .normal), "Continue")

    view.configure(with: (2, true, true, NSAttributedString(string: "$20")))
    XCTAssertTrue(view.continueButton.isEnabled)
    XCTAssertTrue(view.continueButton.isLoading)
    view.configure(with: (2, true, false, NSAttributedString(string: "$20")))
    XCTAssertEqual(view.continueButton.title(for: .disabled), "Continue with 2 add-ons")

    view.configure(with: (1, true, false, nil))
    XCTAssertFalse(view.continueButton.isLoading)
    XCTAssertEqual(view.continueButton.title(for: .normal), "Continue with 1 add-on")
  }

  func testPledgeAmountIsPreservedInPresentationState() {
    let amount = NSAttributedString(string: "$20")
    let state = RewardAddOnSelectionContinueCTAState(data: (2, true, false, amount))
    XCTAssertEqual(state.pledgeAmount, amount)
    XCTAssertEqual(state.buttonTitle, "Continue with 2 add-ons")
  }
}
