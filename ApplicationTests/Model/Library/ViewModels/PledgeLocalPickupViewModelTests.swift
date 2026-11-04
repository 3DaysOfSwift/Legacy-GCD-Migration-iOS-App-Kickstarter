@testable import Kickstarter_iOS
import UIKit
import XCTest

@MainActor
final class PledgeLocalPickupViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testLocationAppearsAndUpdatesWhenReconfigured() {
    let view = PledgeLocalPickupView(frame: .zero)
    view.configure(with: PledgeLocalPickupViewData(locationName: "New York"))
    XCTAssertTrue(self.labels(in: view).contains("New York"))
    view.configure(with: PledgeLocalPickupViewData(locationName: "London"))
    XCTAssertTrue(self.labels(in: view).contains("London"))
    XCTAssertFalse(self.labels(in: view).contains("New York"))
  }

  private func labels(in view: UIView) -> [String] {
    let own = (view as? UILabel)?.text.map { [$0] } ?? []
    return own + view.subviews.flatMap { self.labels(in: $0) }
  }
}
