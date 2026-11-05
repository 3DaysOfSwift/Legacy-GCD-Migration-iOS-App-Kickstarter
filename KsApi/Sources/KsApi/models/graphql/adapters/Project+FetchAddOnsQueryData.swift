import Foundation
import GraphAPI

extension Project {
  static func project(from data: GraphAPI.FetchAddOnsQuery.Data) -> Project? {
    let addOns = data.project?.addOns?.nodes?
      .compactMap { node -> Reward? in
        guard let node else { return nil }

        let rewardFragment = node.fragments.rewardFragment
        let imageFragment = node.fragments.rewardImageFragment
        let itemFragment = node.fragments.rewardItemsFragment

        let expandedShippingRules = node.shippingRulesExpanded?.nodes?
          .compactMap { node in node?.fragments.shippingRuleFragment }
          .compactMap(ShippingRule.shippingRule(from:))

        return Reward.reward(
          from: rewardFragment,
          expandedShippingRules: expandedShippingRules,
          rewardItems: RewardsItem.rewardItemsData(from: itemFragment),
          rewardImage: Reward.Image.rewardPhoto(from: imageFragment)
        )
      }

    guard
      let fragment = data.project?.fragments.projectFragment,
      let project = Project.project(
        from: fragment,
        flagging: nil,
        addOns: addOns,
        extendedProjectProperties: nil,
        video: nil
      )
    else { return nil }

    return project
  }
}
