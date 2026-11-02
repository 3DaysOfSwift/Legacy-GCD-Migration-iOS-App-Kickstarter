import Foundation

/// Immutable analytics values detached from generated transport objects.
public struct ProjectAnalyticsSnapshot: ProjectAnalyticsProperties, Sendable {
  public let categoryAnalyticsName: String?
  public let categoryParentAnalyticsName: String?
  public let categoryParentId: String?
  public let countryCode: String
  public let creatorId: String?
  public let creatorIsRepeatCreator: Bool?
  public let datesDeadline: TimeInterval?
  public let datesLaunchedAt: TimeInterval?
  public let id: Int
  public let hasAddOns: Bool
  public let hasVideo: Bool
  public let name: String
  public let isInPostCampaignPledgingPhase: Bool
  public let personalizationIsStarred: Bool?
  public let personalizationIsBacking: Bool?
  public let postCampaignPledgingEnabled: Bool
  public let prelaunchActivated: Bool?
  public let rewardsCount: Int
  public let stateValue: String
  public let statsBackerCount: Int
  public let statsCommentsCount: Int?
  public let statsCurrency: String
  public let statsPercentFunded: Int
  public let statsPledged: Int
  public let statsTotalAmountPledgedUsdCurrency: Float?
  public let statsGoalUsdCurrency: Float?
  public let statsUpdatesCount: Int?
  public let tags: [String]?

  public init(_ source: any ProjectAnalyticsProperties) {
    self.categoryAnalyticsName = source.categoryAnalyticsName
    self.categoryParentAnalyticsName = source.categoryParentAnalyticsName
    self.categoryParentId = source.categoryParentId
    self.countryCode = source.countryCode
    self.creatorId = source.creatorId
    self.creatorIsRepeatCreator = source.creatorIsRepeatCreator
    self.datesDeadline = source.datesDeadline
    self.datesLaunchedAt = source.datesLaunchedAt
    self.id = source.id
    self.hasAddOns = source.hasAddOns
    self.hasVideo = source.hasVideo
    self.name = source.name
    self.isInPostCampaignPledgingPhase = source.isInPostCampaignPledgingPhase
    self.personalizationIsStarred = source.personalizationIsStarred
    self.personalizationIsBacking = source.personalizationIsBacking
    self.postCampaignPledgingEnabled = source.postCampaignPledgingEnabled
    self.prelaunchActivated = source.prelaunchActivated
    self.rewardsCount = source.rewardsCount
    self.stateValue = source.stateValue
    self.statsBackerCount = source.statsBackerCount
    self.statsCommentsCount = source.statsCommentsCount
    self.statsCurrency = source.statsCurrency
    self.statsPercentFunded = source.statsPercentFunded
    self.statsPledged = source.statsPledged
    self.statsTotalAmountPledgedUsdCurrency = source.statsTotalAmountPledgedUsdCurrency
    self.statsGoalUsdCurrency = source.statsGoalUsdCurrency
    self.statsUpdatesCount = source.statsUpdatesCount
    self.tags = source.tags
  }
  public func datesDuration(using calendar: Calendar = .current) -> Int? {
    guard let deadlineDateValue = self.datesDeadline,
          let launchedAtDateValue = self.datesLaunchedAt else {
      return nil
    }

    let deadlineDate = Date(timeIntervalSince1970: deadlineDateValue)
    let launchedAtDate = Date(timeIntervalSince1970: launchedAtDateValue)

    return calendar.dateComponents([.day], from: launchedAtDate, to: deadlineDate).day
  }

  public func datesHoursRemaining(
    from date: Foundation.Date = Date(),
    using calendar: Foundation.Calendar = .current
  ) -> Int? {
    guard let deadlineDateValue = self.datesDeadline else {
      return nil
    }

    let deadlineDate = Date(timeIntervalSince1970: deadlineDateValue)

    guard let hoursRemaining = calendar.dateComponents([.hour], from: date, to: deadlineDate).hour else {
      return nil
    }

    return max(0, hoursRemaining)
  }

}
