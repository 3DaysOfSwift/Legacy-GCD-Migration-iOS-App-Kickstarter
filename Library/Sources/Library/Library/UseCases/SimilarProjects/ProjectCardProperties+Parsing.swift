import Foundation
import GraphAPI
import Kingfisher
import KsApi

public extension ProjectCardProperties {
  init?(_ fragment: GraphAPI.ProjectCardFragment) {
    self.init(ProjectCardResponse(fragment))
  }

  init?(_ fragment: ProjectCardResponse) {
    guard
      let imageURLString = fragment.imageURL,
      let imageURL = URL(string: imageURLString),
      let state = Project.State(rawValue: fragment.state.lowercased())
    else {
      return nil
    }

    func timestamp(from: String?) -> Foundation.Date? {
      from
        .flatMap { timestamp in Int(timestamp) }
        .flatMap { timestamp in Date(timeIntervalSince1970: TimeInterval(timestamp)) }
    }

    let launchedAt = timestamp(from: fragment.launchedAt)
    let deadlineAt = timestamp(from: fragment.deadlineAt)

    self.projectID = fragment.pid
    self.image = .network(imageURL)
    self.name = fragment.name
    self.isLaunched = fragment.isLaunched
    self.isStarred = fragment.isWatched
    self.isPrelaunchActivated = fragment.prelaunchActivated
    self.isInPostCampaignPledgingPhase = fragment.isInPostCampaignPledgingPhase
    self.isPostCampaignPledgingEnabled = fragment.postCampaignPledgingEnabled
    self.launchedAt = launchedAt
    self.deadlineAt = deadlineAt
    self.percentFunded = fragment.percentFunded
    self.state = state
    self.goal = fragment.goal
    self.pledged = fragment.pledged
    self.url = fragment.url

    self.projectAnalytics = fragment.analytics
    self.projectPamphletMainCell = fragment.details.projectPamphletMainCellProperties
  }
}

extension ProjectCardProperties: ProjectPamphletMainCellConfiguration {
  public var projectAnalyticsProperties: any ProjectAnalyticsProperties {
    self.projectAnalytics
  }

  public var projectPamphletMainCellProperties: ProjectPamphletMainCellProperties {
    self.projectPamphletMainCell
  }

  public var projectCreatorProperties: ProjectCreatorProperties {
    ProjectCreatorProperties(id: self.projectID, name: self.name, projectWebURL: self.url)
  }

  public var projectWebURL: String {
    self.url
  }

  public var videoViewProperties: VideoViewProperties {
    self.projectPamphletMainCellProperties.videoViewProperties
  }
}

extension GraphAPI.ProjectPamphletMainCellPropertiesFragment: HasProjectPamphletMainCellProperties {
  public var projectPamphletMainCellProperties: ProjectPamphletMainCellProperties {
    ProjectCardResponse.Details(self).projectPamphletMainCellProperties
  }
}

extension ProjectCardResponse.Details: HasProjectPamphletMainCellProperties {
  public var projectPamphletMainCellProperties: ProjectPamphletMainCellProperties {
    let state = Project.State(rawValue: self.state.lowercased()) ?? .failed

    let video: (hls: String?, high: String)?
    if let high = self.videoHigh {
      video = (hls: self.videoHLS, high: high)
    } else {
      video = nil
    }

    return ProjectPamphletMainCellProperties(
      param: .id(self.pid),
      name: self.name,
      blurb: self.projectDescription,
      creatorName: self.creatorName,
      creatorAvatarURL: self.creatorAvatarURL,
      creatorId: self.creatorId,
      isCreatorBlocked: self.isCreatorBlocked,
      state: state,
      stateChangedAt: TimeInterval(self.stateChangedAt) ?? 0,
      photo: self.photo,
      displayPrelaunch: nil,
      isBacking: self.isBacking,
      backersCount: self.backersCount,
      categoryName: self.categoryName,
      locationName: self.locationName,
      deadline: TimeInterval(self.deadlineAt ?? "0") ?? 0,
      fxRate: Float(self.fxRate),
      projectUsdExchangeRate: Float(self.projectUsdExchangeRate),
      goal: (Int(Double(self.goalAmount ?? "0") ?? 0), self.goalCurrency, self.goalSymbol),
      pledged: (Int(Double(self.pledgedAmount ?? "0") ?? 0), self.pledgedCurrency, self.pledgedSymbol),
      convertedPledgedAmount: nil,
      currency: self.currency,
      userCurrency: nil,
      country: Project.Country(currencyCode: self.country) ?? .us,
      projectNotice: "",
      video: video,
      webURL: self.url
    )
  }
}
