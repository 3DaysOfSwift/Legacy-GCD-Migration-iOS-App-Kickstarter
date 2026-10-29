@testable import Kickstarter_Framework
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import UIKit
import XCTest

/// Geometry/lifetime checks only; reference-device snapshot suites remain unchanged.
@MainActor
final class LayoutLifecycleTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testReportCellReconfigurationReusesOneHostedView() throws {
    let cell = ReportProjectCell(style: .default, reuseIdentifier: nil)
    cell.frame = CGRect(x: 0, y: 0, width: 390, height: 90)
    cell.configureWith(value: false)
    let host = try XCTUnwrap(cell.contentView.subviews.first)
    func hostConstraints() -> Int {
      cell.contentView.constraints.filter { $0.firstItem === host || $0.secondItem === host }.count
    }
    let constraints = hostConstraints()
    for flagged in [true, false, true] {
      cell.prepareForReuse()
      cell.configureWith(value: flagged)
      cell.setNeedsLayout()
      cell.layoutIfNeeded()
      XCTAssertEqual(cell.contentView.subviews.count, 1)
      XCTAssertTrue(cell.contentView.subviews.first === host)
      XCTAssertEqual(hostConstraints(), constraints)
      XCTAssertEqual(cell.accessibilityTraits, flagged ? .staticText : .button)
      XCTAssertEqual(cell.isAccessibilityElement, !flagged)
    }
  }

  func testDiscoveryShadowsFollowCurrentBoundsWithoutQueuedWork() throws {
    let cell = try XCTUnwrap(Bundle.framework.loadNibNamed(
      "DiscoveryPostcardCell", owner: nil, options: nil
    )?.first as? DiscoveryPostcardCell)
    func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    for width: CGFloat in [390, 600, 320] {
      cell.frame = CGRect(x: 0, y: 0, width: width, height: 700)
      cell.setNeedsLayout()
      cell.layoutIfNeeded()
      let shadows = descendants(cell).filter { $0.layer.shadowPath != nil }
      XCTAssertGreaterThanOrEqual(shadows.count, 2)
      for view in shadows {
        let path = try XCTUnwrap(view.layer.shadowPath).boundingBox
        XCTAssertEqual(path.width, view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(path.height, view.bounds.height, accuracy: 0.5)
      }
    }
  }

  func testRewardExpansionUsesLaidOutRowsAndLatestSelection() {
    let controller = PledgeExpandableRewardsHeaderViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let parent = UIViewController()
    window.rootViewController = parent
    parent.addChild(controller)
    parent.view.addSubview(controller.view)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor)
    ])
    controller.didMove(toParent: parent)
    controller.animatingViewDelegate = parent.view
    window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    controller.configure(with: PledgeExpandableRewardsHeaderViewData(
      rewards: [.template], selectedQuantities: [:], currencyCode: "USD", omitCurrencyCode: false
    ))
    parent.view.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    parent.view.layoutIfNeeded()
    XCTAssertGreaterThan(controller.collapsedHeight(), 0)
    XCTAssertGreaterThanOrEqual(controller.expandedHeight(), controller.collapsedHeight())
    controller.expandButtonTapped()
    controller.expandButtonTapped()
    parent.view.layoutIfNeeded()
    controller.view.layoutIfNeeded()
    parent.view.layoutIfNeeded()
    let table = self.table(in: controller.view)
    XCTAssertEqual(table?.superview?.frame.height ?? -1, controller.collapsedHeight(), accuracy: 1)
  }

  private func table(in view: UIView) -> UITableView? {
    if let table = view as? UITableView { return table }
    return view.subviews.compactMap { self.table(in: $0) }.first
  }
}
