import Foundation

import UIKit

enum PledgeRewardsSummaryRow: Hashable, Sendable {
  case header(UUID)
  case reward(UUID)
  case addOns(UUID)
  case shipping(UUID)
  case bonusSupport(UUID)
}

/**
 A `UITableViewDiffableDataSource` that accepts two types.

 - `PledgeRewardsSummarySection`: defines the section type of the table.
 - `PledgeRewardsSummaryRow`: a Sendable section-qualified identifier. Attributed display data stays in the MainActor model store.

 These types are defined above and each UITableViewCell is configured based on the row being rendered.
 */

class PledgeRewardsSummaryDiffableDataSource: UITableViewDiffableDataSource<
  PledgeRewardsSummarySection,
  PledgeRewardsSummaryRow
> {
  private let models = PledgeSummaryModels()
  private var updateID = UUID()

  init(tableView: UITableView) {
    let models = self.models
    super.init(tableView: tableView) { tableView, indexPath, row in
      guard let model = models.values[row.id] else { return nil }
      switch row {
      case .header:
        let cell = tableView.dequeueReusableCell(
          withClass: PostCampaignPledgeRewardsSummaryHeaderCell.self,
          for: indexPath
        ) as! PostCampaignPledgeRewardsSummaryHeaderCell

        cell.configureWith(value: model)

        return cell
      case .reward, .addOns, .shipping, .bonusSupport:
        let cell = tableView.dequeueReusableCell(
          withClass: PostCampaignPledgeRewardsSummaryCell.self,
          for: indexPath
        ) as! PostCampaignPledgeRewardsSummaryCell

        cell.configureWith(value: model)

        return cell
      }
    }
  }

  func apply(header: PledgeSummaryRewardCellData?, rewards: [PledgeSummaryRewardCellData]) {
    let snapshot = diffableDataSourceSnapshot(using: header, rewards)
    let values = rewards + (header.map { [$0] } ?? [])
    for value in values { self.models.values[value.id] = value }
    let updateID = UUID()
    self.updateID = updateID
    let retainedIDs = Set(snapshot.itemIdentifiers.map(\.id))
    // Retain outgoing presentation values until their transition completes. Only
    // the current snapshot may prune storage after overlapping updates.
    self.apply(snapshot, animatingDifferences: true) { [weak self] in
      guard let self, self.updateID == updateID else { return }
      self.models.values = self.models.values.filter { retainedIDs.contains($0.key) }
    }
  }

}

/**
 Creates `NSDiffableDataSourceSnapshot` to apply to the pledge summary table view data source on our crowdfunding and late pledge checkout screens.

 - parameter headerData: The `PledgeExpandableHeaderRewardCellData`that represents the table's custom header `UITableViewCell`.
 - parameter rewards: The `[PledgeExpandableHeaderRewardCellData]`that represents the tables reward data (baseReward, addOns, and bonusSupport).

 - returns: A `NSDiffableDataSourceSnapshot` that will be applied to the UITableView's Diffable Data Source `PledgeRewardsSummaryDiffableDataSource`.
 */

func diffableDataSourceSnapshot(
  using headerData: PledgeSummaryRewardCellData?,
  _ rewards: [PledgeSummaryRewardCellData]
)
  -> NSDiffableDataSourceSnapshot<PledgeRewardsSummarySection, PledgeRewardsSummaryRow> {
  var snapshot = NSDiffableDataSourceSnapshot<PledgeRewardsSummarySection, PledgeRewardsSummaryRow>()

  // MARK: Header

  /// Define the sections of the table and what data to use in each section.
  if let header = headerData {
    snapshot.appendSections([.header])
    snapshot.appendItems([.header(header.id)], toSection: .header)
  }

  // MARK: Reward

  if let baseReward = rewards.first {
    snapshot.appendSections([.reward])
    snapshot.appendItems([.reward(baseReward.id)], toSection: .reward)
  }

  // MARK: Add-Ons

  let addOnsData = rewards
    .filter { reward in reward.id != rewards.first?.id && reward.type == .reward }
    .map { PledgeRewardsSummaryRow.addOns($0.id) }

  /// We only want to add an add-ons section if any have been selected
  if addOnsData.count > 0 {
    snapshot.appendSections([.addOns])
    snapshot.appendItems(addOnsData, toSection: .addOns)
  }

  // MARK: Shipping

  let shippingInfo = rewards
    .filter { reward in reward.type == .shipping }
    .map { PledgeRewardsSummaryRow.shipping($0.id) }

  if let shipping = shippingInfo.first {
    snapshot.appendSections([.shipping])
    snapshot.appendItems([shipping], toSection: .shipping)
  }

  // MARK: Bonus Support

  let bonusSupport = rewards
    .filter { reward in reward.type == .bonusSupport }
    .map { PledgeRewardsSummaryRow.bonusSupport($0.id) }

  if let bonusSupportData = bonusSupport.first {
    snapshot.appendSections([.bonusSupport])
    snapshot.appendItems([bonusSupportData], toSection: .bonusSupport)
  }

  return snapshot
}

@MainActor
private final class PledgeSummaryModels {
  var values: [UUID: PledgeSummaryRewardCellData] = [:]
}

extension PledgeRewardsSummaryRow {
  var id: UUID {
    switch self {
    case let .header(id), let .reward(id), let .addOns(id), let .shipping(id), let .bonusSupport(id):
      return id
    }
  }
}
