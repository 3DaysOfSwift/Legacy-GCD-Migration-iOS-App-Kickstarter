import KDS
import KsApi
import Prelude
import UIKit

public struct DiscoveryPillData: Equatable {
  public let imageName: String
  public let text: String
  public let type: DiscoveryProjectTagPillCellType
}

public enum DiscoveryProjectTagPillCellType: Equatable {
  case green
  case grey

  public var backgroundColor: UIColor {
    switch self {
    case .green: return LegacyColors.ksr_create_700.uiColor(opacity: 0.07)
    case .grey: return LegacyColors.ksr_support_300.uiColor()
    }
  }

  public var textColor: UIColor {
    switch self {
    case .green: return LegacyColors.ksr_create_700.uiColor()
    case .grey: return LegacyColors.ksr_support_400.uiColor()
    }
  }
}

public typealias BoldedAttributedLabelData = (boldedString: String, inString: String)
public typealias FacepileViewData = (avatars: [URL], description: String)

@MainActor
public final class DiscoveryProjectCardViewModel {
  struct Display {
    let backerCount: BoldedAttributedLabelData
    let facepile: FacepileViewData?
    let facepileHidden: Bool
    let goalMetIconHidden: Bool
    let tags: [DiscoveryPillData]
    let percentFunded: BoldedAttributedLabelData
    let blurb: String
    let imageURL: URL?
    let name: String
    let statusIcon: String?
    let status: BoldedAttributedLabelData?
    let tagsHidden: Bool
    let backerHidden: Bool
  }

  public init() {}

  func configure(with value: DiscoveryProjectCellRowValue) -> Display {
    let project = value.project
    let count = project.stats.backersCount
    let percentage = "\(project.stats.percentFunded)%"
    let funded: BoldedAttributedLabelData = project.stats.goalMet
      ? (Strings.Goal_met(), Strings.Goal_met())
      : (percentage, Strings.percentage_funded(percentage: percentage))
    let icon: String?
    let status: BoldedAttributedLabelData?
    switch project.state {
    case .canceled:
      icon = "icon--prohibit"; status = ("", Strings.profile_projects_status_canceled())
    case .failed:
      icon = "icon--prohibit"; status = ("", Strings.profile_projects_status_unsuccessful())
    case .successful:
      icon = "icon--check"; status = ("", Strings.profile_projects_status_successful())
    case .live:
      icon = "icon--clock"
      if let deadline = project.dates.deadline {
        let (duration, unit) = Format.duration(secondsInUTC: deadline, abbreviate: false, useToGo: true,
                                               env: AppEnvironment.current)
        status = (duration, "\(duration) \(unit)")
      } else { status = ("", "") }
    case .started, .submitted, .suspended, .purged:
      icon = nil; status = nil
    }
    let friends = project.personalization.friends
    return Display(
      backerCount: (Format.wholeNumber(count), Strings.general_backer_count_backers(backer_count: count)),
      facepile: friends.flatMap(facepileData(for:)),
      facepileHidden: friends?.isEmpty ?? true,
      goalMetIconHidden: !project.stats.goalMet,
      tags: projectTags(project: project, category: value.category),
      percentFunded: funded,
      blurb: project.blurb,
      imageURL: URL(string: project.photo.full),
      name: project.name,
      statusIcon: icon,
      status: status,
      tagsHidden: projectTagsViewShouldHide(project: project, category: value.category),
      backerHidden: !userIsBackingProject(project)
    )
  }
}

private func projectTagsViewShouldHide(project: Project, category: KsApi.Category?) -> Bool {
  let categoryTagShouldHide = projectCategoryTagShouldHide(for: project, in: category)
  let pwlTagShouldHide = projectPWLTagShouldHide(project: project)

  return categoryTagShouldHide && pwlTagShouldHide
}

private func projectCategoryTagShouldHide(for project: Project, in category: KsApi.Category?) -> Bool {
  guard let category = category, !category.isRoot else {
    // Always show category when filter category is nil, or we're in a root category
    return false
  }

  return project.category?.id == category.intID
}

private func projectPWLTagShouldHide(project: Project) -> Bool {
  return !project.staffPick
}

private func projectTags(project: Project, category: KsApi.Category?) -> [DiscoveryPillData] {
  let shouldShowCategoryTag = !projectCategoryTagShouldHide(for: project, in: category)
  let shouldShowPWLTag = !projectPWLTagShouldHide(project: project)

  var tags: [DiscoveryPillData] = []

  if shouldShowPWLTag {
    let pwlTag = DiscoveryPillData(
      imageName: "icon--small-k",
      text: Strings.Projects_We_Love(),
      type: .green
    )

    tags.append(pwlTag)
  }

  if shouldShowCategoryTag, let category = project.category {
    let categoryTag = DiscoveryPillData(
      imageName: "icon--compass",
      text: category.name,
      type: .grey
    )

    tags.append(categoryTag)
  }

  return tags
}

private func facepileData(for friendsList: [User]) -> FacepileViewData? {
  guard !friendsList.isEmpty else { return nil }

  let avatars = friendsList.prefix(3).map(\.avatar.small).compactMap(URL.init(string:))

  let remainingCount = friendsList.count - 1
  let description = Strings.Social_friend_is_backer(
    friend_name: friendsList[0].name,
    remaining_count: remainingCount
  )

  return (avatars, description)
}
