import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

public typealias ManagePledgeViewParamConfigData = (
  projectParam: Param,
  backingParam: Param?
)

public enum ManagePledgeAlertAction: CaseIterable {
  case editPledgeOverTimePledge
  case changePaymentMethod
  case chooseAnotherReward
  case contactCreator
  case cancelPledge
  case viewRewards
}

@MainActor
public protocol ManagePledgeViewModelInputs {
  func beginRefresh()
  func configureWith(_ params: ManagePledgeViewParamConfigData)
  func cancelPledgeDidFinish(with message: String)
  func fixButtonTapped()
  func menuButtonTapped()
  func menuOptionSelected(with action: ManagePledgeAlertAction)
  func pledgeViewControllerDidUpdatePledgeWithMessage(_ message: String)
  func viewDidLoad()
  func termsOfUseTapped(with helpType: HelpType)
}

@MainActor
public protocol ManagePledgeViewModelOutputs: AnyObject {
  var onPaymentMethod: ((ManagePledgePaymentMethodViewData) -> Void)? { get set }
  var onPledgeSummary: ((ManagePledgeSummaryViewData) -> Void)? { get set }
  var onEndRefreshing: (() -> Void)? { get set }
  var onCancelPledge: ((CancelPledgeViewData) -> Void)? { get set }
  var onChangePaymentMethod: ((PledgeViewData) -> Void)? { get set }
  var onContactCreator: ((MessageSubject, KSRAnalytics.MessageDialogContext) -> Void)? { get set }
  var onFixPaymentMethod: ((PledgeViewData) -> Void)? { get set }
  var onRewards: ((Project) -> Void)? { get set }
  var onEditPledgeOverTime: ((Project) -> Void)? { get set }
  var onLoadProjectAndRewards: ((Project, [Reward]) -> Void)? { get set }
  var onLoadRefreshHeader: (() -> Void)? { get set }
  var onFinish: ((String?) -> Void)? { get set }
  var onPaymentMethodHidden: ((Bool) -> Void)? { get set }
  var onPledgeDetailsLabel: ((String) -> Void)? { get set }
  var onRightBarButtonHidden: ((Bool) -> Void)? { get set }
  var onShowMenu: (([ManagePledgeAlertAction]) -> Void)? { get set }
  var onShowError: ((String) -> Void)? { get set }
  var onShowSuccess: ((String) -> Void)? { get set }
  var onShowHelp: ((HelpType) -> Void)? { get set }
  var onStartRefreshing: (() -> Void)? { get set }
  var onTitle: ((String) -> Void)? { get set }
  var onPlotSchedule: (([PledgePaymentIncrement]) -> Void)? { get set }
  var onPlotScheduleHidden: ((Bool) -> Void)? { get set }
}

@MainActor
public protocol ManagePledgeViewModelType {
  var inputs: ManagePledgeViewModelInputs { get }
  var outputs: ManagePledgeViewModelOutputs { get }
}

@MainActor
private final class ManagePledgeTrackingState {
  private var projects: [(Project, [Reward])] = []
  private var backings: [Backing] = []

  func addProject(_ project: Project, rewards: [Reward]) {
    projects.append((project, rewards))
    trackAvailablePairs()
  }

  func addBacking(_ backing: Backing) {
    backings.append(backing)
    trackAvailablePairs()
  }

  private func trackAvailablePairs() {
    while !projects.isEmpty && !backings.isEmpty {
      let (project, rewards) = projects.removeFirst()
      let backing = backings.removeFirst()
      guard let reward = backing.reward else { continue }
      let checkoutData = checkoutProperties(
        from: project, baseReward: reward, addOnRewards: rewards,
        selectedQuantities: selectedRewardQuantities(in: backing), additionalPledgeAmount: backing.bonusAmount,
        pledgeTotal: backing.amount, shippingTotal: Double(backing.shippingAmount ?? 0),
        isApplePay: backing.paymentSource?.paymentType == .applePay
      )
      AppEnvironment.current.ksrAnalytics.trackManagePledgePageViewed(
        project: project, reward: reward, checkoutData: checkoutData
      )
    }
  }
}

