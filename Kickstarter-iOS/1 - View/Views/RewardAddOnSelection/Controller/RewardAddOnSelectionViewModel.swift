import Experimentation
import Foundation
import KsApi
import Prelude

public typealias SelectedRewardId = Int
public typealias SelectedRewardQuantity = Int
public typealias SelectedRewardQuantities = [SelectedRewardId: SelectedRewardQuantity]

public enum RewardAddOnSelectionDataSourceItem: Equatable {
  case rewardAddOn(RewardAddOnCardViewData)
  case emptyState(EmptyStateViewType)

  public var rewardAddOnCardViewData: RewardAddOnCardViewData? {
    switch self {
    case .rewardAddOn(let data): return data
    case .emptyState: return nil
    }
  }

  public var emptyStateViewType: EmptyStateViewType? {
    switch self {
    case .rewardAddOn: return nil
    case .emptyState(let viewType): return viewType
    }
  }
}

@MainActor
public protocol RewardAddOnSelectionViewModelInputs {
  func beginRefresh()
  func configure(with data: PledgeViewData)
  func continueButtonTapped()
  func pledgeAmountViewControllerDidUpdate(with data: PledgeAmountData)
  func rewardAddOnCardViewDidSelectQuantity(quantity: Int, rewardId: Int)
  func viewDidLoad()
}

@MainActor
public protocol RewardAddOnSelectionViewModelOutputs: AnyObject {
  var onConfigureContinue: ((RewardAddOnSelectionContinueCTAViewData) -> Void)? { get set }
  var onConfigureAmount: ((PledgeAmountViewConfigData) -> Void)? { get set }
  var onEndRefreshing: (() -> Void)? { get set }
  var onGoToPledge: ((PledgeViewData) -> Void)? { get set }
  var onHeaderTitle: ((String) -> Void)? { get set }
  var onPageTitle: ((String) -> Void)? { get set }
  var onLoadRewards: (([RewardAddOnSelectionDataSourceItem]) -> Void)? { get set }
  var onLoadAndReloadRewards: (([RewardAddOnSelectionDataSourceItem]) -> Void)? { get set }
  var onStartRefreshing: (() -> Void)? { get set }
}

@MainActor
public protocol RewardAddOnSelectionViewModelType {
  var inputs: RewardAddOnSelectionViewModelInputs { get }
  var outputs: RewardAddOnSelectionViewModelOutputs { get }
}

