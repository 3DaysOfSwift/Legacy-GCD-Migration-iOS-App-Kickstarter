import KDS
import KsApi
import Prelude
import Observation
import UIKit

@MainActor @Observable
public final class ActivityFriendBackingViewModel {
  public init() {}
  public private(set) var friendImageURL: URL?
  public private(set) var friendTitle = NSAttributedString(string: "")
  public private(set) var fundingBarColor = UIColor.clear
  public private(set) var fundingProgressPercentage: Float?
  public private(set) var percentFundedText = NSAttributedString(string: "")
  public private(set) var projectName = ""
  public private(set) var projectImageURL: URL?
  public private(set) var cellAccessibilityLabel = ""

  public func configureWith(activity: Activity) {
    self.friendImageURL = (activity.user?.avatar.small).flatMap(URL.init(string:))
    let categoryID = activity.project?.category?.parentId ?? activity.project?.category?.id
    if let categoryID {
      let title = string(forCategoryId: String(categoryID), friendName: activity.user?.name ?? "")
      self.friendTitle = title.simpleHtmlAttributedString(
        base: [.font: UIFont.ksr_subhead(size: 12), .foregroundColor: LegacyColors.ksr_support_400.uiColor()],
        bold: [.font: UIFont.ksr_subhead(size: 12), .foregroundColor: LegacyColors.ksr_support_700.uiColor()],
        italic: [.font: UIFont.ksr_subhead(size: 12), .foregroundColor: LegacyColors.ksr_support_700.uiColor()]
      ) ?? NSAttributedString(string: "")
    } else { self.friendTitle = NSAttributedString(string: "") }
    self.fundingBarColor = progressBarColor(forActivityCategory: activity.category)
    if let project = activity.project {
      self.fundingProgressPercentage = clamp(0, 1)(project.stats.fundingProgress)
    }
    self.percentFundedText = activityFriendBackingViewModelPercentFundedString(forActivity: activity)
    self.projectName = activity.project?.name ?? ""
    self.projectImageURL = (activity.project?.photo.full).flatMap(URL.init(string:))
    self.cellAccessibilityLabel = "\(self.friendTitle.string), \(self.projectName)"
  }
}

private func progressBarColor(forActivityCategory category: Activity.Category) -> UIColor {
  switch category {
  case .cancellation, .failure, .suspension:
    return LegacyColors.ksr_support_400.uiColor()
  case .launch, .success:
    return LegacyColors.ksr_create_700.uiColor()
  default:
    return LegacyColors.ksr_create_700.uiColor()
  }
}

private func string(forCategoryId id: String, friendName: String) -> String {
  let root = RootCategory(categoryId: Int(id) ?? -1)
  switch root {
  case .art: return Strings.Friend_backed_art_project(friend_name: friendName)
  case .comics: return Strings.Friend_backed_comics_project(friend_name: friendName)
  case .dance: return Strings.Friend_backed_dance_project(friend_name: friendName)
  case .design: return Strings.Friend_backed_design_project(friend_name: friendName)
  case .fashion: return Strings.Friend_backed_fashion_project(friend_name: friendName)
  case .food: return Strings.Friend_backed_food_project(friend_name: friendName)
  case .film: return Strings.Friend_backed_film_project(friend_name: friendName)
  case .games: return Strings.Friend_backed_games_project(friend_name: friendName)
  case .journalism: return Strings.Friend_backed_journalism_project(friend_name: friendName)
  case .music: return Strings.Friend_backed_music_project(friend_name: friendName)
  case .photography: return Strings.Friend_backed_photography_project(friend_name: friendName)
  case .tech: return Strings.Friend_backed_tech_project(friend_name: friendName)
  case .theater: return Strings.Friend_backed_theater_project(friend_name: friendName)
  case .publishing: return Strings.Friend_backed_publishing_project(friend_name: friendName)
  case .crafts: return Strings.Friend_backed_crafts_project(friend_name: friendName)
  case .unrecognized: return ""
  }
}

@MainActor
private func activityFriendBackingViewModelPercentFundedString(forActivity activity: Activity) -> NSAttributedString {
  guard let project = activity.project else { return NSAttributedString(string: "") }

  let percentage = Format.percentage(project.stats.percentFunded)

  return NSAttributedString(string: percentage, attributes: [
    NSAttributedString.Key.font: UIFont.ksr_caption1(size: 10),
    NSAttributedString.Key.foregroundColor: LegacyColors.ksr_create_700.uiColor()
  ])
}
