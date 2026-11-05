import KsApi
import Prelude
import UIKit

public enum RewardsCollectionViewContext {
  case createPledge
  case managePledge
}

@MainActor
final class RewardsCollectionViewModel {
  enum Event {
    case configureFooter(Int), flashScrollIndicators
    case goToAddOnSelection(PledgeViewData), goToCustomizeYourReward(PledgeViewData)
    case navigationBarShadowImageHidden(Bool), reloadData([RewardCardViewData])
    case showPlaceholderRewardCards(Int), footerHidden(Bool), scrollToReward(IndexPath)
    case showEditRewardConfirmationPrompt(String, String), title(String)
  }
  var onEvent: ((Event) -> Void)?
  private let rewardsFeature: RewardsFeature
  private let route = UUID()
  internal private(set) var loadingTask: Task<Void, Never>?
  private var loadingGeneration = UUID()
  private var configuration: (project: Project, refTag: RefTag?, context: RewardsCollectionViewContext, secret: String?)?
  private var didLoad = false
  private var hasLocation = false
  private var location: Location?
  private var displayedLocation: Location?
  private var displayedRewards: [Reward]?
  private var isLoading = true
  private var didLayout = false
  private var didScroll = false
  private var selected: Reward?
  private var pendingPledge: (PledgeViewData, Bool)?
  private var showDivider: Bool?

