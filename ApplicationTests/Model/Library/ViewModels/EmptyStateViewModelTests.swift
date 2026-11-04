@testable import Kickstarter_iOS
import KDS
import XCTest

final class EmptyStateViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testErrorPullToRefreshState() {
    let state = EmptyStateViewType.errorPullToRefresh
    XCTAssertFalse(state.bodyLabelHidden)
    XCTAssertEqual(state.bodyLabelText, "Something went wrong—pull to refresh.")
    XCTAssertEqual(state.bodyLabelTextColor, LegacyColors.ksr_support_700.uiColor())
    XCTAssertEqual(state.imageName, "icon-exclamation")
    XCTAssertEqual(state.leftRightMargins, Styles.grid(10))
    XCTAssertTrue(state.titleLabelHidden)
    XCTAssertEqual(state.titleLabelText, "")
  }

  func testAddOnsUnavailableState() {
    let state = EmptyStateViewType.addOnsUnavailable
    XCTAssertFalse(state.bodyLabelHidden)
    XCTAssertEqual(state.bodyLabelText, "Change your shipping location or skip add-ons to continue.")
    XCTAssertEqual(state.bodyLabelTextColor, LegacyColors.ksr_support_400.uiColor())
    XCTAssertEqual(state.imageName, "icon-globe")
    XCTAssertEqual(state.leftRightMargins, Styles.grid(3))
    XCTAssertFalse(state.titleLabelHidden)
    XCTAssertEqual(state.titleLabelText, "Add-ons unavailable")
  }
}
