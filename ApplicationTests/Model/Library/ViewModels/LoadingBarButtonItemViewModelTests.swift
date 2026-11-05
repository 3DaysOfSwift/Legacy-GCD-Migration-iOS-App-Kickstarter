@testable import Kickstarter_iOS
import XCTest
import UIKit

@MainActor
final class LoadingBarButtonItemViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testUpdatesAreDeliveredInOrder() {
    let viewModel = LoadingBarButtonItemViewModel()
    var enabled: [Bool] = []
    var titles: [String] = []
    var animation: [Bool] = []
    viewModel.onEnabledChanged = { enabled.append($0) }
    viewModel.onTitleChanged = { titles.append($0) }
    viewModel.onAnimatingChanged = { animation.append($0) }
    viewModel.setIsEnabled(isEnabled: true)
    viewModel.setIsEnabled(isEnabled: false)
    viewModel.setTitle(title: "Hello")
    viewModel.setAnimating(isAnimating: true)
    viewModel.setAnimating(isAnimating: false)
    XCTAssertEqual(enabled, [true, false])
    XCTAssertEqual(titles, ["Hello"])
    XCTAssertEqual(animation, [true, false])
  }
  func testViewDisplaysButtonAndLoadingState() {
    let view = LoadingBarButtonItemView.instantiate()
    guard let button = view.subviews.compactMap({ $0 as? UIButton }).first,
          let indicator = view.subviews.compactMap({ $0 as? UIActivityIndicatorView }).first else {
      return XCTFail("Expected the button and activity indicator")
    }
    view.setTitle(title: "Save")
    view.setIsEnabled(isEnabled: true)
    XCTAssertEqual(button.title(for: .normal), "Save")
    XCTAssertTrue(button.isEnabled)
    view.startAnimating()
    XCTAssertTrue(button.isHidden)
    XCTAssertTrue(indicator.isAnimating)
    view.stopAnimating()
    XCTAssertFalse(button.isHidden)
    XCTAssertFalse(indicator.isAnimating)
  }

}
