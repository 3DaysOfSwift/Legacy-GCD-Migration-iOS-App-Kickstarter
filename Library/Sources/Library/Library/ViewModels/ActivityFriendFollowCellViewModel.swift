import KDS
import KsApi
import Prelude
import ReactiveSwift
import UIKit

@MainActor
public protocol ActivityFriendFollowCellViewModelInputs {
  /// Call to configure activity with Activity.
  func configureWith(activity: Activity)

  /// Call when follow button is tapped.
  func followButtonTapped()
}

@MainActor
public protocol ActivityFriendFollowCellViewModelOutputs {
  /// Emits a URL to the friend image.
  var friendImageURL: Signal<URL?, Never> { get }

  /// Emits whether to hide the follow button.
  var hideFollowButton: Signal<Bool, Never> { get }

  /// Emits text for title label.
  var title: Signal<NSAttributedString, Never> { get }
}

@MainActor
public final class ActivityFriendFollowCellViewModel: ActivityFriendFollowCellViewModelInputs,
  ActivityFriendFollowCellViewModelOutputs {
  public init(feature: FriendsFeature? = nil) {
    let feature = feature ?? AppModel.shared.friendsFeature
    let configuredActivity = self.activityProperty
    let friend = self.activityProperty.signal.skipNil()
      .map(Activity.lens.user.view)
      .skipNil()
      .map { feature.cached($0) }

    self.friendImageURL = friend.map { URL.init(string: $0.avatar.small) }

    self.title = friend.map {
      let string = Strings.activity_user_name_is_now_following_you(user_name: "<b>\($0.name)</b>")
      return string.simpleHtmlAttributedString(
        base: [
          NSAttributedString.Key.font: UIFont.ksr_subhead(size: 14.0),
          NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
        ],
        bold: [
          NSAttributedString.Key.font: UIFont.ksr_headline(size: 14.0),
          NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor()
        ]
      ) ?? NSAttributedString(string: "")
    }

    let followFriendEvent = friend.takeWhen(self.followButtonTappedProperty.signal)
      .switchMap { user in
        feature.delayed(feature.setFollowingResult(user: user, following: true))
          .materialize()
      }

    let followFriendSuccess = followFriendEvent.values()
      .filter { $0.id == configuredActivity.value?.user?.id }

    self.hideFollowButton = Signal.merge(friend, followFriendSuccess)
      .map { $0.isFriend ?? false }
      .skipRepeats()
  }

  fileprivate let activityProperty = MutableProperty<Activity?>(nil)
  public func configureWith(activity: Activity) {
    self.activityProperty.value = activity
  }

  fileprivate let followButtonTappedProperty = MutableProperty(())
  public func followButtonTapped() {
    self.followButtonTappedProperty.value = ()
  }

  public let friendImageURL: Signal<URL?, Never>
  public let hideFollowButton: Signal<Bool, Never>
  public let title: Signal<NSAttributedString, Never>

  public var inputs: ActivityFriendFollowCellViewModelInputs { return self }
  public var outputs: ActivityFriendFollowCellViewModelOutputs { return self }
}
