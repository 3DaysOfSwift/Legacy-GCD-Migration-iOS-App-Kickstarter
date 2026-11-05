import KDS
import KsApi
import Prelude
import UIKit

public typealias DiscoveryProjectCellRowValue = (
  project: Project,
  category: KsApi.Category?, // FIXME: consolidate into two parameters: project, filterParams
  params: DiscoveryParams?
)

public struct PostcardMetadataData {
  public let iconImage: UIImage?
  public let labelText: String
  public let iconAndTextColor: UIColor
}

private enum PostcardMetadataType {
  case backing
  case featured

  fileprivate func data(forProject project: Project) -> PostcardMetadataData? {
    switch self {
    case .backing:
      return PostcardMetadataData(
        iconImage: image(named: "metadata-backing"),
        labelText: Strings.discovery_baseball_card_metadata_backer(),
        iconAndTextColor: LegacyColors.ksr_create_700.uiColor()
      )
    case .featured:
      guard let rootCategory = project.category?.parentName else { return nil }
      return PostcardMetadataData(
        iconImage: image(named: "metadata-featured"),
        labelText: Strings.discovery_baseball_card_metadata_featured_project(
          category_name: rootCategory
        ),
        iconAndTextColor: LegacyColors.ksr_support_700.uiColor()
      )
    }
  }
}

@MainActor
final class DiscoveryPostcardViewModel {
  enum Event {
    case backersTitleLabelText(String)
    case backersSubtitleLabelText(String)
    case cellAccessibilityLabel(String)
    case cellAccessibilityValue(String)
    case deadlineSubtitleLabelText(String)
    case deadlineTitleLabelText(String)
    case fundingProgressBarViewHidden(Bool)
    case fundingProgressContainerViewHidden(Bool)
    case locationStackViewHidden(Bool)
    case locationLabelText(String)
    case metadataLabelText(String)
    case metadataIcon(UIImage?)
    case metadataIconImageViewTintColor(UIColor)
    case metadataTextColor(UIColor)
    case metadataViewHidden(Bool)
    case percentFundedTitleLabelText(String)
    case progressPercentage(Float)
    case projectImageURL(URL?)
    case projectNameAndBlurbLabelText(NSAttributedString)
    case projectStateIconHidden(Bool)
    case projectStateStackViewHidden(Bool)
    case projectStateSubtitleLabelText(String)
    case projectStateTitleLabelColor(UIColor)
    case projectStateTitleLabelText(String)
    case projectCategoryName(String)
    case projectIsStaffPickLabelHidden(Bool)
    case projectCategoryViewHidden(Bool)
    case projectCategoryStackViewHidden(Bool)
    case projectStatsStackViewHidden(Bool)
    case socialImageURL(URL?)
    case socialLabelText(String)
    case socialStackViewHidden(Bool)
  }
  var onEvent: ((Event) -> Void)?
  private var lastStateHidden: Bool?
  private var lastStateColor: UIColor?
  private var lastSocialHidden: Bool?