@MainActor
public final class RewardAddOnSelectionViewModel: RewardAddOnSelectionViewModelType,
  RewardAddOnSelectionViewModelInputs,
  RewardAddOnSelectionViewModelOutputs
{
  private let feature: RewardsFeature
  private var pendingConfiguration: PledgeViewData?
  private var isLoaded = false
  private let addOnsRoute = UUID()
  private var addOnsTask: Task<Void, Never>?
  private var changedQuantities: SelectedRewardQuantities = [:]
  private var displayedChanges: SelectedRewardQuantities?
  private var backedQuantities: SelectedRewardQuantities?
  private var baseQuantities: SelectedRewardQuantities?
  private var latestCardData: ([Reward], Project, Reward, PledgeViewContext, ShippingRule?)?
  private var latestCardQuantities: SelectedRewardQuantities?
  private var currentBaseReward: Reward?
  private var currentAddOnRewards: [Reward]?
  private var currentRewardQuantities: SelectedRewardQuantities?
  private var totalRewards: [Reward]?
  private var totalQuantities: SelectedRewardQuantities?
  private var totalBonus: Double?
  private var analyticsTotal: Double?
  private var initialTrackingProject: Project?
  private var initialTrackingReward: Reward?
  private var initialTrackingRewards: [Reward]?
  private var initialTrackingConfiguration: PledgeViewData?
  private var initialTrackingBonus: Double?
  private var initialTrackingTotal: Double?
  private var trackedPage = false
  private var ctaCount: Int?
  private var ctaValid: Bool?
  private var ctaHasAddOns: Bool?
  private var ctaTotal: NSAttributedString?
  private var currencyProject: Project?
  private var currencyTotal: Double?
  private var hasCTATotal = false
  private var sentInitialCTA = false
  private var checkoutConfiguration: PledgeViewData?
  private var checkoutRewards: [Reward]?
  private var checkoutBonus: Double?
  private var checkoutShipping: ShippingRule?
  private var hasCheckoutShipping = false
  private var checkoutQuantities: SelectedRewardQuantities?
  private var checkoutLocationID: Int?
  private var hasCheckoutLocation = false
  private var validationProject: Project?
  private var validationInitialBonus: Double?
  private var validationAmount: PledgeAmountData?
  private var validationQuantities: SelectedRewardQuantities?
  private var validationShipping: ShippingRule?
  private var hasValidationShipping = false
  private var addOnsRequestID: UUID?
  deinit {
    self.addOnsTask?.cancel()
    let feature = self.feature
    let route = self.addOnsRoute
    Task { @MainActor in feature.releaseAddOns(route: route) }
  }
  public init(feature: RewardsFeature = AppModel.shared.rewardsFeature) {
    self.feature = feature
  }

  private func applyConfiguration(_ data: PledgeViewData) {
    let project = data.project
    if !self.trackedPage {
      if self.initialTrackingProject == nil { self.initialTrackingProject = project }
      self.trackPageIfReady()
    }
    self.validationProject = project
    self.publishValidity()
    self.publishAmountConfiguration()
    let initialBonus = project.personalization.backing?.bonusAmount ?? 0
    self.validationInitialBonus = initialBonus
    self.publishValidity()
    self.publishAmountConfiguration()
    self.receiveBonus(initialBonus)
    if let amount = project.personalization.backing?.amount { self.receivePledgeTotal(amount) }
    self.currencyProject = project
    self.publishCurrencyTotal()
    self.backedQuantities = project.personalization.backing.map(selectedRewardQuantities(in:)) ?? [:]
    self.publishSelectedQuantities()

    if let reward = data.rewards.first {
      if !self.trackedPage, self.initialTrackingReward == nil { self.initialTrackingReward = reward }
      self.trackPageIfReady()
      self.currentBaseReward = reward
      self.publishRewardSelection()
      self.publishAmountConfiguration()
      if !reward.hasAddOns {
        self.currentAddOnRewards = []
        self.publishRewardSelection()
      }
      self.onHeaderTitle?(reward.hasAddOns ? Strings.Customize_your_reward_with_optional_addons() : Strings.Customize_your_reward())
      self.onPageTitle?(reward.hasAddOns ? Strings.Pledge_flow_navigation_bar_titles_Addons() : Strings.Pledge_flow_navigation_bar_titles_Bonus_support())
      self.ctaHasAddOns = reward.hasAddOns
      self.publishInitialCTA()
    }
    self.receiveLatestQuantities(data.selectedQuantities)
    self.baseQuantities = data.selectedQuantities
    self.publishSelectedQuantities()
    self.checkoutLocationID = data.selectedLocationId
    self.hasCheckoutLocation = true
    self.receiveShipping(data.selectedShippingRule)
    if let reward = data.rewards.first, !reward.shipping.enabled { self.receiveShipping(nil) }
    if !self.trackedPage, self.initialTrackingConfiguration == nil { self.initialTrackingConfiguration = data }
    self.trackPageIfReady()
    self.checkoutConfiguration = data
    self.displayedChanges = [:]
    self.publishSelectedQuantities()
    self.loadAddOns(for: data)
  }

  private func receiveBonus(_ value: Double) {
    if !self.trackedPage, self.initialTrackingBonus == nil { self.initialTrackingBonus = value }
    self.trackPageIfReady()
    self.totalBonus = value
    self.publishPledgeTotal()
    self.checkoutBonus = value
  }

  private func receiveShipping(_ value: ShippingRule?) {
    self.validationShipping = value
    self.hasValidationShipping = true
    self.publishValidity()
    self.checkoutShipping = value
    self.hasCheckoutShipping = true
    self.checkoutLocationID = value?.location.id
    self.hasCheckoutLocation = true
  }

  private func trackPageIfReady() {
    guard !self.trackedPage, let project = self.initialTrackingProject,
          let reward = self.initialTrackingReward, let rewards = self.initialTrackingRewards,
          let config = self.initialTrackingConfiguration, let bonus = self.initialTrackingBonus,
          let total = self.initialTrackingTotal else { return }
    self.trackedPage = true
    let data = checkoutProperties(
      from: project, baseReward: reward, addOnRewards: rewards,
      selectedQuantities: config.selectedQuantities, additionalPledgeAmount: bonus,
      pledgeTotal: total, shippingTotal: 0, isApplePay: nil
    )
    AppEnvironment.current.ksrAnalytics.trackAddOnsPageViewed(
      project: project, reward: reward, checkoutData: data, refTag: config.refTag
    )
  }

  private func publishCurrencyTotal() {
    guard let project = self.currencyProject, let total = self.currencyTotal else { return }
    self.ctaTotal = attributedCurrency(withProject: project, total: total)
    self.hasCTATotal = true
    self.publishUpdatedCTA()
    self.publishInitialCTA()
  }

  private func publishInitialCTA() {
    guard !self.sentInitialCTA, self.hasCTATotal, let hasAddOns = self.ctaHasAddOns else { return }
    self.sentInitialCTA = true
    self.onConfigureContinue?((0, true, hasAddOns, self.ctaTotal))
  }

  private func publishUpdatedCTA() {
    guard self.hasCTATotal, let count = self.ctaCount, let valid = self.ctaValid else { return }
    self.onConfigureContinue?((count, valid, false, self.ctaTotal))
  }

  private func publishAmountConfiguration() {
    guard let project = self.validationProject, let reward = self.currentBaseReward,
          let initialBonus = self.validationInitialBonus else { return }
    self.onConfigureAmount?((project, reward, initialBonus))
  }

  private func publishValidity() {
    guard let project = self.validationProject, let initialBonus = self.validationInitialBonus,
          let amount = self.validationAmount, let quantities = self.validationQuantities,
          self.hasValidationShipping else { return }
    self.ctaValid = isValid(
      project: project, initialAdditionalPledgeAmount: initialBonus,
      pledgeAmountData: amount, latestSelectedQuantities: quantities,
      selectedShippingRule: self.validationShipping
    )
    self.publishUpdatedCTA()
  }

  private func receivePledgeTotal(_ value: Double) {
    if !self.trackedPage, self.initialTrackingTotal == nil {
      self.initialTrackingTotal = value
      self.trackPageIfReady()
    }
    self.analyticsTotal = value
    self.currencyTotal = value
    self.publishCurrencyTotal()
  }

  private func publishPledgeTotal() {
    guard let rewards = self.totalRewards, let quantities = self.totalQuantities,
          let bonus = self.totalBonus else { return }
    let rewardTotal = calculateAllRewardsTotal(addOnRewards: rewards, selectedQuantities: quantities)
    self.receivePledgeTotal(calculatePledgeTotal(
      pledgeAmount: bonus, shippingCost: 0, addOnRewardsTotal: rewardTotal
    ))
  }

  private func publishRewardSelection() {
    guard let base = self.currentBaseReward, let addOns = self.currentAddOnRewards,
          let quantities = self.currentRewardQuantities else { return }
    let ids = Set(addOns.map(\.id))
    let count = quantities.reduce(0) { total, entry in
      total + (entry.key != base.id && ids.contains(entry.key) ? entry.value : 0)
    }
    let selected = [base] + addOns.filter { (quantities[$0.id] ?? 0) > 0 }
    if !self.trackedPage, self.initialTrackingRewards == nil {
      self.initialTrackingRewards = selected
      self.trackPageIfReady()
    }
    self.totalRewards = selected
    self.publishPledgeTotal()
    self.checkoutRewards = selected
    self.ctaCount = count
    self.publishUpdatedCTA()
  }

  private func receiveCardItems(_ items: [RewardAddOnSelectionDataSourceItem]) {
    self.currentAddOnRewards = items.compactMap { $0.rewardAddOnCardViewData?.reward }
    self.publishRewardSelection()
  }

  private func publishCards(reload: Bool) {
    guard let data = self.latestCardData, let quantities = self.latestCardQuantities else { return }
    let items = rewardsData(
      addOns: data.0, project: data.1, baseReward: data.2,
      context: data.3, shippingRule: data.4, selectedQuantities: quantities
    )
    self.receiveCardItems(items)
    if reload { self.onLoadAndReloadRewards?(items) }
    else { self.onLoadRewards?(items) }
  }

  private func loadAddOns(for data: PledgeViewData) {
    self.addOnsTask?.cancel()
    let id = UUID()
    self.addOnsRequestID = id
    self.addOnsTask = self.feature.startAddOns(
      route: self.addOnsRoute, slug: data.project.slug,
      baseReward: data.rewards.first, shippingRule: data.selectedShippingRule
    ) { [weak self] result in
      guard let self, self.addOnsRequestID == id else { return }
      switch result {
      case let .success(rewards):
        if let rewards, let reward = data.rewards.first {
          self.latestCardData = (
            rewards, data.project, reward, data.context,
            reward.shipping.enabled ? data.selectedShippingRule : nil
          )
          self.publishCards(reload: true)
        }
      case .failure:
        let items: [RewardAddOnSelectionDataSourceItem] = [.emptyState(.errorPullToRefresh)]
        self.receiveCardItems(items)
        self.onLoadAndReloadRewards?(items)
      }
      self.onEndRefreshing?()
    }
  }

  // MARK: - Inputs

  public func beginRefresh() {
    self.onStartRefreshing?()
    if self.isLoaded, let data = self.pendingConfiguration { self.loadAddOns(for: data) }
  }

  public func configure(with data: PledgeViewData) {
    self.pendingConfiguration = data
    if self.isLoaded { self.applyConfiguration(data) }
  }

  public func continueButtonTapped() {
    if let config = self.checkoutConfiguration, let rewards = self.checkoutRewards,
       let bonus = self.checkoutBonus, let quantities = self.checkoutQuantities,
       self.hasCheckoutShipping, self.hasCheckoutLocation {
      self.onGoToPledge?(PledgeViewData(
        project: config.project, rewards: rewards, bonusSupport: bonus,
        selectedShippingRule: self.checkoutShipping, selectedQuantities: quantities,
        selectedLocationId: self.checkoutLocationID, refTag: config.refTag, context: config.context
      ))
    }
    self.trackContinue()
  }

  private func trackContinue() {
    guard let config = self.checkoutConfiguration, let reward = self.currentBaseReward,
          let rewards = self.checkoutRewards, let quantities = self.checkoutQuantities,
          let bonus = self.checkoutBonus, let total = self.analyticsTotal else { return }
    let data = checkoutProperties(
      from: config.project, baseReward: reward, addOnRewards: rewards,
      selectedQuantities: quantities, additionalPledgeAmount: bonus,
      pledgeTotal: total, shippingTotal: 0, isApplePay: nil
    )
    AppEnvironment.current.ksrAnalytics.trackAddOnsContinueButtonClicked(
      project: config.project, reward: reward, checkoutData: data, refTag: config.refTag
    )
  }

  public func pledgeAmountViewControllerDidUpdate(with data: PledgeAmountData) {
    self.receiveBonus(data.amount)
    self.validationAmount = data
    self.publishValidity()
  }

  public func viewDidLoad() {
    self.isLoaded = true
    if let data = self.pendingConfiguration { self.applyConfiguration(data) }
  }

  public func rewardAddOnCardViewDidSelectQuantity(
    quantity: SelectedRewardQuantity,
    rewardId: SelectedRewardId
  ) {
    self.changedQuantities[rewardId] = quantity
    self.displayedChanges = self.changedQuantities
    self.publishSelectedQuantities()
  }

  private func receiveLatestQuantities(_ quantities: SelectedRewardQuantities) {
    self.validationQuantities = quantities
    self.publishValidity()
    self.currentRewardQuantities = quantities
    self.publishRewardSelection()
    self.latestCardQuantities = quantities
    self.publishCards(reload: false)
  }

  private func publishSelectedQuantities() {
    guard let backed = self.backedQuantities, let changed = self.displayedChanges,
          let base = self.baseQuantities else { return }
    let quantities = backed.withAllValuesFrom(changed).withAllValuesFrom(base)
    self.receiveLatestQuantities(quantities)
    self.totalQuantities = quantities
    self.publishPledgeTotal()
    self.checkoutQuantities = quantities
  }

  // MARK: - Outputs

  public var onConfigureContinue: ((RewardAddOnSelectionContinueCTAViewData) -> Void)?
  public var onConfigureAmount: ((PledgeAmountViewConfigData) -> Void)?
  public var onEndRefreshing: (() -> Void)?
  public var onGoToPledge: ((PledgeViewData) -> Void)?
  public var onHeaderTitle: ((String) -> Void)?
  public var onPageTitle: ((String) -> Void)?
  public var onLoadRewards: (([RewardAddOnSelectionDataSourceItem]) -> Void)?
  public var onLoadAndReloadRewards: (([RewardAddOnSelectionDataSourceItem]) -> Void)?
  public var onStartRefreshing: (() -> Void)?

  public var inputs: RewardAddOnSelectionViewModelInputs { return self }
  public var outputs: RewardAddOnSelectionViewModelOutputs { return self }
}

