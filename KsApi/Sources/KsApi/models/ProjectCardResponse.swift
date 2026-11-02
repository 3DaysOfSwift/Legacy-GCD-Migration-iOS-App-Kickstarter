import Foundation
import GraphAPI

/// Immutable card and initial project-page values; contains no generated selection sets.
public struct ProjectCardResponse: Sendable {
  public let pid: Int
  public let imageURL: String?
  public let state: String
  public let name: String
  public let isLaunched: Bool
  public let isWatched: Bool
  public let prelaunchActivated: Bool
  public let isInPostCampaignPledgingPhase: Bool
  public let postCampaignPledgingEnabled: Bool
  public let launchedAt: String?
  public let deadlineAt: String?
  public let percentFunded: Int
  public let url: String
  public let goal: Money?
  public let pledged: Money?
  public let analytics: ProjectAnalyticsSnapshot
  public let details: ProjectCardResponse.Details

  public init(_ fragment: GraphAPI.ProjectCardFragment) {
    self.pid = fragment.pid
    self.imageURL = fragment.image?.url
    self.state = fragment.state.rawValue
    self.name = fragment.name
    self.isLaunched = fragment.isLaunched
    self.isWatched = fragment.isWatched
    self.prelaunchActivated = fragment.prelaunchActivated
    self.isInPostCampaignPledgingPhase = fragment.isInPostCampaignPledgingPhase
    self.postCampaignPledgingEnabled = fragment.postCampaignPledgingEnabled
    self.launchedAt = fragment.launchedAt
    self.deadlineAt = fragment.deadlineAt
    self.percentFunded = fragment.percentFunded
    self.url = fragment.url
    self.goal = fragment.goal.flatMap { Money($0.fragments.moneyFragment) }
    self.pledged = Money(fragment.pledged.fragments.moneyFragment)
    self.analytics = ProjectAnalyticsSnapshot(fragment.fragments.projectAnalyticsFragment)
    self.details = Details(fragment.fragments.projectPamphletMainCellPropertiesFragment)
  }

  public struct Details: Sendable {
    public let pid: Int
    public let name: String
    public let projectDescription: String
    public let creatorName: String
    public let creatorAvatarURL: String
    public let creatorId: Int
    public let isCreatorBlocked: Bool
    public let state: String
    public let stateChangedAt: String
    public let photo: String
    public let isBacking: Bool
    public let backersCount: Int
    public let categoryName: String
    public let locationName: String
    public let deadlineAt: String?
    public let fxRate: Double
    public let projectUsdExchangeRate: Double
    public let goalAmount: String?
    public let goalCurrency: String
    public let goalSymbol: String
    public let pledgedAmount: String?
    public let pledgedCurrency: String
    public let pledgedSymbol: String
    public let currency: String
    public let country: String
    public let videoHigh: String?
    public let videoHLS: String?
    public let url: String

    public init(_ fragment: GraphAPI.ProjectPamphletMainCellPropertiesFragment) {
      self.pid = fragment.pid
      self.name = fragment.name
      self.projectDescription = fragment.projectDescription
      self.creatorName = fragment.creator?.name ?? ""
      self.creatorAvatarURL = fragment.creator?.imageUrl ?? ""
      self.creatorId = (fragment.creator?.id).flatMap(Int.init) ?? 0
      self.isCreatorBlocked = fragment.creator?.isBlocked ?? false
      self.state = fragment.state.rawValue
      self.stateChangedAt = fragment.stateChangedAt
      self.photo = fragment.image?.url ?? ""
      self.isBacking = fragment.backing != nil
      self.backersCount = fragment.backersCount
      self.categoryName = fragment.category?.name ?? ""
      self.locationName = fragment.location?.displayableName ?? ""
      self.deadlineAt = fragment.deadlineAt
      self.fxRate = fragment.fxRate
      self.projectUsdExchangeRate = fragment.projectUsdExchangeRate
      self.goalAmount = fragment.goal?.fragments.moneyFragment.amount
      self.goalCurrency = fragment.goal?.fragments.moneyFragment.currency?.rawValue ?? ""
      self.goalSymbol = fragment.goal?.fragments.moneyFragment.symbol ?? ""
      self.pledgedAmount = fragment.pledged.fragments.moneyFragment.amount
      self.pledgedCurrency = fragment.pledged.fragments.moneyFragment.currency?.rawValue ?? ""
      self.pledgedSymbol = fragment.pledged.fragments.moneyFragment.symbol ?? ""
      self.currency = fragment.currency.rawValue
      self.country = fragment.country.code.rawValue
      self.videoHigh = fragment.video?.videoSources?.high?.src
      self.videoHLS = fragment.video?.videoSources?.hls?.src
      self.url = fragment.url
    }
  }
}
