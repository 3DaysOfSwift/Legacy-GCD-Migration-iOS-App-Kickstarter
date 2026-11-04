@testable import Kickstarter_iOS
@testable import KsApi
import UIKit
import XCTest

@MainActor
final class RewardTrackingActivitiesCellViewModelTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testCellDisplaysProjectAndTrackingNumber() {
    let cell = RewardTrackingActivitiesCell(style: .default, reuseIdentifier: nil)
    let project = Project.template
    cell.configureWith(value: .init(trackingData: .init(trackingNumber: "ABC", trackingURL: nil), project: project))
    let labels = self.descendants(cell).compactMap { $0 as? UILabel }.compactMap(\.text)
    XCTAssertTrue(labels.contains(project.name))
    XCTAssertTrue(labels.contains(Strings.Tracking_number(number: "ABC")))
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + self.descendants($0) }
  }
}
