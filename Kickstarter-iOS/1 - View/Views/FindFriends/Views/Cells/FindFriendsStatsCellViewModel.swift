import KsApi
import Observation

@MainActor @Observable
public final class FindFriendsStatsCellViewModel {
  public init() {}
  public private(set) var backedProjectsCountText: String?
  public private(set) var followAllText: String?
  public private(set) var friendsCountText: String?
  public private(set) var hideFollowAllButton: Bool?
  private var remoteFriendCount: Int?

  public func configureWith(stats: FriendStatsEnvelope, source: FriendsSource) {
    let count = stats.stats.remoteFriendsCount
    self.remoteFriendCount = count
    self.backedProjectsCountText = Format.wholeNumber(stats.stats.friendProjectsCount)
    self.followAllText = Strings.social_following_stats_button_follow_all_friends(remote_friends_count: count)
    self.friendsCountText = Format.wholeNumber(count)
    self.hideFollowAllButton = count <= 2
  }

  public func countForFollowAllAction() -> Int? { self.remoteFriendCount }
}
