import KDS
import KsApi
import Prelude
import UIKit

public typealias ProjectPamphletMainCellData = (
  project: any ProjectPamphletMainCellConfiguration,
  refTag: RefTag?
)

@MainActor
final class ProjectPamphletMainCellViewModel {
  enum Event {
    case backersSubtitleLabelText(String)
    case backersTitleLabelText(String)
    case categoryNameLabelText(String)
    case configureVideoPlayerController(any ProjectPamphletMainCellConfiguration)
    case conversionLabelHidden(Bool)
    case conversionLabelText(String)
    case creatorImageUrl(URL?)
    case creatorLabelText(String)
    case deadlineSubtitleLabelText(String)
    case deadlineTitleLabelText(String)
    case fundingProgressBarViewBackgroundColor(UIColor)
    case isPrelaunchProject(Bool)
    case locationNameLabelText(String)
    case locationStackViewHidden(Bool)
    case notifyDelegateToGoToCreator(any ProjectPamphletMainCellConfiguration)
    case notifyDelegateToGoToProjectNotice
    case opacityForViews(CGFloat)
    case pledgedSubtitleLabelText(String)
    case pledgedTitleLabelText(String)
    case pledgedTitleLabelTextColor(UIColor)
    case prelaunchProjectBackingText(String)
    case progressPercentage(Float)
    case projectBlurbLabelText(String)
    case projectImageUrl(URL?)
    case projectNameLabelText(String)
    case projectStateLabelText(String)
    case projectStateLabelTextColor(UIColor)
    case projectUnsuccessfulLabelTextColor(UIColor)
    case stateLabelHidden(Bool)
    case statsStackViewAccessibilityLabel(String)
    case backingLabelHidden(Bool)
    case projectNoticeBannerHidden(Bool)
  }
  var onEvent: ((Event) -> Void)?
  private var data: ProjectPamphletMainCellData?
  private var awake = false
  private var delegateReady = false
  private var videoConfigured = false
  private var videoInitialized = false
  private var videoPlaying = false
  private var lastBackingHidden: Bool?

