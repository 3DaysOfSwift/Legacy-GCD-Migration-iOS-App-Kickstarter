import Foundation
import KsApi
import Observation

@MainActor @Observable
public final class FindFriendsFriendFollowCellViewModel {
  public private(set) var cellAccessibilityValue: String?
  public private(set) var enableFollowButton: Bool?
  public private(set) var enableUnfollowButton: Bool?
  public private(set) var followButtonAccessibilityLabel: String?
  public private(set) var hideFollowButton: Bool?
  public private(set) var hideProjectsCreated: Bool?
  public private(set) var hideUnfollowButton: Bool?
  public private(set) var imageURL: URL?
  public private(set) var location: String?
  public private(set) var name: String?
  public private(set) var projectsBackedText: String?
  public private(set) var projectsCreatedText: String?
  public private(set) var unfollowButtonAccessibilityLabel: String?
  @ObservationIgnored var onChange: (@MainActor () -> Void)?
  @ObservationIgnored private let feature: FriendsFeature
  @ObservationIgnored private let delay: @MainActor () async throws -> Void
  @ObservationIgnored private var followObservation: Task<Void, Never>?
  @ObservationIgnored private var unfollowObservation: Task<Void, Never>?
  private var friend: User?

  public init(feature: FriendsFeature? = nil, delay: (@MainActor () async throws -> Void)? = nil) {
    self.feature = feature ?? AppModel.shared.friendsFeature
    self.delay = delay ?? {
      let seconds = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  }

  public func configureWith(friend: User) {
    let friend = self.feature.cached(friend)
    self.friend = friend
    self.imageURL = URL(string: friend.avatar.medium)
    self.location = friend.location?.displayableName ?? ""
    self.name = friend.name
    self.projectsBackedText = Strings.social_following_friend_projects_count_backed(backed_count: friend.stats.backedProjectsCount ?? 0)
    let count = friend.stats.createdProjectsCount ?? 0
    self.hideProjectsCreated = count == 0
    if count > 0 { self.projectsCreatedText = Strings.social_following_friend_projects_count_created(created_count: count) }
    self.followButtonAccessibilityLabel = Strings.Follow_friend_name(friend_name: friend.name)
    self.unfollowButtonAccessibilityLabel = Strings.Unfollow_friend_name(friend_name: friend.name)
    self.applyFollowing(friend.isFriend ?? false)
  }

  private func applyFollowing(_ following: Bool) {
    self.hideFollowButton = following
    self.hideUnfollowButton = !following
    self.enableFollowButton = !following
    self.enableUnfollowButton = following
    self.cellAccessibilityValue = following ? Strings.Followed() : Strings.Not_followed()
    self.onChange?()
  }

  public func followButtonTapped() { self.setFollowing(true) }
  public func unfollowButtonTapped() { self.setFollowing(false) }

  private func setFollowing(_ following: Bool) {
    guard let friend = self.friend else { return }
    let generation = self.feature.sessionFeature.generation
    let sessionUser = self.feature.sessionFeature.currentUser?.id
    let command = self.feature.startFollowing(user: friend, following: following)
    if following { self.followObservation?.cancel(); self.enableFollowButton = false }
    else { self.unfollowObservation?.cancel(); self.enableUnfollowButton = false }
    self.onChange?()
    let task = Task { [weak self] in
      do {
        let updated = try await command.value
        guard let self, !Task.isCancelled else { return }
        if following { self.enableFollowButton = true } else { self.enableUnfollowButton = true }
        self.onChange?()
        try await self.delay()
        try Task.checkCancellation()
        guard self.friend?.id == updated.id, self.feature.sessionFeature.generation == generation,
              self.feature.sessionFeature.currentUser?.id == sessionUser else { return }
        self.applyFollowing(updated.isFriend ?? false)
      } catch {
        guard let self, !Task.isCancelled else { return }
        if following { self.enableFollowButton = true } else { self.enableUnfollowButton = true }
        self.onChange?()
      }
    }
    if following { self.followObservation = task } else { self.unfollowObservation = task }
  }

  func waitForObservations() async {
    await self.followObservation?.value
    await self.unfollowObservation?.value
  }
  deinit { self.followObservation?.cancel(); self.unfollowObservation?.cancel() }
}
