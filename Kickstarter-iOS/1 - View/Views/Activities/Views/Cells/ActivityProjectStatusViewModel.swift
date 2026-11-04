import KDS
import KsApi
import Prelude
import Observation
import UIKit

@MainActor @Observable
public final class ActivityProjectStatusViewModel {
  public init() {}
  public private(set) var fundingBarColor = UIColor.clear
  public private(set) var fundingProgressPercentage: Float?
  public private(set) var metadataBackgroundColor = UIColor.clear
  public private(set) var metadataText = ""
  public private(set) var percentFundedText = NSAttributedString(string: "")
  public private(set) var projectImageURL: URL?
  public private(set) var projectName: String?

  public func configureWith(activity: Activity) {
    self.fundingBarColor = progressBarColor(forActivityCategory: activity.category)
    self.metadataBackgroundColor = metadataColor(forActivityCategory: activity.category)
    let creator = activity.project?.creator
    self.metadataText = activityProjectStatusViewModelMetadataString(
      forActivityCategory: activity.category,
      isCreatorUser: AppEnvironment.current.currentUser == creator,
      friendName: creator?.name ?? ""
    )
    self.percentFundedText = activityProjectStatusViewModelPercentFundedString(forActivity: activity)
    if let project = activity.project {
      self.fundingProgressPercentage = clamp(0, 1)(project.stats.fundingProgress)
      self.projectImageURL = URL(string: project.photo.full)
      self.projectName = project.name
    }
  }
}

private func progressBarColor(forActivityCategory category: Activity.Category) -> UIColor {
  switch category {
  case .cancellation, .failure, .suspension:
    return LegacyColors.ksr_support_700.uiColor()
  case .launch, .success:
    return LegacyColors.ksr_create_700.uiColor()
  default:
    return LegacyColors.ksr_create_700.uiColor()
  }
}

private func metadataColor(forActivityCategory category: Activity.Category) -> UIColor {
  switch category {
  case .cancellation, .failure, .suspension:
    return LegacyColors.ksr_support_700.uiColor()
  case .launch:
    return LegacyColors.ksr_create_700.uiColor()
  case .success:
    return LegacyColors.ksr_create_700.uiColor()
  default:
    return LegacyColors.ksr_create_700.uiColor()
  }
}

private func activityProjectStatusViewModelMetadataString(
  forActivityCategory category: Activity.Category,
  isCreatorUser: Bool, friendName: String
) -> String {
  switch category {
  case .cancellation:
    return Strings.Project_Cancelled()
  case .failure:
    return Strings.Unsuccessfully_Funded()
  case .launch:
    return isCreatorUser
      ? Strings.You_Launched()
      : Strings.Friend_name_launched_a_project(friend_name: friendName)
  case .success:
    return Strings.activity_successfully_funded()
  case .suspension:
    return Strings.Project_Suspended()
  default:
    return ""
  }
}

@MainActor
private func activityProjectStatusViewModelPercentFundedString(forActivity activity: Activity) -> NSAttributedString {
  guard let project = activity.project else { return NSAttributedString(string: "") }

  let percentage = Format.percentage(project.stats.percentFunded)

  return NSAttributedString(string: percentage, attributes: [
    NSAttributedString.Key.font: UIFont.ksr_caption1(size: 10),
    NSAttributedString.Key.foregroundColor: LegacyColors.ksr_create_700.uiColor()
  ])
}
