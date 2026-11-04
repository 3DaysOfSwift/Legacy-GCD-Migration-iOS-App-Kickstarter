import Foundation
import KsApi

@MainActor
public final class ActivitySampleFollowCellViewModel {
  public struct Display {
    let text: String
    let imageURL: URL?
  }
  var onGoToActivity: (() -> Void)?
  public init() {}

  public func configureWith(activity: Activity) -> Display {
    Display(
      text: Strings.activity_user_name_is_now_following_you(user_name: activity.user?.name ?? ""),
      imageURL: (activity.user?.avatar.medium).flatMap(URL.init)
    )
  }

  public func seeAllActivityTapped() { self.onGoToActivity?() }
}