  func awakeFromNib() {
    self.awake = true
    self.publishProject()
    self.onEvent?(.opacityForViews(0))
  }
  func configureWith(value: ProjectPamphletMainCellData) {
    self.data = value
    if self.awake { self.publishProject() }
    self.onEvent?(.opacityForViews(1))
  }
  func delegateDidSet() { self.delegateReady = true; self.configureVideoIfReady() }
  func creatorButtonTapped() {
    guard self.awake, let project = self.data?.project else { return }
    self.onEvent?(.notifyDelegateToGoToCreator(project))
    AppEnvironment.current.ksrAnalytics.trackGotoCreatorDetailsClicked(project: project)
  }
  func projectNoticeLearnMoreTapped() { self.onEvent?(.notifyDelegateToGoToProjectNotice) }
  func videoDidStart() { self.videoPlaying = true; self.publishBackingHidden() }
  func videoDidFinish() { self.videoPlaying = false; self.publishBackingHidden() }
  private func configureVideoIfReady() {
    guard self.awake, self.delegateReady, !self.videoConfigured, let project = self.data?.project else { return }
    self.videoConfigured = true
    self.onEvent?(.configureVideoPlayerController(project))
  }
  private func publishBackingHidden() {
    guard self.awake, self.videoInitialized, let properties = self.data?.project.projectPamphletMainCellProperties else { return }
    let hidden: Bool
    if let prelaunch = properties.displayPrelaunch {
      hidden = prelaunch ? false : properties.isBacking != true || self.videoPlaying
    } else { hidden = true }
    guard self.lastBackingHidden != hidden else { return }
    self.lastBackingHidden = hidden
    self.onEvent?(.backingLabelHidden(hidden))
  }
  private func publishProject() {
    guard self.awake, let project = self.data?.project else { return }
    let properties = project.projectPamphletMainCellProperties
    self.onEvent?(.projectNameLabelText(properties.name))
    self.onEvent?(.projectBlurbLabelText(properties.blurb))
    self.onEvent?(.creatorLabelText(Strings.project_creator_by_creator(creator_name: properties.creatorName)))
    self.onEvent?(.creatorImageUrl(URL(string: properties.creatorAvatarURL)))
    self.onEvent?(.stateLabelHidden(properties.state == .live))
    if properties.state != .live {
      self.onEvent?(.projectStateLabelText(fundingStatus(forProperties: properties)))
      self.onEvent?(.projectStateLabelTextColor(properties.state == .successful ? LegacyColors.ksr_create_700.uiColor() : LegacyColors.ksr_support_400.uiColor()))
    }
    self.onEvent?(.fundingProgressBarViewBackgroundColor(progressColor(forProperties: properties)))
    self.onEvent?(.projectUnsuccessfulLabelTextColor(LegacyColors.ksr_support_400.uiColor()))
    self.onEvent?(.pledgedTitleLabelTextColor(properties.state == .successful || properties.state == .live ? LegacyColors.ksr_create_700.uiColor() : LegacyColors.ksr_support_400.uiColor()))
    self.onEvent?(.prelaunchProjectBackingText(properties.displayPrelaunch == true ? Strings.Coming_soon() : Strings.Youre_a_backer()))
    self.onEvent?(.projectImageUrl(URL(string: properties.photo)))
    self.onEvent?(.projectNoticeBannerHidden((properties.projectNotice ?? "").isEmpty))
    if !self.videoInitialized { self.videoInitialized = true; self.videoPlaying = false }
    self.publishBackingHidden()
    let backers = Strings.Backers_count_separator_backers(backers_count: properties.backersCount).split(separator: "\n").map(String.init)
    self.onEvent?(.backersTitleLabelText(backers.first ?? ""))
    self.onEvent?(.backersSubtitleLabelText(backers.last ?? ""))
    self.onEvent?(.categoryNameLabelText(properties.categoryName ?? ""))
    var duration = ("", "")
    if let deadline = properties.deadline {
      let environment: Environment = AppEnvironment.current
      duration = Format.duration(from: environment.dateType.init().date,
        to: environment.dateType.init(timeIntervalSince1970: deadline).date,
        calendar: environment.calendar, useToGo: true)
    }
    self.onEvent?(.deadlineTitleLabelText(duration.0))
    self.onEvent?(.deadlineSubtitleLabelText(duration.1))
    let conversion = properties.needsConversion
    self.onEvent?(.conversionLabelHidden(!conversion))
    self.onEvent?(.locationNameLabelText(properties.locationName))
    self.onEvent?(.locationStackViewHidden(properties.locationName.isEmpty))
    self.onEvent?(.pledgedTitleLabelText(pledgedText(for: properties, conversion)))
    self.onEvent?(.pledgedSubtitleLabelText(goalText(for: properties, conversion)))
    if conversion { self.onEvent?(.conversionLabelText(conversionText(for: properties))) }
    self.onEvent?(.statsStackViewAccessibilityLabel(statsStackViewAccessibilityLabelForProperties(properties, needsConversion: conversion)))
    if let prelaunch = properties.displayPrelaunch { self.onEvent?(.isPrelaunchProject(prelaunch)) }
    self.onEvent?(.progressPercentage(clamp(0, 1)(properties.fundingProgress)))
    self.configureVideoIfReady()
  }
}

@MainActor
private func statsStackViewAccessibilityLabelForProperties(
  _ properties: ProjectPamphletMainCellProperties,
  needsConversion: Bool
) -> String {
  let projectCurrencyData = pledgeAmountAndGoalAndCountry(
    forProperties: properties,
    needsConversion: needsConversion
  )

  let pledged = Format.currency(
    projectCurrencyData.pledgedAmount,
    currencyCode: projectCurrencyData.currency,
    omitCurrencyCode: properties.omitUSCurrencyCode
  )
  let goal = Format.currency(
    projectCurrencyData.goalAmount,
    currencyCode: projectCurrencyData.currency,
    omitCurrencyCode: properties.omitUSCurrencyCode
  )

  let backersCount = properties.backersCount
  var (time, unit) = ("", "")

  if let deadline = properties.deadline {
    let environment: Environment = AppEnvironment.current
    (time, unit) = Format.duration(
      from: environment.dateType.init().date,
      to: environment.dateType.init(timeIntervalSince1970: deadline).date,
      calendar: environment.calendar, useToGo: true
    )
  }

  let timeLeft = time + " " + unit

  return properties.state == .live
    ? Strings.dashboard_graphs_funding_accessibility_live_stat_value(
      pledged: pledged, goal: goal, backers_count: backersCount, time_left: timeLeft
    )
    : Strings.dashboard_graphs_funding_accessibility_non_live_stat_value(
      pledged: pledged, goal: goal, backers_count: backersCount, time_left: timeLeft
    )
}