// MARK: - Functions

private func rewardsData(
  addOns: [Reward],
  project: Project,
  baseReward: Reward,
  context: PledgeViewContext,
  shippingRule: ShippingRule?,
  selectedQuantities: SelectedRewardQuantities
) -> [RewardAddOnSelectionDataSourceItem] {
  let addOnsFilteredByExpandedShippingRule = RewardsFeature.availableAddOns(
    addOns, project: project, baseReward: baseReward, shippingRule: shippingRule)

  guard !addOnsFilteredByExpandedShippingRule.isEmpty else {
    return [.emptyState(.addOnsUnavailable)]
  }

  return
    addOnsFilteredByExpandedShippingRule
    .map { reward in
      RewardAddOnCardViewData(
        project: project,
        reward: reward,
        context: context == .pledge ? .pledge : .manage,
        shippingRule: reward.shipping.enabled
          ? reward.shippingRule(matching: shippingRule)
          : nil,
        selectedQuantities: selectedQuantities
      )
    }
    .map(RewardAddOnSelectionDataSourceItem.rewardAddOn)
}

private func isValid(
  project: Project,
  initialAdditionalPledgeAmount: Double,
  pledgeAmountData: PledgeAmountData,
  latestSelectedQuantities: SelectedRewardQuantities,
  selectedShippingRule: ShippingRule?
) -> Bool {
  if !pledgeAmountData.isValid { return false }

  guard let backing = project.personalization.backing else { return true }

  let addOnChanged =
    latestSelectedQuantities != selectedRewardQuantities(in: backing)
    || backing.locationId != selectedShippingRule?.location.id
  let bonusChanged = pledgeAmountData.amount != initialAdditionalPledgeAmount

  return addOnChanged || bonusChanged
}
