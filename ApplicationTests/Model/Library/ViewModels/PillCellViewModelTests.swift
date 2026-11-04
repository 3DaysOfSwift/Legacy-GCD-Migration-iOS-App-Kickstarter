@testable import Kickstarter_iOS
import XCTest

@MainActor
final class PillCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConfiguringReusedCellUpdatesText() {
    let cell = PillCell(frame: .zero)
    cell.configureWith(value: "First")
    XCTAssertEqual(cell.label.text, "First")
    cell.configureWith(value: "Second")
    XCTAssertEqual(cell.label.text, "Second")
  }
}
