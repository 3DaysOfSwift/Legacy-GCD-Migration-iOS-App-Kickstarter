import Foundation
import GraphAPI

public struct ProjectAndBackingEnvelope: Equatable, Decodable, Sendable {
  public var project: Project
  public var backing: Backing
}

// MARK: - GraphQL Adapters

extension ProjectAndBackingEnvelope {
  static func envelope(from data: GraphAPI.FetchBackingQuery.Data) -> ProjectAndBackingEnvelope? {
    let addOns = data.backing?.addOns?.nodes?
      .compactMap { $0 }
      .compactMap { node -> Reward? in
        let rewardFragment = node.fragments.rewardFragment
        let itemFragment = node.fragments.rewardItemsFragment
        let imageFragment = node.fragments.rewardImageFragment

        return Reward.reward(
          from: rewardFragment,
          rewardItems: RewardsItem.rewardItemsData(from: itemFragment),
          rewardImage: Reward.Image.rewardPhoto(from: imageFragment)
        )
      }

    var paymentIncrements: [PledgePaymentIncrement] = []

    if let backingIncrements = data.backing?.paymentIncrements {
      paymentIncrements = backingIncrements
        .compactMap {
          PledgePaymentIncrement(withGraphQLFragment: $0.fragments.paymentIncrementFragment)
        }
    }

    guard
      let backingFragment = data.backing?.fragments.backingFragment,
      let projectFragment = data.backing?.project?.fragments.projectFragment,
      let backing = Backing.backing(
        from: backingFragment,
        addOns: addOns,
        paymentIncrements: paymentIncrements
      ),
      let project = Project.project(
        from: projectFragment,
        flagging: nil,
        backing: backing,
        extendedProjectProperties: nil,
        video: nil
      )
    else {
      return nil
    }

    return ProjectAndBackingEnvelope(project: project, backing: backing)
  }
}