@MainActor
private final class ManagePledgeReadIdentity {
  var id: UUID?
}

@MainActor
public final class ManagePledgeViewModel:
  ManagePledgeViewModelType, ManagePledgeViewModelInputs, ManagePledgeViewModelOutputs {
  private let feature: PledgeFeature
  private var projectHasLoaded = false
  private var configuredParams: ManagePledgeViewParamConfigData?
  private var hasLoadedView = false
  private var configuredBackingWasProvided = false
  private var currentBackingParam: Param?
  private var rightBarHidden: Bool?
  private var paymentMethodHidden: Bool?
  private var visibilityBacking: Backing?
  private var visibilityIsCreator: Bool?
  private var backingHasLoaded = false
  private var currentProject: Project?
  private var titleProject: Project?
  private var titleIsCreator: Bool?
  private var currentRewards: [Reward]?
  private var hasSeenDisallowedCancellation = false
  private let projectRoute = UUID()
  private let projectReadEvents = Signal<(Signal<Project, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private var projectReadTask: Task<Void, Never>?
  private let projectReadIdentity = ManagePledgeReadIdentity()
  private let backingRoute = UUID()
  private let backingReadEvents = Signal<(Signal<Backing, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private var backingReadTask: Task<Void, Never>?
  private let backingReadIdentity = ManagePledgeReadIdentity()
  deinit {
    self.backingReadTask?.cancel()
    self.projectReadTask?.cancel()
    let feature = self.feature, projectRoute = self.projectRoute, backingRoute = self.backingRoute
    Task { @MainActor in
      feature.releaseRead(route: projectRoute)
      feature.releaseRead(route: backingRoute)
    }
  }
  public init(feature: PledgeFeature = AppModel.shared.pledgeFeature) {
    self.feature = feature
    let projectReadIdentity = self.projectReadIdentity
    let backingReadIdentity = self.backingReadIdentity
    let fetchProjectEvent = self.projectReadEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [projectReadIdentity, feature] _, userID, generation, id in
        projectReadIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let initialProject = fetchProjectEvent.values()
      .on(value: { [weak self] project in
        guard let self else { return }
        self.projectHasLoaded = true
        if !self.configuredBackingWasProvided, let id = project.personalization.backing?.id {
          self.currentBackingParam = .id(id)
          self.loadBacking(id)
        }
      })

    let graphBackingEvent = self.backingReadEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [backingReadIdentity, feature] _, userID, generation, id in
        backingReadIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let backing = graphBackingEvent.values()

    let endRefreshingWhenProjectFailed = fetchProjectEvent.errors()
      .ignoreValues()

    let endRefreshingWhenBackingCompleted = graphBackingEvent
      .filter { $0.isTerminating }
      .ksr_delay(.milliseconds(300), on: AppEnvironment.current.scheduler)
      .ignoreValues()

    let endRefreshing = Signal.merge(
      endRefreshingWhenProjectFailed,
      endRefreshingWhenBackingCompleted
    )
    .ignoreValues()

    let project: Signal<Project, Never> = initialProject.combineLatest(with: backing)
      .map { project, backing -> Project in
        /**
         Here we are updating the `Project`'s `Backing` with an updated one from GraphQL.
         This is because, at the time of writing, v1 does not return add-ons or bonus amount but GraphQL does.
         */
        let p = (project |> Project.lens.personalization.backing .~ backing)
        return p
      }

    let userIsCreatorOfProject = project.map { project in
      currentUserIsCreator(of: project)
    }

    let projectAndReward = Signal.combineLatest(project, backing)
      .compactMap { project, backing -> (Project, Reward)? in
        guard let reward = backing.reward else { return (project, .noReward) }

        return (project, reward)
      }

    let loadProjectAndRewardsIntoDataSource = projectAndReward.combineLatest(with: backing)
      .map(unpack)
      .map { project, reward, backing -> (Project, [Reward]) in
        (project, distinctRewards([reward] + (backing.addOns ?? [])))
      }

    // Pair loaded project data with backing events for analytics in arrival order.
    let trackingState = ManagePledgeTrackingState()
    loadProjectAndRewardsIntoDataSource.observeValues { trackingState.addProject($0, rewards: $1) }
    backing.observeValues { trackingState.addBacking($0) }

    _ = endRefreshing.observeValues { [weak self] _ in self?.onEndRefreshing?() }
    _ = loadProjectAndRewardsIntoDataSource.observeValues { [weak self] first, second in
      self?.currentRewards = second
      self?.onLoadProjectAndRewards?(first, second)
      self?.setRightBarHidden(false)
    }
    _ = project.observeValues { [weak self] value in self?.currentProject = value }
    _ = backing.observeValues { [weak self] value in
      guard let self else { return }
      if !value.cancelable { self.hasSeenDisallowedCancellation = true }
      if self.backingHasLoaded { self.onFinish?(nil) }
      self.backingHasLoaded = true
    }
    _ = fetchProjectEvent.errors().observeValues { [weak self] _ in self?.handleLoadError() }
    _ = graphBackingEvent.errors().observeValues { [weak self] _ in self?.handleLoadError() }
    _ = project.observeValues { [weak self] value in
      self?.titleProject = value
      self?.updateTitle()
    }
    _ = userIsCreatorOfProject.observeValues { [weak self] value in
      self?.titleIsCreator = value
      self?.updateTitle()
    }
    _ = backing.observeValues { [weak self] backing in
      self?.onPaymentMethod?(managePledgePaymentMethodViewData(with: backing))
    }
    project.combineLatest(with: backing).observeValues { [weak self] project, backing in
      let rewards = distinctRewards([backing.reward ?? .noReward] + (backing.addOns ?? []))
      let isCreator = currentUserIsCreator(of: project)
      let latestDelivery = rewards.compactMap(\.estimatedDeliveryOn).reduce(0, max)
      let estimatedShipping = backing.locationId.flatMap { locationID in
        estimatedShippingText(for: rewards, project: project, locationId: locationID,
                              selectedQuantities: selectedRewardQuantities(in: backing))
      }.map { Strings.About_reward_amount(reward_amount: $0) }
      let received = ManageViewPledgeRewardReceivedViewData(
        project: project, backerCompleted: backing.backerCompleted ?? false,
        estimatedDeliveryOn: latestDelivery, backingState: backing.status,
        estimatedShipping: estimatedShipping,
        pledgeDisclaimerViewHidden: rewards.allSatisfy { $0.estimatedDeliveryOn == nil } || isCreator
      )
      if let data = managePledgeSummaryViewData(
        with: (project, backing.reward ?? .noReward), backing: backing,
        rewardReceivedWithData: received, rewardReceivedViewControllerViewIsHidden: latestDelivery == 0
      ) { self?.onPledgeSummary?(data) }
    }
    _ = backing.observeValues { [weak self] backing in
      self?.visibilityBacking = backing
      self?.updatePaymentMethodVisibility()
    }
    _ = userIsCreatorOfProject.observeValues { [weak self] isCreator in
      self?.visibilityIsCreator = isCreator
      self?.updatePaymentMethodVisibility()
      self?.onPledgeDetailsLabel?(isCreator ? Strings.Pledge_details() : Strings.Your_pledge_details())
    }
    _ = backing.observeValues { [weak self] backing in
      let enabled = isPledgeOverTime(with: backing)
      self?.onPlotScheduleHidden?(!enabled)
      if enabled { self?.onPlotSchedule?(backing.paymentIncrements) }
    }
  }

  private func loadBacking(_ backingID: Int) {
    self.backingReadTask?.cancel()
    let feature = self.feature
    let route = self.backingRoute
    let userID = feature.sessionFeature.currentUser?.id
    let generation = feature.sessionFeature.generation
    let id = UUID()
    self.backingReadIdentity.id = id
    self.backingReadTask = Task { [weak self] in
      do {
        let backing = try await feature.backing(route: route, id: backingID)
        try Task.checkCancellation()
        guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.backingReadEvents.input.send(value: (.value(backing), userID, generation, id))
        self?.backingReadEvents.input.send(value: (.completed, userID, generation, id))
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.backingReadEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
      }
    }
  }

  private func loadProject(_ param: Param) {
    self.projectReadTask?.cancel()
    let feature = self.feature
    let route = self.projectRoute
    let userID = feature.sessionFeature.currentUser?.id
    let generation = feature.sessionFeature.generation
    let id = UUID()
    self.projectReadIdentity.id = id
    self.projectReadTask = Task { [weak self] in
      do {
        let project = try await feature.project(route: route, param: param)
        try Task.checkCancellation()
        guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.projectReadEvents.input.send(value: (.value(project), userID, generation, id))
        self?.projectReadEvents.input.send(value: (.completed, userID, generation, id))
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.projectReadEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
      }
    }
  }

  public func beginRefresh() {
    self.onStartRefreshing?()
    self.fetchProjectIfNeeded()
    if let id = self.currentBackingParam?.id { self.loadBacking(id) }
  }

  public func configureWith(_ params: ManagePledgeViewParamConfigData) {
    self.configuredParams = params
    self.publishParamsWhenReady()
  }

  private func publishParamsWhenReady() {
    guard self.hasLoadedView, let params = self.configuredParams else { return }
    if let backing = params.backingParam {
      self.configuredBackingWasProvided = true
      self.currentBackingParam = backing
      if let id = backing.id { self.loadBacking(id) }
    }
    self.setRightBarHidden(true)
    self.onStartRefreshing?()
    self.fetchProjectIfNeeded()
  }

  private func updateTitle() {
    guard let project = self.titleProject, let isCreator = self.titleIsCreator else { return }
    self.onTitle?(navigationBarTitle(with: project, userIsCreatorOfProject: isCreator))
  }

  private func handleLoadError() {
    if !self.backingHasLoaded {
      self.onLoadRefreshHeader?()
      self.setRightBarHidden(true)
    }
    self.onShowError?(Strings.Something_went_wrong_please_try_again())
  }

  private func paymentMethodData(context: PledgeViewContext) -> PledgeViewData? {
    guard let project = self.currentProject, let backing = self.visibilityBacking,
          let rewards = self.currentRewards else { return nil }
    return pledgeViewData(project: project, backing: backing, rewards: rewards, context: context)
  }

  private func updatePaymentMethodVisibility() {
    guard let backing = self.visibilityBacking, let isCreator = self.visibilityIsCreator else { return }
    let hidden = isCreator || (!shouldShowFixPaymentMethodButton(for: backing) && backing.paymentSource == nil)
    guard self.paymentMethodHidden != hidden else { return }
    self.paymentMethodHidden = hidden
    self.onPaymentMethodHidden?(hidden)
  }

  private func setRightBarHidden(_ hidden: Bool) {
    guard self.rightBarHidden != hidden else { return }
    self.rightBarHidden = hidden
    self.onRightBarButtonHidden?(hidden)
  }

  private func fetchProjectIfNeeded() {
    guard self.hasLoadedView, !self.projectHasLoaded, let params = self.configuredParams else { return }
    self.loadProject(params.projectParam)
  }

  public func cancelPledgeDidFinish(with message: String) {
    self.onFinish?(message)
  }

  public func fixButtonTapped() {
    guard let data = self.paymentMethodData(context: .fixPaymentMethod) else { return }
    self.onFixPaymentMethod?(data)
  }

  public func menuButtonTapped() {
    guard let project = self.currentProject, let backing = self.visibilityBacking,
          let isCreator = self.visibilityIsCreator else { return }
    self.onShowMenu?(actionSheetMenuOptionsFor(project: project, backing: backing, userIsCreatorOfProject: isCreator))
  }

  public func menuOptionSelected(with action: ManagePledgeAlertAction) {
    switch action {
    case .chooseAnotherReward, .viewRewards:
      if let project = self.currentProject { self.onRewards?(project) }
    case .editPledgeOverTimePledge:
      if let project = self.currentProject { self.onEditPledgeOverTime?(project) }
    case .contactCreator:
      if let project = self.currentProject {
        self.onContactCreator?(.project(id: project.id, name: project.name), .backerModal)
      }
    case .changePaymentMethod:
      if let data = self.paymentMethodData(context: .changePaymentMethod) { self.onChangePaymentMethod?(data) }
    case .cancelPledge:
      if let project = self.currentProject, let backing = self.visibilityBacking, backing.cancelable {
        self.onCancelPledge?(cancelPledgeViewData(with: project, backing: backing))
      }
      if self.hasSeenDisallowedCancellation {
        self.onShowError?(Strings.We_dont_allow_cancelations_that_will_cause_a_project_to_fall_short_of_its_goal_within_the_last_24_hours())
      }
    }
  }

  public func termsOfUseTapped(with helpType: HelpType) {
    self.onShowHelp?(helpType)
  }

  public func pledgeViewControllerDidUpdatePledgeWithMessage(_ message: String) {
    self.beginRefresh()
    self.onShowSuccess?(message)
  }

  public func viewDidLoad() {
    self.hasLoadedView = true
    self.publishParamsWhenReady()
  }

  public var onPaymentMethod: ((ManagePledgePaymentMethodViewData) -> Void)?
  public var onPledgeSummary: ((ManagePledgeSummaryViewData) -> Void)?
  public var onPlotSchedule: (([PledgePaymentIncrement]) -> Void)?
  public var onEndRefreshing: (() -> Void)?
  public var onCancelPledge: ((CancelPledgeViewData) -> Void)?
  public var onChangePaymentMethod: ((PledgeViewData) -> Void)?
  public var onContactCreator: ((MessageSubject, KSRAnalytics.MessageDialogContext) -> Void)?
  public var onFixPaymentMethod: ((PledgeViewData) -> Void)?
  public var onRewards: ((Project) -> Void)?
  public var onEditPledgeOverTime: ((Project) -> Void)?
  public var onLoadProjectAndRewards: ((Project, [Reward]) -> Void)?
  public var onLoadRefreshHeader: (() -> Void)?
  public var onPaymentMethodHidden: ((Bool) -> Void)?
  public var onPledgeDetailsLabel: ((String) -> Void)?
  public var onPlotScheduleHidden: ((Bool) -> Void)?
  public var onFinish: ((String?) -> Void)?
  public var onRightBarButtonHidden: ((Bool) -> Void)?
  public var onShowMenu: (([ManagePledgeAlertAction]) -> Void)?
  public var onShowSuccess: ((String) -> Void)?
  public var onShowError: ((String) -> Void)?
  public var onShowHelp: ((HelpType) -> Void)?
  public var onStartRefreshing: (() -> Void)?
  public var onTitle: ((String) -> Void)?

  public var inputs: ManagePledgeViewModelInputs { return self }
  public var outputs: ManagePledgeViewModelOutputs { return self }
}

// MARK: - Functions

private func pledgeViewData(
  project: Project,
  backing: Backing,
  rewards: [Reward],
  context: PledgeViewContext
) -> PledgeViewData {
  return PledgeViewData(
    project: project,
    rewards: rewards,
    bonusSupport: nil,
    selectedShippingRule: nil,
    selectedQuantities: selectedRewardQuantities(in: backing),
    selectedLocationId: backing.locationId,
    refTag: nil,
    context: context
  )
}

private func actionSheetMenuOptionsFor(
  project: Project,
  backing: Backing,
  userIsCreatorOfProject: Bool
) -> [ManagePledgeAlertAction] {
  if userIsCreatorOfProject {
    return [.viewRewards]
  }

  guard project.state == .live else {
    return [.viewRewards, .contactCreator]
  }

  if backing.status == .preauth {
    return [.contactCreator]
  }

  var actions = ManagePledgeAlertAction.allCases
    .filter { $0 != .viewRewards && $0 != .editPledgeOverTimePledge }

  /// Enable the 'Edit pledge' option for all PLOT-enabled projects.
  if isPledgeOverTime(with: backing) || project.isPledgeOverTimeAllowed == true {
    actions = actions.filter { $0 != .chooseAnotherReward }
    actions.insert(.editPledgeOverTimePledge, at: 1)
  }

  return actions
}

private func navigationBarTitle(
  with project: Project,
  userIsCreatorOfProject: Bool
) -> String {
  if userIsCreatorOfProject {
    return Strings.Pledge_details()
  }

  return project.state == .live ? Strings.Manage_your_pledge() : Strings.Your_pledge()
}

private func managePledgeMenuCTAType(for managePledgeAlertAction: ManagePledgeAlertAction)
  -> KSRAnalytics.ManagePledgeMenuCTAType {
  switch managePledgeAlertAction {
  case .editPledgeOverTimePledge: return .editPledgeOverTimePledge
  case .cancelPledge: return .cancelPledge
  case .changePaymentMethod: return .changePaymentMethod
  case .chooseAnotherReward: return .chooseAnotherReward
  case .contactCreator: return .contactCreator
  case .viewRewards: return .viewRewards
  }
}

private func cancelPledgeViewData(
  with project: Project,
  backing: Backing
) -> CancelPledgeViewData {
  return .init(
    project: project,
    projectName: project.name,
    omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
    backingId: backing.graphID,
    pledgeAmount: backing.amount
  )
}

private func shouldShowFixPaymentMethodButton(for backing: Backing) -> Bool {
  // For PLOT pledges, the fix button is always hidden because the fix action
  // is handled by the `PledgeStatusLabelView`.
  if isPledgeOverTime(with: backing) { return false }
  return backing.status == .errored
}

private func managePledgePaymentMethodViewData(
  with backing: Backing
) -> ManagePledgePaymentMethodViewData {
  ManagePledgePaymentMethodViewData(
    showFixPaymentButton: shouldShowFixPaymentMethodButton(for: backing),
    expirationDate: backing.paymentSource?.expirationDate,
    lastFour: backing.paymentSource?.lastFour,
    creditCardType: backing.paymentSource?.type,
    paymentType: backing.paymentSource?.paymentType
  )
}

private func isPledgeOverTime(with backing: Backing) -> Bool {
  return !backing.paymentIncrements.isEmpty
}

@MainActor
private func managePledgeSummaryViewData(
  with projectAndReward: (Project, Reward),
  backing: Backing,
  rewardReceivedWithData: ManageViewPledgeRewardReceivedViewData,
  rewardReceivedViewControllerViewIsHidden: Bool
) -> ManagePledgeSummaryViewData? {
  let (project, backedReward) = projectAndReward

  guard let backer = backing.backer,
        let deadline = project.dates.deadline else { return nil }

  let isRewardLocalPickup = isRewardLocalPickup(backing.reward)

  return ManagePledgeSummaryViewData(
    backerId: backer.id,
    backerName: backer.name,
    backerSequence: backing.sequence,
    backingState: backing.status,
    bonusAmount: backing.bonusAmount,
    currentUserIsCreatorOfProject: currentUserIsCreator(of: project),
    isNoReward: backedReward.id == Reward.noReward.id,
    locationName: backing.locationName,
    needsConversion: project.stats.needsConversion,
    omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
    pledgeAmount: backing.amount,
    pledgedOn: backing.pledgedAt,
    currencyCode: project.statsCurrency,
    projectDeadline: deadline,
    projectState: project.state,
    rewardMinimum: backing.rewardsAmount ?? allRewardsTotal(for: backing),
    rewardReceivedViewControllerViewIsHidden: rewardReceivedViewControllerViewIsHidden,
    rewardReceivedWithData: rewardReceivedWithData,
    shippingAmount: backing.shippingAmount.flatMap(Double.init),
    shippingAmountHidden: backing.reward?.shipping.enabled == false || backing.shippingAmount == 0,
    rewardIsLocalPickup: isRewardLocalPickup,
    paymentIncrements: backing.paymentIncrements,
    project: project
  )
}

private func allRewardsTotal(for backing: Backing) -> Double {
  let baseRewardAmount = backing.reward?.minimum ?? 0

  guard let addOns = backing.addOns else { return baseRewardAmount }

  return baseRewardAmount + addOns.reduce(0.0) { total, addOn in total.addingCurrency(addOn.minimum) }
}

private func distinctRewards(_ rewards: [Reward]) -> [Reward] {
  var rewardIds: Set<Int> = []
  return rewards.filter { reward in
    defer { rewardIds.insert(reward.id) }
    return !rewardIds.contains(reward.id)
  }
}