  init(rewardsFeature: RewardsFeature? = nil) {
    self.rewardsFeature = rewardsFeature ?? AppModel.shared.rewardsFeature
  }
  deinit {
    self.loadingTask?.cancel()
    let feature = self.rewardsFeature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }
  func configure(
    with project: Project, refTag: RefTag?, context: RewardsCollectionViewContext, secretRewardToken: String?
  ) {
    self.configuration = (project, refTag, context, secretRewardToken)
  }
  func viewDidLoad() {
    guard let config = self.configuration else { return }
    self.didLoad = true
    self.onEvent?(.title(titleForContext(config.context, project: config.project)))
    self.onEvent?(.showPlaceholderRewardCards(config.project.rewards.count))
    self.trackRewardsViewed(project: config.project, refTag: config.refTag)
    if self.hasLocation { self.startLoading() }
  }
  func shippingLocationSelected(_ location: Location?) {
    guard !self.hasLocation || self.location != location else { return }
    self.hasLocation = true
    self.location = location
    guard self.didLoad else { return }
    if !self.isLoading, let config = self.configuration {
      self.isLoading = true
      self.onEvent?(.showPlaceholderRewardCards(config.project.rewards.count))
    }
    self.startLoading()
  }
  func shippingLocationViewDidFailToLoad() {}
  private func startLoading() {
    guard let config = self.configuration else { return }
    let generation = UUID()
    self.loadingGeneration = generation
    let currentLocation = self.location
    let feature = self.rewardsFeature
    let request = feature.requestLoad(route: self.route, project: config.project, location: currentLocation)
    self.loadingTask = Task { [weak self] in
      await request.value
      guard let self, !Task.isCancelled, !request.isCancelled, self.loadingGeneration == generation else { return }
      let snapshot = feature.snapshot(for: self.route)
      if snapshot.hasResult {
        self.displayedRewards = snapshot.rewards
        self.displayedLocation = currentLocation
      }
      self.isLoading = false
      self.publishCards()
      self.scrollIfReady()
      self.loadingTask = nil
    }
  }
  private func publishCards() {
    guard let config = self.configuration, let rewards = self.displayedRewards else { return }
    let cards = rewards.map { reward in
      RewardCardViewData(
        project: config.project, reward: reward, context: .pledge,
        currentShippingLocation: self.displayedLocation
      )
    }
    self.onEvent?(.reloadData(cards))
    self.onEvent?(.configureFooter(cards.count))
  }
  func viewDidLayoutSubviews() { self.didLayout = true; self.scrollIfReady() }
  private func scrollIfReady() {
    guard self.didLayout, !self.didScroll, let config = self.configuration, let rewards = self.displayedRewards,
          let index = rewardToScrollIndexPath(config.project, rewards: rewards, secretRewardToken: config.secret) else { return }
    self.didScroll = true
    self.onEvent?(.scrollToReward(index))
  }
  func rewardSelected(with rewardId: Int) {
    guard let config = self.configuration,
          let reward = self.displayedRewards?.first(where: { $0.id == rewardId }),
          self.hasLocation else { return }
    self.selected = reward
    self.trackRewardClicked(reward, project: config.project, refTag: config.refTag)
    let rule = shippingRule(forReward: reward, selectedLocation: self.location)
    guard rewardsCarouselCanNavigateToReward(reward, in: config.project, selectedShippingLocation: rule?.location) else { return }
    let pledgeContext: PledgeViewContext = config.project.isInPostCampaignPledgingPhase ? .latePledge : .pledge
    let updateContext: PledgeViewContext = config.project.isPledgeOverTimeAllowed == true ? .editPledgeOverTime : .updateReward
    let data = PledgeViewData(
      project: config.project, rewards: [reward], bonusSupport: nil, selectedShippingRule: rule,
      selectedQuantities: [reward.id: 1], selectedLocationId: nil, refTag: config.refTag,
      context: config.project.personalization.backing == nil ? pledgeContext : updateContext
    )
    self.pendingPledge = (data, reward.hasAddOns)
    if shouldTriggerEditRewardPrompt(data) {
      self.onEvent?(.showEditRewardConfirmationPrompt(
        Strings.Continue_with_this_reward(), Strings.It_may_not_offer_some_or_all_of_your_add_ons()
      ))
    } else { self.navigate(data, hasAddOns: reward.hasAddOns) }
  }
  func confirmedEditReward() {
    guard let (data, hasAddOns) = self.pendingPledge else { return }
    self.navigate(data, hasAddOns: hasAddOns)
  }
  private func navigate(_ data: PledgeViewData, hasAddOns: Bool) {
    self.onEvent?(hasAddOns ? .goToAddOnSelection(data) : .goToCustomizeYourReward(data))
  }
  func selectedReward() -> Reward? { self.selected }
  func rewardCellShouldShowDividerLine(_ show: Bool) {
    self.showDivider = show
    self.onEvent?(.navigationBarShadowImageHidden(!show))
  }
  func viewWillAppear() {
    if let show = self.showDivider { self.onEvent?(.navigationBarShadowImageHidden(!show)) }
  }
  func traitCollectionDidChange(_ traitCollection: UITraitCollection) {
    self.onEvent?(.footerHidden(traitCollection.verticalSizeClass != .regular))
  }
  func viewDidAppear() {
    self.onEvent?(.flashScrollIndicators)
    guard let config = self.configuration, self.didLoad else { return }
    let project = config.project
    AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()
    guard let externalId = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier else { return }
    let userId = AppEnvironment.current.currentUser.map { "\($0.id)" } ?? ""
    var extInfo = Array(repeating: "", count: 16)
    extInfo[0] = "i2"
    extInfo[4] = AppEnvironment.current.mainBundle.platformVersion
    _ = AppEnvironment.current.apiService.triggerThirdPartyEventInput(
      input: .init(
        deviceId: externalId, eventName: ThirdPartyEventInputName.RewardSelectionViewed.rawValue,
        projectId: "\(project.id)", pledgeAmount: nil, shipping: nil, transactionId: nil, userId: userId,
        appData: .init(advertiserTrackingEnabled: true, applicationTrackingEnabled: true, extinfo: extInfo),
        clientMutationId: ""
      )
    )
  }
  private func trackRewardsViewed(project: Project, refTag: RefTag?) {
    let reward = Reward.noReward
    let (backing, shippingTotal) = backingAndShippingTotal(for: project, and: reward)
    let properties = checkoutProperties(
      from: project, baseReward: reward, addOnRewards: backing?.addOns ?? [], selectedQuantities: [:],
      additionalPledgeAmount: backing?.bonusAmount ?? 0, pledgeTotal: backing?.amount ?? reward.minimum,
      shippingTotal: shippingTotal ?? 0, isApplePay: nil
    )
    AppEnvironment.current.ksrAnalytics.trackRewardsViewed(project: project, checkoutPropertiesData: properties, refTag: refTag)
  }
  private func trackRewardClicked(_ reward: Reward, project: Project, refTag: RefTag?) {
    let (backing, shippingTotal) = backingAndShippingTotal(for: project, and: reward)
    let properties = checkoutProperties(
      from: project, baseReward: reward, addOnRewards: backing?.addOns ?? [], selectedQuantities: [reward.id: 1],
      additionalPledgeAmount: backing?.bonusAmount ?? 0, pledgeTotal: backing?.amount ?? reward.minimum,
      shippingTotal: shippingTotal ?? 0, isApplePay: nil
    )
    AppEnvironment.current.ksrAnalytics.trackRewardClicked(project: project, reward: reward, checkoutPropertiesData: properties, refTag: refTag)
  }
}

