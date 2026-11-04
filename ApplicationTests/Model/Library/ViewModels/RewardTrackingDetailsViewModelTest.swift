@testable import Kickstarter_iOS
import UIKit
import XCTest

@MainActor
final class RewardTrackingDetailsViewModelTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testTrackingPresentationAndAction() throws {
    let view = RewardTrackingDetailsView(style: .activity)
    let delegate = TrackingDelegate()
    view.delegate = delegate
    let url = try XCTUnwrap(URL(string: "https://example.com/tracking"))
    view.configure(with: .init(trackingNumber: "1234567890", trackingURL: url))
    let labels = descendants(view).compactMap { $0 as? UILabel }.compactMap(\.text)
    XCTAssertTrue(labels.contains(Strings.Tracking_number(number: "1234567890")))
    XCTAssertTrue(labels.contains(Strings.Your_reward_has_shipped()))
    let button = try XCTUnwrap(descendants(view).compactMap { $0 as? UIButton }.first)
    XCTAssertFalse(button.isHidden)
    button.sendActions(for: .touchUpInside)
    XCTAssertEqual(delegate.url, url)
    view.configure(with: .init(trackingNumber: "456", trackingURL: nil))
    XCTAssertTrue(button.isHidden)
  }

  private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + self.descendants($0) }
  }
}

@MainActor
private final class TrackingDelegate: RewardTrackingDetailsViewDelegate {
  var url: URL?
  func didTapTrackingButton(with trackingURL: URL) { self.url = trackingURL }
}
