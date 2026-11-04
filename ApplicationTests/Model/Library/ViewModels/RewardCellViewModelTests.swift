@testable import Kickstarter_iOS
import UIKit
import XCTest
@testable import KsApi


import Prelude

@MainActor
final class RewardCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = RewardCellViewModel()

  func testPrepareForReuseResetsScrollOffset() throws {
    let cell = RewardCell(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    let scrollView = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UIScrollView }.first)
    scrollView.contentInset.top = 12
    scrollView.contentOffset = CGPoint(x: 0, y: 40)
    cell.prepareForReuse()
    XCTAssertEqual(scrollView.contentOffset.y, -12)
  }

  func testBackerLabelHidden_IsBacked() {
    let reward = Reward.template

    let project = Project.cosmicSurgery
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ reward
          |> Backing.lens.rewardId .~ reward.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
      )

    let hidden = self.vm.backerLabelHidden(for: RewardCardViewData(
      project: project,
      reward: reward,
      context: .manage,
      currentShippingLocation: nil
    ))

    XCTAssertFalse(hidden)
  }

  func testBackerLabelHidden_IsNotBacked() {
    let reward = Reward.template

    let project = Project.cosmicSurgery
      |> Project.lens.state .~ .live
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.personalization.backing .~ (
        .template
          |> Backing.lens.reward .~ Reward.noReward
          |> Backing.lens.rewardId .~ Reward.noReward.id
          |> Backing.lens.shippingAmount .~ 10
          |> Backing.lens.amount .~ 700.0
      )

    let hidden = self.vm.backerLabelHidden(for: RewardCardViewData(
      project: project,
      reward: reward,
      context: .manage,
      currentShippingLocation: nil
    ))

    XCTAssertTrue(hidden)
  }
}