// MARK: - Functions

@MainActor
private func titleForContext(_ context: RewardsCollectionViewContext, project: Project) -> String {
  if currentUserIsCreator(of: project) {
    return Strings.View_your_rewards()
  }

  guard project.state == .live else {
    if project.isInPostCampaignPledgingPhase {
      return Strings.Back_this_project()
    }

    return Strings.View_rewards()
  }

  return context == .createPledge ? Strings.Pledge_flow_navigation_bar_titles_Rewards() : Strings
    .Edit_reward()
}

private func shouldTriggerEditRewardPrompt(_ data: PledgeViewData) -> Bool {
  // If the user is not backing the project then there is no need to show the prompt.
  guard
    userIsBackingProject(data.project),
    let backing = data.project.personalization.backing
  else { return false }

  let rewardChanged = data.rewards.first?.id != backing.reward?.id

  // We show the prompt if they have previously backed with add-ons and they are selecting a new reward.
  return backing.addOns?.isEmpty == false && rewardChanged
}

/// Returns the `IndexPath` of the reward to auto-scroll to in the collection view.
/// If a `secretRewardToken` is provided, it returns the first secret reward's index.
/// Otherwise, it returns the index of the backed reward (if the project is backed).
private func rewardToScrollIndexPath(
  _ project: Project,
  rewards: [Reward],
  secretRewardToken: String?
) -> IndexPath? {
  if let secretRewardToken = secretRewardToken, !secretRewardToken.isEmpty {
    return firstSecretRewardIndexPath(rewards: rewards)
  }

  return backedRewardIndexPath(project, rewards: rewards)
}

private func firstSecretRewardIndexPath(rewards: [Reward]) -> IndexPath? {
  return rewards.firstIndex(where: { $0.isSecretReward && $0.isAvailable == true })
    .flatMap { IndexPath(row: $0, section: 0) }
}

private func backedRewardIndexPath(_ project: Project, rewards: [Reward]) -> IndexPath? {
  guard let backing = project.personalization.backing else {
    return nil
  }

  let backedReward = reward(from: backing, inProject: project)
  return rewards
    .firstIndex(where: { $0.id == backedReward.id })
    .flatMap { IndexPath(row: $0, section: 0) }
}

private func backingAndShippingTotal(for project: Project, and reward: Reward) -> (Backing?, Double?) {
  let backing = project.personalization.backing
  let shippingTotal = reward.shipping.enabled ? backing?.shippingAmount.flatMap(Double.init) : 0.0

  return (backing, shippingTotal)
}

private func shippingRule(forReward reward: Reward, selectedLocation location: Location?) -> ShippingRule? {
  guard let selectedLocation = location else {
    return nil
  }

  // Whether or not this is a "shippable" reward.
  // "No Reward", digital rewards and local pickup rewards are not shippable.
  let hasShipping = reward.isRestrictedShippingPreference || reward.isUnRestrictedShippingPreference

  guard let rules = reward.shippingRulesExpanded else {
    assert(
      !hasShipping,
      "This reward is shippable, but no shipping rules were included on the reward. The backer may not be able to complete this pledge."
    )

    return nil
  }

  guard let rule = rules.first(where: { $0.location.id == selectedLocation.id }) else {
    assert(
      !hasShipping,
      "This reward is shippable, but no shipping rule matched the selected location. The backer may not be able to complete this pledge."
    )

    return nil
  }

  return rule
}
