import KDS
import KsApi
import Observation
import UIKit

@MainActor @Observable
public final class ActivityFriendFollowCellViewModel {
  public private(set) var friendImageURL: URL?
  public private(set) var hideFollowButton: Bool?
  public private(set) var title: NSAttributedString?
  @ObservationIgnored var onChange: (@MainActor () -> Void)?
  @ObservationIgnored private let feature: FriendsFeature
  @ObservationIgnored private let delay: @MainActor () async throws -> Void
  @ObservationIgnored private var observation: Task<Void, Never>?
  private var friend: User?

  public init(feature: FriendsFeature? = nil, delay: (@MainActor () async throws -> Void)? = nil) {
    self.feature = feature ?? AppModel.shared.friendsFeature
    self.delay = delay ?? {
      let seconds = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  }

  public func configureWith(activity: Activity) {
    self.friend = activity.user.map { self.feature.cached($0) }
    guard let friend = self.friend else { return }
    self.friendImageURL = URL(string: friend.avatar.small)
    let string = Strings.activity_user_name_is_now_following_you(user_name: "<b>\(friend.name)</b>")
    self.title = string.simpleHtmlAttributedString(
      base: [.font: UIFont.ksr_subhead(size: 14), .foregroundColor: LegacyColors.ksr_support_700.uiColor()],
      bold: [.font: UIFont.ksr_headline(size: 14), .foregroundColor: LegacyColors.ksr_support_700.uiColor()]
    ) ?? NSAttributedString(string: "")
    self.hideFollowButton = friend.isFriend ?? false
  }

  public func followButtonTapped() {
    guard let friend = self.friend else { return }
    let generation = self.feature.sessionFeature.generation
    let userID = self.feature.sessionFeature.currentUser?.id
    let task = self.feature.startFollowing(user: friend, following: true)
    self.observation?.cancel()
    self.observation = Task { [weak self] in
      do {
        let result = try await task.value
        guard let self else { return }
        try await self.delay()
        try Task.checkCancellation()
        guard self.friend?.id == result.id, self.feature.sessionFeature.generation == generation,
              self.feature.sessionFeature.currentUser?.id == userID else { return }
        self.hideFollowButton = result.isFriend ?? false
        self.onChange?()
      } catch { }
    }
  }

  func waitForObservation() async { await self.observation?.value }
  deinit { self.observation?.cancel() }
}
