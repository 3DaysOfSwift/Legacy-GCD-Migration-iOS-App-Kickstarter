@testable import Kickstarter_iOS
import XCTest

@MainActor
private final class PersonalizationDelegateProbe: PersonalizationCellDelegate {
  var taps = 0
  var dismissals = 0
  func personalizationCellTapped(_ cell: PersonalizationCell) { self.taps += 1 }
  func personalizationCellDidTapDismiss(_ cell: PersonalizationCell) { self.dismissals += 1 }
}

@MainActor
final class PersonalizationCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testActionsNotifyDelegateOnEveryTap() {
    let cell = PersonalizationCell(style: .default, reuseIdentifier: nil)
    let delegate = PersonalizationDelegateProbe()
    cell.delegate = delegate
    cell.perform(NSSelectorFromString("cellTapped"))
    cell.perform(NSSelectorFromString("cellTapped"))
    cell.perform(NSSelectorFromString("dismissButtonTapped"))
    XCTAssertEqual(delegate.taps, 2)
    XCTAssertEqual(delegate.dismissals, 1)
  }
}