@MainActor
private func fundingStatus(forProperties properties: ProjectPamphletMainCellProperties) -> String {
  let date = Format.date(
    secondsInUTC: properties.stateChangedAt,
    dateStyle: .medium,
    timeStyle: .none
  )

  switch properties.state {
  case .canceled:
    return Strings.discovery_baseball_card_status_banner_canceled_date(date: date)
  case .failed:
    return Strings.creator_project_preview_subtitle_funding_unsuccessful_on_deadline(deadline: date)
  case .successful:
    return Strings.project_status_project_was_successfully_funded_on_deadline(deadline: date)
  case .suspended:
    return Strings.discovery_baseball_card_status_banner_suspended_date(date: date)
  case .live, .purged, .started, .submitted:
    return ""
  }
}

typealias ConvertedCurrrencyProjectData = (pledgedAmount: Int, goalAmount: Int, currency: String)

private func pledgeAmountAndGoalAndCountry(
  forProperties properties: ProjectPamphletMainCellProperties,
  needsConversion: Bool
) -> ConvertedCurrrencyProjectData {
  guard needsConversion else {
    return (properties.pledged.amount, properties.goal.amount, properties.currency)
  }

  guard let goalCurrentCurrency = properties.goalCurrentCurrency,
        let pledgedCurrentCurrency = properties.convertedPledgedAmount,
        let userCurrency = properties.userCurrency else {
    return (Int(properties.pledgedUsd), Int(properties.goalUsd), Project.Country.us.currencyCode)
  }

  return (Int(pledgedCurrentCurrency), Int(goalCurrentCurrency), userCurrency)
}

@MainActor
private func goalText(for properties: ProjectPamphletMainCellProperties, _ needsConversion: Bool) -> String {
  let projectCurrencyData = pledgeAmountAndGoalAndCountry(
    forProperties: properties,
    needsConversion: needsConversion
  )

  return Strings.activity_project_state_change_pledged_of_goal(
    goal: Format.currency(
      projectCurrencyData.goalAmount,
      currencyCode: projectCurrencyData.currency,
      omitCurrencyCode: properties.omitUSCurrencyCode
    )
  )
}

@MainActor
private func pledgedText(
  for properties: ProjectPamphletMainCellProperties,
  _ needsConversion: Bool
) -> String {
  let projectCurrencyData = pledgeAmountAndGoalAndCountry(
    forProperties: properties,
    needsConversion: needsConversion
  )

  return Format.currency(
    projectCurrencyData.pledgedAmount,
    currencyCode: projectCurrencyData.currency,
    omitCurrencyCode: properties.omitUSCurrencyCode
  )
}

@MainActor
private func conversionText(for properties: ProjectPamphletMainCellProperties) -> String {
  return Strings.discovery_baseball_card_stats_convert_from_pledged_of_goal(
    pledged: Format.currency(
      properties.pledged.amount,
      currencyCode: properties.currency,
      omitCurrencyCode: properties.omitUSCurrencyCode
    ),
    goal: Format.currency(
      properties.goal.amount,
      currencyCode: properties.currency,
      omitCurrencyCode: properties.omitUSCurrencyCode
    )
  )
}

private func progressColor(forProperties properties: ProjectPamphletMainCellProperties) -> UIColor {
  switch properties.state {
  case .canceled, .failed, .suspended:
    return LegacyColors.ksr_support_400.uiColor()
  default:
    return LegacyColors.ksr_create_700.uiColor()
  }
}
