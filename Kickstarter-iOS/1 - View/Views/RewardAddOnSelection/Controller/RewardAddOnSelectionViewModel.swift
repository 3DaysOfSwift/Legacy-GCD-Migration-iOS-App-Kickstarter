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
public protocol RewardAddOnSelectionViewModelOutputs {
  var configureContinueCTAViewWithData: Signal<RewardAddOnSelectionContinueCTAViewData, Never> {
    get
  }
  var configurePledgeAmountViewWithData: Signal<PledgeAmountViewConfigData, Never> { get }
  var endRefreshing: Signal<(), Never> { get }
  var goToPledge: Signal<PledgeViewData, Never> { get }
  var headerTitle: Signal<String, Never> { get }
  var pageTitle: Signal<String, Never> { get }
  var loadAddOnRewardsIntoDataSource: Signal<[RewardAddOnSelectionDataSourceItem], Never> { get }
  var loadAddOnRewardsIntoDataSourceAndReloadTableView:
    Signal<[RewardAddOnSelectionDataSourceItem], Never>
  { get }
  var startRefreshing: Signal<(), Never> { get }
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
  deinit {
    let feature = self.feature
    let route = self.addOnsRoute
    Task { @MainActor in feature.releaseAddOns(route: route) }
  }
  public init(feature: RewardsFeature = AppModel.shared.rewardsFeature) {
    self.feature = feature
    let route = self.addOnsRoute
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

    self.headerTitle = hasAddOns.map { (hasAddons: Bool) -> String in
      hasAddons
        ? Strings.Customize_your_reward_with_optional_addons()
        : Strings.Customize_your_reward()
    }

    self.pageTitle = hasAddOns.map { (hasAddOns: Bool) -> String in
      hasAddOns
        ? Strings.Pledge_flow_navigation_bar_titles_Addons()
        : Strings.Pledge_flow_navigation_bar_titles_Bonus_support()
    }

    let shippingRule = Signal.merge(
      selectedShippingRule,
      baseReward.filter { reward in !reward.shipping.enabled }.mapConst(nil)
    )

    let addOnsEvent = refreshAddons.switchMap { data in
      let slug = data.project.slug
      let baseReward = data.rewards.first
      let shippingRule = data.selectedShippingRule

      return feature.addOnsResult(
        route: route,
        slug: slug,
        baseReward: baseReward,
        shippingRule: shippingRule
      )
      .map { ($0, data) }
      .materialize()
    }

    self.startRefreshing = self.beginRefreshSignal
    self.endRefreshing = addOnsEvent.filter { $0.isTerminating }.ignoreValues()

    let requestErrored = addOnsEvent.map(\.error).map(isNotNil)

    // Quantities updated as the user selects them, merged with an empty initial value.
    let updatedSelectedQuantities = Signal.merge(
      self.rewardAddOnCardViewDidSelectQuantityProperty.signal
        .skipNil()
        .scan([:]) { current, new -> SelectedRewardQuantities in
          let (quantity, rewardId) = new
          var mutableCurrent = current
          mutableCurrent[rewardId] = quantity
          return mutableCurrent
        },
      configData.mapConst([:])
    )

    let backedQuantities = project.map { project -> SelectedRewardQuantities in
      guard let backing = project.personalization.backing else { return [:] }

      return selectedRewardQuantities(in: backing)
    }

    // Backed quantities overwritten by user-selected quantities.
    let selectedAddOnQuantities = Signal.combineLatest(
      updatedSelectedQuantities,
      backedQuantities
    )
    .map { updatedSelectedQuantities, backedQuantities in
      backedQuantities.withAllValuesFrom(updatedSelectedQuantities)
    }

    // User-selected and backed quantities combined with the base reward selection.
    let selectedQuantities = Signal.combineLatest(
      selectedAddOnQuantities,
      baseRewardQuantities
    )
    .map { selectedAddOnQuantities, baseRewardQuantities in
      selectedAddOnQuantities.withAllValuesFrom(baseRewardQuantities)
    }

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

    self.loadAddOnRewardsIntoDataSourceAndReloadTableView = Signal.merge(
      reloadRewardsIntoDataSource,
      requestErrored.filter(isTrue).mapConst([.emptyState(.errorPullToRefresh)])
    )

    self.loadAddOnRewardsIntoDataSource =
      rewardAddOnCardsViewData
      .takePairWhen(latestSelectedQuantities)
      .map(unpack)
      .map(rewardsData)

    let dataSourceItems = Signal.merge(
      self.loadAddOnRewardsIntoDataSourceAndReloadTableView,
      self.loadAddOnRewardsIntoDataSource
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

    self.configurePledgeAmountViewWithData = Signal.combineLatest(
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

    self.goToPledge = Signal.combineLatest(
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

    self.configureContinueCTAViewWithData = Signal.merge(
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

  private let rewardAddOnCardViewDidSelectQuantityProperty = MutableProperty<
    (SelectedRewardQuantity, SelectedRewardId)?
  >(nil)
  public func rewardAddOnCardViewDidSelectQuantity(
    quantity: SelectedRewardQuantity,
    rewardId: SelectedRewardId
  ) {
    self.rewardAddOnCardViewDidSelectQuantityProperty.value = (quantity, rewardId)
  }

  // MARK: - Outputs

  public let configureContinueCTAViewWithData:
    Signal<RewardAddOnSelectionContinueCTAViewData, Never>
  public let configurePledgeAmountViewWithData: Signal<PledgeAmountViewConfigData, Never>
  public let endRefreshing: Signal<(), Never>
  public let goToPledge: Signal<PledgeViewData, Never>
  public let headerTitle: Signal<String, Never>
  public let pageTitle: Signal<String, Never>
  public let loadAddOnRewardsIntoDataSource: Signal<[RewardAddOnSelectionDataSourceItem], Never>
  public let loadAddOnRewardsIntoDataSourceAndReloadTableView:
    Signal<[RewardAddOnSelectionDataSourceItem], Never>
  public let startRefreshing: Signal<(), Never>

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
