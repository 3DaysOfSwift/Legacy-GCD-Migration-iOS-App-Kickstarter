import Foundation
import KsApi

@MainActor
public final class ActivitySampleProjectCellViewModel {
  public struct Display {
    let accessibilityHint: String
    let imageURL: URL?
    let subtitle: String
    let title: String?
  }
  var onGoToActivity: (() -> Void)?
  public init() {}

  public func configureWith(activity: Activity) -> Display {
    let subtitle: String
    switch activity.category {
    case .cancellation: subtitle = Strings.activity_funding_canceled()
    case .failure: subtitle = Strings.activity_project_was_not_successfully_funded()
    case .launch: subtitle = Strings.activity_user_name_launched_project(user_name: activity.user?.name ?? "")
    case .success: subtitle = Strings.activity_successfully_funded()
    case .update:
      subtitle = Strings.activity_posted_update_number_title(
        update_number: Format.wholeNumber(activity.update?.sequence ?? 0),
        update_title: activity.update?.title ?? ""
      )
    default: subtitle = ""
    }
    return Display(
      accessibilityHint: activity.category == .update ? Strings.Opens_update() : Strings.Opens_project(),
      imageURL: (activity.project?.photo.med).flatMap(URL.init),
      subtitle: subtitle,
      title: activity.project?.name
    )
  }

  public func seeAllActivityTapped() { self.onGoToActivity?() }
}
