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
  private let addOnsRoute = UUID()
  private let addOnsEvents = Signal<Signal<([Reward]?, PledgeViewData), ErrorEnvelope>.Event, Never>.pipe()
  private var addOnsTask: Task<Void, Never>?
  private let selectedQuantitiesEvents = Signal<SelectedRewardQuantities, Never>.pipe()
  private var changedQuantities: SelectedRewardQuantities = [:]
  private var displayedChanges: SelectedRewardQuantities?
  private var backedQuantities: SelectedRewardQuantities?
  private var baseQuantities: SelectedRewardQuantities?
  private var addOnsRequestID: UUID?
  deinit {
    self.addOnsTask?.cancel()
    let feature = self.feature
    let route = self.addOnsRoute
    Task { @MainActor in feature.releaseAddOns(route: route) }
  }
  public init(feature: RewardsFeature = AppModel.shared.rewardsFeature) {
    self.feature = feature
    let configData = Signal.combineLatest(
      self.configureWithDataProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal
    )
    .map(first)

    let project = configData.map(\.project)
    let baseReward = configData.map(\.rewards).map(\.first).skipNil()
    let baseRewardQuantities = configData.map(\.selectedQuantities)
    let refTag = configData.map(\.refTag)
    let context = configData.map(\.context)
    let initialLocationId = configData.map(\.selectedLocationId)
    let selectedShippingRule = configData.map(\.selectedShippingRule)

    let hasAddOns = baseReward.map(\.hasAddOns)

    let refreshAddons = Signal.merge(
      configData,
      configData.takeWhen(self.beginRefreshSignal)
    )

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

    let addOnsEvent = self.addOnsEvents.output

    let startRefreshing = self.beginRefreshSignal
    let endRefreshing = addOnsEvent.filter { $0.isTerminating }.ignoreValues()

    let requestErrored = addOnsEvent.map(\.error).map(isNotNil)

    let selectedQuantities = self.selectedQuantitiesEvents.output

    let latestSelectedQuantities = Signal.merge(
      baseRewardQuantities,
      selectedQuantities
    )

    let rewardAddOnCardsViewData = addOnsEvent.values().compactMap {
      response
        -> ([Reward], Project, Reward, PledgeViewContext, ShippingRule?)? in
      let (addOns, data) = response
      guard let addOns, let reward = data.rewards.first else { return nil }
      return (
        addOns, data.project, reward, data.context,
        reward.shipping.enabled ? data.selectedShippingRule : nil
      )
    }

    let reloadRewardsIntoDataSource =
      rewardAddOnCardsViewData
      .withLatest(from: latestSelectedQuantities)
      .map(unpack)
      .map(rewardsData)

    let loadAddOnRewardsIntoDataSourceAndReloadTableView = Signal.merge(
      reloadRewardsIntoDataSource,
      requestErrored.filter(isTrue).mapConst([.emptyState(.errorPullToRefresh)])
    )

    let loadAddOnRewardsIntoDataSource =
      rewardAddOnCardsViewData
      .takePairWhen(latestSelectedQuantities)
      .map(unpack)
      .map(rewardsData)

    let dataSourceItems = Signal.merge(
      loadAddOnRewardsIntoDataSourceAndReloadTableView,
      loadAddOnRewardsIntoDataSource
    )

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

    let baseRewardAndAddOnRewards = Signal.combineLatest(
      baseReward,
      allAddOnRewards
    )

    // MARK: - Bonus support

    /// Initial pledge amount is zero if not backed.
    let initialAdditionalPledgeAmount = project.map {
      $0.personalization.backing?.bonusAmount ?? 0.0
    }

    let configurePledgeAmountViewWithData = Signal.combineLatest(
      project,
      baseReward,
      initialAdditionalPledgeAmount
    )
    .map { project, reward, initialPledgeAmount in
      (project, reward, initialPledgeAmount)
    }

    /// Called when pledge or bonus is updated by backer
    let additionalPledgeAmount = Signal.merge(
      initialAdditionalPledgeAmount,
      self.pledgeAmountDataSignal.map { $0.amount }
    )

    let totalSelectedAddOnsQuantity = Signal.combineLatest(
      latestSelectedQuantities,
      baseReward.map(\.id),
      allAddOnRewards.map { $0.map(\.id) }
    )
    .map { quantities, baseRewardId, addOnRewardIds in
      quantities
        // Filter out the base reward for determining the add-on quantities
        .filter { key, _ in key != baseRewardId && addOnRewardIds.contains(key) }
        .reduce(0) { accum, keyValue in
          let (_, value) = keyValue
          return accum + value
        }
    }

    let enableContinueButton = Signal.combineLatest(
      project,
      initialAdditionalPledgeAmount,
      self.pledgeAmountDataSignal,
      latestSelectedQuantities,
      shippingRule
    )
    .map(isValid)

    let selectedRewards =
      baseRewardAndAddOnRewards
      .combineLatest(with: latestSelectedQuantities)
      .map(unpack)
      .map { baseReward, addOnRewards, selectedQuantities -> [Reward] in
        let selectedRewardIds =
          selectedQuantities
          .filter { _, qty in qty > 0 }
          .keys

        return [baseReward]
          + addOnRewards
          .filter { reward in selectedRewardIds.contains(reward.id) }
      }

    let selectedLocationId = Signal.merge(
      initialLocationId,
      shippingRule.map { $0?.location.id }
    )

    let goToPledge = Signal.combineLatest(
      project,
      selectedRewards,
      additionalPledgeAmount,
      shippingRule,
      selectedQuantities,
      selectedLocationId,
      refTag,
      context
    )
    .map(PledgeViewData.init)
    .takeWhen(self.continueButtonTappedProperty.signal)

    let allRewardsTotal = Signal.combineLatest(
      selectedRewards,
      selectedQuantities
    )
    .map(calculateAllRewardsTotal)

    let combinedPledgeTotal = Signal.combineLatest(
      additionalPledgeAmount,
      additionalPledgeAmount.mapConst(0),
      allRewardsTotal
    )
    .map(calculatePledgeTotal)

    let pledgeTotal = Signal.merge(
      project.map { $0.personalization.backing }.skipNil().map(\.amount),
      combinedPledgeTotal
    )

    let attibutedPledgeTotal = Signal.combineLatest(project, pledgeTotal).map(attributedCurrency)

    let configureContinueCTAViewWithData = Signal.merge(
      // Updated values.
      Signal.combineLatest(totalSelectedAddOnsQuantity, enableContinueButton, attibutedPledgeTotal)
        .map { qty, isValid, total in (qty, isValid, false, total) },
      // Initial values. Note that button only loads if there are add-ons to fetch.
      Signal.combineLatest(hasAddOns, attibutedPledgeTotal)
        .map { hasAddOns, total in (0, true, hasAddOns, total) }
        .take(first: 1)
    )

    // MARK: - Tracking

    // shippingRule needs to be set for the event is fired
    Signal.zip(
      project,
      baseReward,
      selectedRewards,
      refTag,
      configData,
      additionalPledgeAmount,
      pledgeTotal
    )
    .take(first: 1)
    .observeForUI()
    .observeValues {
      project, baseReward, selectedRewards, refTag, configData, additionalPledgeAmount, pledgeTotal
      in
      let checkoutPropertiesData = checkoutProperties(
        from: project,
        baseReward: baseReward,
        addOnRewards: selectedRewards,
        selectedQuantities: configData.selectedQuantities,
        additionalPledgeAmount: additionalPledgeAmount,
        pledgeTotal: pledgeTotal,
        shippingTotal: 0,
        isApplePay: nil
      )

      AppEnvironment.current.ksrAnalytics.trackAddOnsPageViewed(
        project: project,
        reward: baseReward,
        checkoutData: checkoutPropertiesData,
        refTag: refTag
      )
    }

    // Send updated checkout data with add-ons continue event
    Signal.combineLatest(
      project,
      baseReward,
      selectedRewards,
      selectedQuantities,
      additionalPledgeAmount,
      pledgeTotal,
      refTag
    ).takeWhen(self.continueButtonTappedProperty.signal)
      .observeValues {
        project, baseReward, selectedRewards, selectedQuantities, additionalPledgeAmount,
        pledgeTotal, refTag in

        let checkoutData = checkoutProperties(
          from: project,
          baseReward: baseReward,
          addOnRewards: selectedRewards,
          selectedQuantities: selectedQuantities,
          additionalPledgeAmount: additionalPledgeAmount,
          pledgeTotal: pledgeTotal,
          shippingTotal: 0,
          isApplePay: nil
        )

        AppEnvironment.current.ksrAnalytics.trackAddOnsContinueButtonClicked(
          project: project,
          reward: baseReward,
          checkoutData: checkoutData,
          refTag: refTag
        )
      }

    _ = headerTitle.observeValues { [weak self] value in self?.onHeaderTitle?(value) }
    _ = pageTitle.observeValues { [weak self] value in self?.onPageTitle?(value) }
    _ = startRefreshing.observeValues { [weak self] _ in self?.onStartRefreshing?() }
    _ = endRefreshing.observeValues { [weak self] _ in self?.onEndRefreshing?() }
    _ = loadAddOnRewardsIntoDataSourceAndReloadTableView.observeValues { [weak self] value in self?.onLoadAndReloadRewards?(value) }
    _ = loadAddOnRewardsIntoDataSource.observeValues { [weak self] value in self?.onLoadRewards?(value) }
    _ = configurePledgeAmountViewWithData.observeValues { [weak self] value in self?.onConfigureAmount?(value) }
    _ = goToPledge.observeValues { [weak self] value in self?.onGoToPledge?(value) }
    _ = configureContinueCTAViewWithData.observeValues { [weak self] value in self?.onConfigureContinue?(value) }
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
    _ = refreshAddons.observeValues { [weak self] data in
      self?.loadAddOns(for: data)
    }
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
        self.addOnsEvents.input.send(value: .value((rewards, data)))
        self.addOnsEvents.input.send(value: .completed)
      case let .failure(error):
        self.addOnsEvents.input.send(value: .failed((error as? ErrorEnvelope) ?? .couldNotParseJSON))
      }
    }
  }

  // MARK: - Inputs

  private let (beginRefreshSignal, beginRefreshObserver) = Signal<Void, Never>.pipe()
  public func beginRefresh() {
    self.beginRefreshObserver.send(value: ())
  }

  private let configureWithDataProperty = MutableProperty<PledgeViewData?>(nil)
  public func configure(with data: PledgeViewData) {
    self.configureWithDataProperty.value = data
  }

  private let continueButtonTappedProperty = MutableProperty(())
  public func continueButtonTapped() {
    self.continueButtonTappedProperty.value = ()
  }

  private let (pledgeAmountDataSignal, pledgeAmountObserver) = Signal<PledgeAmountData, Never>
    .pipe()
  public func pledgeAmountViewControllerDidUpdate(with data: PledgeAmountData) {
    self.pledgeAmountObserver.send(value: data)
  }

  private let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
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

private func unpack(
  rewardsData: ([Reward], Project, Reward, PledgeViewContext, ShippingRule?),
  selectedQuantities: SelectedRewardQuantities
) -> ([Reward], Project, Reward, PledgeViewContext, ShippingRule?, SelectedRewardQuantities) {
  return (
    rewardsData.0, rewardsData.1, rewardsData.2, rewardsData.3, rewardsData.4, selectedQuantities
  )
}

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