  func configure(with value: DiscoveryProjectCellRowValue) {
    let project = value.project
    let backers = Strings.Backers_count_separator_backers(backers_count: project.stats.backersCount)
      .split(separator: "\n").map(String.init)
    self.onEvent?(.backersTitleLabelText(backers.first ?? ""))
    self.onEvent?(.backersSubtitleLabelText(backers.last ?? ""))
    let deadline: (String, String)
    if let date = project.dates.deadline, project.state == .live {
      deadline = Format.duration(secondsInUTC: date, useToGo: true)
    } else { deadline = ("", "") }
    self.onEvent?(.deadlineTitleLabelText(deadline.0))
    self.onEvent?(.deadlineSubtitleLabelText(deadline.1))
    let metadata = postcardMetadata(forProject: project)
    self.onEvent?(.metadataViewHidden(metadata == nil))
    if let metadata {
      self.onEvent?(.metadataIcon(metadata.iconImage))
      self.onEvent?(.metadataLabelText(metadata.labelText))
      self.onEvent?(.metadataTextColor(metadata.iconAndTextColor))
      self.onEvent?(.metadataIconImageViewTintColor(metadata.iconAndTextColor))
    }
    self.onEvent?(.percentFundedTitleLabelText(project.state == .live ? Format.percentage(project.stats.percentFunded) : ""))
    self.onEvent?(.progressPercentage(clamp(0, 1)(project.stats.fundingProgress)))
    self.onEvent?(.projectImageURL(URL(string: project.photo.full)))
    self.onEvent?(.projectNameAndBlurbLabelText(projectAttributedNameAndBlurb(project)))
    self.onEvent?(.projectStateIconHidden(project.state != .successful))
    let stateHidden = project.state == .live
    if self.lastStateHidden != stateHidden {
      self.lastStateHidden = stateHidden
      self.onEvent?(.projectStateStackViewHidden(stateHidden))
      self.onEvent?(.projectStatsStackViewHidden(!stateHidden))
    }
    self.onEvent?(.projectStateSubtitleLabelText(project.state != .live ? Format.date(secondsInUTC: project.dates.stateChangedAt, dateStyle: .medium, timeStyle: .none) : ""))
    let stateColor = project.state == .successful ? LegacyColors.ksr_create_700.uiColor() : LegacyColors.ksr_support_700.uiColor()
    if self.lastStateColor != stateColor {
      self.lastStateColor = stateColor
      self.onEvent?(.projectStateTitleLabelColor(stateColor))
    }
    let stateTitle = fundingStatusText(forProject: project)
    self.onEvent?(.projectStateTitleLabelText(stateTitle))
    self.onEvent?(.projectCategoryName(project.category?.name ?? ""))
    let categoryHidden: Bool
    if let category = value.category, !category.isRoot, let projectCategory = project.category {
      categoryHidden = Int(projectCategory.id) == category.intID
    } else { categoryHidden = false }
    let staffHidden = !project.staffPick
    self.onEvent?(.projectCategoryViewHidden(categoryHidden))
    self.onEvent?(.projectIsStaffPickLabelHidden(staffHidden))
    self.onEvent?(.projectCategoryStackViewHidden(categoryHidden && staffHidden))
    self.onEvent?(.socialImageURL(project.personalization.friends?.first.flatMap { URL(string: $0.avatar.medium) }))
    self.onEvent?(.socialLabelText(project.personalization.friends.flatMap(socialText(forFriends:)) ?? ""))
    let socialHidden = project.personalization.friends == nil || project.personalization.friends?.count ?? 0 == 0
    if self.lastSocialHidden != socialHidden {
      self.lastSocialHidden = socialHidden
      self.onEvent?(.socialStackViewHidden(socialHidden))
    }
    self.onEvent?(.fundingProgressContainerViewHidden(project.state == .canceled || project.state == .suspended))
    self.onEvent?(.fundingProgressBarViewHidden(project.state == .failed))
    self.onEvent?(.cellAccessibilityLabel(project.name))
    self.onEvent?(.cellAccessibilityValue("\(project.blurb). \(stateTitle)"))
    self.onEvent?(.locationStackViewHidden(value.params != nil))
    self.onEvent?(.locationLabelText(project.location?.name ?? ""))
  }
}

private func socialText(forFriends friends: [User]) -> String? {
  if friends.count == 1 {
    return Strings.project_social_friend_is_backer(friend_name: friends[0].name)
  } else if friends.count == 2 {
    return Strings.project_social_friend_and_friend_are_backers(
      friend_name: friends[0].name,
      second_friend_name: friends[1].name
    )
  } else if friends.count > 2 {
    let remainingCount = max(0, friends.count - 2)
    return Strings.discovery_baseball_card_social_friends_are_backers(
      friend_name: friends[0].name,
      second_friend_name: friends[1].name,
      remaining_count: remainingCount
    )
  } else {
    return nil
  }
}

private func fundingStatusText(forProject project: Project) -> String {
  switch project.state {
  case .canceled:
    return Strings.Project_cancelled()
  case .failed:
    return Strings.dashboard_creator_project_funding_unsuccessful()
  case .successful:
    return Strings.Funding_successful()
  case .suspended:
    return Strings.dashboard_creator_project_funding_suspended()
  case .live, .purged, .started, .submitted:
    return ""
  }
}

// Returns the disparate metadata data for a project based on metadata precedence.
@MainActor
private func postcardMetadata(forProject project: Project) -> PostcardMetadataData? {
  let today = AppEnvironment.current.dateType.init().date

  let userHasBacked = userIsBackingProject(project)
  let projectIsFeaturedToday = project.isFeaturedToday(today: today)

  if userHasBacked {
    return PostcardMetadataType.backing.data(forProject: project)
  } else if projectIsFeaturedToday {
    return PostcardMetadataType.featured.data(forProject: project)
  } else {
    return nil
  }
}
