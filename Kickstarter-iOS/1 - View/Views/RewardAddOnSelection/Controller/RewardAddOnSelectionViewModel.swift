import Experimentation
import Foundation
import KsApi
import Prelude
import ReactiveSwift

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
  private let configEvents = Signal<PledgeViewData, Never>.pipe()
  private var pendingConfiguration: PledgeViewData?
  private var isLoaded = false
  private let addOnsRoute = UUID()
  private var addOnsTask: Task<Void, Never>?
  private let selectedQuantitiesEvents = Signal<SelectedRewardQuantities, Never>.pipe()
  private var changedQuantities: SelectedRewardQuantities = [:]
  private var displayedChanges: SelectedRewardQuantities?
  private var backedQuantities: SelectedRewardQuantities?
  private var baseQuantities: SelectedRewardQuantities?
  private let cardItems = Signal<[RewardAddOnSelectionDataSourceItem], Never>.pipe()
  private var latestCardData: ([Reward], Project, Reward, PledgeViewContext, ShippingRule?)?
  private var latestCardQuantities: SelectedRewardQuantities?
  private let selectedRewardsEvents = Signal<[Reward], Never>.pipe()
  private let selectedAddOnCountEvents = Signal<Int, Never>.pipe()
  private var currentBaseReward: Reward?
  private var currentAddOnRewards: [Reward]?
  private var currentRewardQuantities: SelectedRewardQuantities?
  private let pledgeTotalEvents = Signal<Double, Never>.pipe()
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
  private let validityEvents = Signal<Bool, Never>.pipe()
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
    let configData = self.configEvents.output

    let project = configData.map(\.project)
    let baseReward = configData.map(\.rewards).map(\.first).skipNil()
    let baseRewardQuantities = configData.map(\.selectedQuantities)
    let context = configData.map(\.context)
    let initialLocationId = configData.map(\.selectedLocationId)
    let selectedShippingRule = configData.map(\.selectedShippingRule)

    let hasAddOns = baseReward.map(\.hasAddOns)


    let headerTitle = hasAddOns.map { (hasAddons: Bool) -> String in
      hasAddons
        ? Strings.Customize_your_reward_with_optional_addons()
        : Strings.Customize_your_reward()
    }

    let pageTitle = hasAddOns.map { (hasAddOns: Bool) -> String in
      hasAddOns
        ? Strings.Pledge_flow_navigation_bar_titles_Addons()
        : Strings.Pledge_flow_navigation_bar_titles_Bonus_support()
    }

    let shippingRule = Signal.merge(
      selectedShippingRule,
      baseReward.filter { reward in !reward.shipping.enabled }.mapConst(nil)
    )

    let selectedQuantities = self.selectedQuantitiesEvents.output

    let latestSelectedQuantities = Signal.merge(
      baseRewardQuantities,
      selectedQuantities
    )

    let dataSourceItems = self.cardItems.output

    let allAddOnRewards = Signal.merge(
      // All add-ons from the data source.
      dataSourceItems.map { items in
        items.compactMap {
          item -> Reward? in item.rewardAddOnCardViewData?.reward
        }
      },
      // No add-ons (and data source is not initialized) if the reward doesn't have add-ons.
      hasAddOns.filter(isFalse).mapConst([])
    )

    // MARK: - Bonus support

    /// Initial pledge amount is zero if not backed.
    let initialAdditionalPledgeAmount = project.map {
      $0.personalization.backing?.bonusAmount ?? 0.0
    }

    /// Called when pledge or bonus is updated by backer
    let additionalPledgeAmount = Signal.merge(
      initialAdditionalPledgeAmount,
      self.pledgeAmountDataSignal.map { $0.amount }
    )

    let totalSelectedAddOnsQuantity = self.selectedAddOnCountEvents.output

    let enableContinueButton = self.validityEvents.output

    let selectedRewards = self.selectedRewardsEvents.output

    let selectedLocationId = Signal.merge(
      initialLocationId,
      shippingRule.map { $0?.location.id }
    )

    let pledgeTotal = self.pledgeTotalEvents.output

    _ = project.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingProject == nil { self.initialTrackingProject = value }
      self.trackPageIfReady()
    }
    _ = baseReward.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingReward == nil { self.initialTrackingReward = value }
      self.trackPageIfReady()
    }
    _ = selectedRewards.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingRewards == nil { self.initialTrackingRewards = value }
      self.trackPageIfReady()
    }
    _ = configData.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingConfiguration == nil { self.initialTrackingConfiguration = value }
      self.trackPageIfReady()
    }
    _ = additionalPledgeAmount.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingBonus == nil { self.initialTrackingBonus = value }
      self.trackPageIfReady()
    }
    _ = pledgeTotal.observeValues { [weak self] value in
      guard let self, !self.trackedPage else { return }
      if self.initialTrackingTotal == nil { self.initialTrackingTotal = value }
      self.trackPageIfReady()
    }

    _ = project.observeValues { [weak self] value in
      self?.validationProject = value
      self?.publishValidity()
      self?.publishAmountConfiguration()
    }
    _ = initialAdditionalPledgeAmount.observeValues { [weak self] value in
      self?.validationInitialBonus = value
      self?.publishValidity()
      self?.publishAmountConfiguration()
    }
    _ = self.pledgeAmountDataSignal.observeValues { [weak self] value in
      self?.validationAmount = value
      self?.publishValidity()
    }
    _ = latestSelectedQuantities.observeValues { [weak self] value in
      self?.validationQuantities = value
      self?.publishValidity()
    }
    _ = shippingRule.observeValues { [weak self] value in
      self?.validationShipping = value
      self?.hasValidationShipping = true
      self?.publishValidity()
    }
    _ = project.observeValues { [weak self] project in
      if let amount = project.personalization.backing?.amount {
        self?.pledgeTotalEvents.input.send(value: amount)
      }
    }
    _ = pledgeTotal.observeValues { [weak self] value in self?.analyticsTotal = value }
    _ = selectedRewards.observeValues { [weak self] rewards in
      self?.totalRewards = rewards
      self?.publishPledgeTotal()
    }
    _ = selectedQuantities.observeValues { [weak self] quantities in
      self?.totalQuantities = quantities
      self?.publishPledgeTotal()
    }
    _ = additionalPledgeAmount.observeValues { [weak self] amount in
      self?.totalBonus = amount
      self?.publishPledgeTotal()
    }
    _ = baseReward.observeValues { [weak self] reward in
      self?.currentBaseReward = reward
      self?.publishRewardSelection()
      self?.publishAmountConfiguration()
    }
    _ = allAddOnRewards.observeValues { [weak self] rewards in
      self?.currentAddOnRewards = rewards
      self?.publishRewardSelection()
    }
    _ = latestSelectedQuantities.observeValues { [weak self] quantities in
      self?.currentRewardQuantities = quantities
      self?.publishRewardSelection()
    }
    _ = headerTitle.observeValues { [weak self] value in self?.onHeaderTitle?(value) }
    _ = pageTitle.observeValues { [weak self] value in self?.onPageTitle?(value) }
    _ = latestSelectedQuantities.observeValues { [weak self] quantities in
      self?.latestCardQuantities = quantities
      self?.publishCards(reload: false)
    }
    _ = configData.observeValues { [weak self] in self?.checkoutConfiguration = $0 }
    _ = selectedRewards.observeValues { [weak self] in self?.checkoutRewards = $0 }
    _ = additionalPledgeAmount.observeValues { [weak self] in self?.checkoutBonus = $0 }
    _ = shippingRule.observeValues { [weak self] value in
      self?.checkoutShipping = value
      self?.hasCheckoutShipping = true
    }
    _ = selectedQuantities.observeValues { [weak self] in self?.checkoutQuantities = $0 }
    _ = selectedLocationId.observeValues { [weak self] value in
      self?.checkoutLocationID = value
      self?.hasCheckoutLocation = true
    }
    _ = totalSelectedAddOnsQuantity.observeValues { [weak self] value in
      self?.ctaCount = value
      self?.publishUpdatedCTA()
    }
    _ = enableContinueButton.observeValues { [weak self] value in
      self?.ctaValid = value
      self?.publishUpdatedCTA()
    }
    _ = hasAddOns.observeValues { [weak self] value in
      self?.ctaHasAddOns = value
      self?.publishInitialCTA()
    }
    _ = project.observeValues { [weak self] value in
      self?.currencyProject = value
      self?.publishCurrencyTotal()
    }
    _ = pledgeTotal.observeValues { [weak self] value in
      self?.currencyTotal = value
      self?.publishCurrencyTotal()
    }
    _ = project.observeValues { [weak self] project in
      self?.backedQuantities = project.personalization.backing.map(selectedRewardQuantities(in:)) ?? [:]
      self?.publishSelectedQuantities()
    }
    _ = baseRewardQuantities.observeValues { [weak self] quantities in
      self?.baseQuantities = quantities
      self?.publishSelectedQuantities()
    }
    _ = configData.observeValues { [weak self] _ in
      self?.displayedChanges = [:]
      self?.publishSelectedQuantities()
    }
    _ = configData.observeValues { [weak self] data in
      self?.loadAddOns(for: data)
    }
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
    self.validityEvents.input.send(value: isValid(
      project: project, initialAdditionalPledgeAmount: initialBonus,
      pledgeAmountData: amount, latestSelectedQuantities: quantities,
      selectedShippingRule: self.validationShipping
    ))
  }

  private func publishPledgeTotal() {
    guard let rewards = self.totalRewards, let quantities = self.totalQuantities,
          let bonus = self.totalBonus else { return }
    let rewardTotal = calculateAllRewardsTotal(addOnRewards: rewards, selectedQuantities: quantities)
    self.pledgeTotalEvents.input.send(value: calculatePledgeTotal(
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
    self.selectedRewardsEvents.input.send(value: selected)
    self.selectedAddOnCountEvents.input.send(value: count)
  }

  private func publishCards(reload: Bool) {
    guard let data = self.latestCardData, let quantities = self.latestCardQuantities else { return }
    let items = rewardsData(
      addOns: data.0, project: data.1, baseReward: data.2,
      context: data.3, shippingRule: data.4, selectedQuantities: quantities
    )
    self.cardItems.input.send(value: items)
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
        self.cardItems.input.send(value: items)
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
    if self.isLoaded { self.configEvents.input.send(value: data) }
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

  private let (pledgeAmountDataSignal, pledgeAmountObserver) = Signal<PledgeAmountData, Never>
    .pipe()
  public func pledgeAmountViewControllerDidUpdate(with data: PledgeAmountData) {
    self.pledgeAmountObserver.send(value: data)
  }

  public func viewDidLoad() {
    self.isLoaded = true
    if let data = self.pendingConfiguration { self.configEvents.input.send(value: data) }
  }

  public func rewardAddOnCardViewDidSelectQuantity(
    quantity: SelectedRewardQuantity,
    rewardId: SelectedRewardId
  ) {
    self.changedQuantities[rewardId] = quantity
    self.displayedChanges = self.changedQuantities
    self.publishSelectedQuantities()
  }

  private func publishSelectedQuantities() {
    guard let backed = self.backedQuantities, let changed = self.displayedChanges,
          let base = self.baseQuantities else { return }
    self.selectedQuantitiesEvents.input.send(value: backed.withAllValuesFrom(changed).withAllValuesFrom(base))
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
