import KsApi
import UIKit

@MainActor
public final class ActivitySampleBackingCellViewModel {
  public struct Display {
    let title: NSAttributedString
    let imageURL: URL?
  }
  var onGoToActivity: (() -> Void)?
  public init() {}

  public func configureWith(activity: Activity) -> Display {
    let string = Strings.activity_friend_backed_project_name_by_creator_name(
      friend_name: activity.user?.name ?? "",
      project_name: activity.project?.name ?? "",
      creator_name: activity.project?.creator.name ?? ""
    )
    return Display(
      title: string.simpleHtmlAttributedString(font: UIFont.ksr_subhead()) ?? NSAttributedString(string: ""),
      imageURL: (activity.user?.avatar.medium).flatMap(URL.init)
    )
  }

  public func seeAllActivityTapped() { self.onGoToActivity?() }
}
