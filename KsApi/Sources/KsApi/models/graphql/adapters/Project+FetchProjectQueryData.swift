import Apollo
import Foundation
import GraphAPI
import Prelude

extension Project {
  public struct ProjectPamphletData: Decodable, Sendable {
    public let project: Project
    public let backingId: Int?
  }

  internal static func project(
    from data: GraphAPI.FetchProjectByParamQuery.Data
  ) -> (Project?, Int?) {
    var projectBackingId: Int?

    if let backingId = data.project?.backing?.id {
      projectBackingId = decompose(id: backingId)
    }

    let videoFragment = data.project?.video?.fragments.projectVideoFragment

    guard
      let fragment = data.project?.fragments.projectFragment,
      let noRewardFragment = data.project?.fragments.noRewardRewardFragment,
      let extendedFragment = data.project?.fragments.extendedProjectPropertiesFragment,
      let project = Project.project(
        from: fragment,
        flagging: data.project?.flagging != nil,
        rewards: [Reward.noRewardReward(from: noRewardFragment)],
        addOns: nil,
        backing: nil,
        extendedProjectProperties: ExtendedProjectProperties.extendedProject(from: extendedFragment),
        video: Project.Video.projectVideo(from: videoFragment)
      )
    else { return (nil, nil) }

    return (project, projectBackingId)
  }
}
