@testable import Kickstarter_iOS
import XCTest
import UIKit

@MainActor
final class LoadingButtonViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testLoadingUpdatesAreDeliveredInOrder() {
    let viewModel = LoadingButtonViewModel()
    var updates: [Bool] = []
    viewModel.onLoadingChanged = { updates.append($0) }
    viewModel.isLoading(true)
    viewModel.isLoading(false)
    XCTAssertEqual(updates, [true, false])
  }
  func testLoadingPreservesUpdatedTitleAndInteraction() {
    let button = LoadingButton(frame: .zero)
    button.setTitle("Start", for: .normal)
    button.isLoading = true
    XCTAssertFalse(button.isUserInteractionEnabled)
    XCTAssertNil(button.title(for: .normal))
    button.setTitle("Updated", for: .normal)
    button.isLoading = false
    XCTAssertTrue(button.isUserInteractionEnabled)
    XCTAssertEqual(button.title(for: .normal), "Updated")
  }

}
