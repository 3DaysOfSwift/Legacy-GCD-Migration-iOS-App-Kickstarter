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
private final class ManagePledgeReadIdentity {
  var id: UUID?
}

@MainActor
public final class ManagePledgeViewModel:
  ManagePledgeViewModelType, ManagePledgeViewModelInputs, ManagePledgeViewModelOutputs {
  private let feature: PledgeFeature
  private var currentMenuOptions: [ManagePledgeAlertAction]?
  private var currentFixPaymentMethodData: PledgeViewData?
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
    let params = Signal.combineLatest(
      self.configureWithProjectOrParamSignal,
      self.viewDidLoadSignal
    )
    .map(first)

    let projectParam = params.map(first)

    let shouldBeginRefresh = Signal.merge(
      self.pledgeViewControllerDidUpdatePledgeWithMessageSignal.ignoreValues(),
      self.beginRefreshSignal
    )

    // Keep track of whether the project has successfully loaded at least once.
    let projectLoaded = MutableProperty<Bool>(false)

    let shouldFetchProjectWithParam = Signal.merge(
      projectParam,
      projectParam.takeWhen(shouldBeginRefresh)
    )

    let fetchProjectEvent = self.projectReadEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [projectReadIdentity, feature] _, userID, generation, id in
        projectReadIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let initialProject = fetchProjectEvent.values()
      // Once we know we have a project value, keep track of that.
      .on(value: { [projectLoaded] _ in projectLoaded.value = true })

    let backingParamFromConfigData = params.map(second)
      .skipNil()
    let backingParamFromProject = initialProject.map { $0.personalization.backing?.id }
      .skipNil()
      .map(Param.id)

    let backingParam = Signal.merge(
      backingParamFromConfigData,
      backingParamFromProject
        .take(until: backingParamFromConfigData.ignoreValues())
    )

    let shouldFetchGraphBackingWithParam = Signal.merge(
      backingParam,
      backingParam.takeWhen(shouldBeginRefresh)
    )

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

    let title = project.combineLatest(with: userIsCreatorOfProject)
      .map(navigationBarTitle(with:userIsCreatorOfProject:))

    let configurePaymentMethodView = backing.map(managePledgePaymentMethodViewData)

    let projectOrBackingFailedToLoad = Signal.merge(
      fetchProjectEvent.map { $0.error as Error? },
      graphBackingEvent.map { $0.error as Error? }
    )
    .filter(isNotNil)

    let loadPullToRefreshHeaderView = projectOrBackingFailedToLoad
      .take(until: backing.ignoreValues())
      .ignoreValues()

    let paymentMethodViewHidden = Signal.combineLatest(
      userIsCreatorOfProject,
      backing
    )
    .map { userIsCreatorOfProject, backing in
      // Never show payment method view if the user is the creator.
      if userIsCreatorOfProject { return true }
      // Always show payment method view if the fix button should be shown.
      if shouldShowFixPaymentMethodButton(for: backing) { return false }
      // Otherwise, show payment method view if we have a payment method to display.
      return backing.paymentSource == nil
    }
    .skipRepeats()

    let loadProjectAndRewardsIntoDataSource = projectAndReward.combineLatest(with: backing)
      .map(unpack)
      .map { project, reward, backing -> (Project, [Reward]) in
        (project, distinctRewards([reward] + (backing.addOns ?? [])))
      }

    let rightBarButtonItemHidden = Signal.merge(
      params.mapConst(true),
      loadPullToRefreshHeaderView.mapConst(true),
      loadProjectAndRewardsIntoDataSource.mapConst(false)
    )
    .skipRepeats()

    let pledgeDisclaimerViewHidden = Signal.combineLatest(
      loadProjectAndRewardsIntoDataSource,
      userIsCreatorOfProject
    )
    .map(unpack)
    .map { _, rewards, userIsCreatorOfProject in
      rewards.map { $0.estimatedDeliveryOn }.allSatisfy(isNil) || userIsCreatorOfProject
    }

    let pledgeDetailsSectionLabelText = userIsCreatorOfProject.map {
      $0 ? Strings.Pledge_details() : Strings.Your_pledge_details()
    }

    let startRefreshing = Signal.merge(
      params.ignoreValues(),
      shouldBeginRefresh.ignoreValues()
    )

    // MARK: - ManageViewPledgeRewardReceivedViewData

    let latestRewardDeliveryDate = loadProjectAndRewardsIntoDataSource.map { _, rewards in
      rewards
        .compactMap { $0.estimatedDeliveryOn }
        .reduce(0) { accum, value in max(accum, value) }
    }

    let estimatedShipping = Signal.combineLatest(
      backing,
      loadProjectAndRewardsIntoDataSource
    )
    .map(unpack)
    .map { backing, project, rewards -> String? in
      guard let locationId = backing.locationId,
            let range = estimatedShippingText(
              for: rewards,
              project: project,
              locationId: locationId,
              selectedQuantities: selectedRewardQuantities(in: backing)
            )
      else { return nil }

      return Strings.About_reward_amount(reward_amount: range)
    }

    let rewardReceivedWithData = Signal.combineLatest(
      project,
      backing,
      latestRewardDeliveryDate,
      estimatedShipping,
      pledgeDisclaimerViewHidden
    )
    .map { project, backing, latestRewardDeliveryDate, estimatedShipping, pledgeDisclaimerViewHidden in
      ManageViewPledgeRewardReceivedViewData(
        project: project,
        backerCompleted: backing.backerCompleted ?? false,
        estimatedDeliveryOn: latestRewardDeliveryDate,
        backingState: backing.status,
        estimatedShipping: estimatedShipping,
        pledgeDisclaimerViewHidden: pledgeDisclaimerViewHidden
      )
    }

    // MARK: - Menu options

    let menuOptions = Signal.combineLatest(project, backing, userIsCreatorOfProject)
      .map(actionSheetMenuOptionsFor(project:backing:userIsCreatorOfProject:))

    let backedRewards = loadProjectAndRewardsIntoDataSource.map(second)

    let goToRewards = project
      .takeWhen(self.menuOptionSelectedSignal.filter { $0 == .chooseAnotherReward || $0 == .viewRewards })

    let goToEditPledgeOverTime = project
      .takeWhen(self.menuOptionSelectedSignal.filter { $0 == .editPledgeOverTimePledge })

    let cancelPledgeSelected = self.menuOptionSelectedSignal
      .filter { $0 == .cancelPledge }
      .ignoreValues()

    let goToCancelPledge = Signal.combineLatest(project, backing)
      .takeWhen(cancelPledgeSelected)
      .filter { _, backing in backing.cancelable }
      .map(cancelPledgeViewData(with:backing:))

    let goToContactCreator = project
      .takeWhen(self.menuOptionSelectedSignal.filter { $0 == .contactCreator })
      .map { project in (MessageSubject.project(id: project.id, name: project.name), KSRAnalytics.MessageDialogContext.backerModal) }

    let goToChangePaymentMethod = Signal.combineLatest(project, backing, backedRewards)
      .takeWhen(self.menuOptionSelectedSignal.filter { $0 == .changePaymentMethod })
      .map { project, backing, rewards in
        (project, backing, rewards, .changePaymentMethod)
      }
      .map(pledgeViewData)

    let fixPaymentMethodData = Signal.combineLatest(project, backing, backedRewards)
      .map { project, backing, rewards in
        (project, backing, rewards, .fixPaymentMethod)
      }
      .map(pledgeViewData)

    let notifyDelegateManagePledgeViewControllerFinishedWithMessage = backing.skip(first: 1)
      .mapConst(nil as String?)

    let rewardReceivedViewControllerViewIsHidden: Signal<Bool, Never> = latestRewardDeliveryDate
      .map { $0 == 0 }

    let configurePledgeSummaryView = Signal.combineLatest(
      projectAndReward,
      backing,
      rewardReceivedWithData,
      rewardReceivedViewControllerViewIsHidden
    )
    .compactMap {
      managePledgeSummaryViewData(
        with: $0.0, backing: $0.1, rewardReceivedWithData: $0.2,
        rewardReceivedViewControllerViewIsHidden: $0.3
      )
    }

    let cancelBackingDisallowed = backing
      .map { $0.cancelable }
      .filter(isFalse)

    let attemptedDisallowedCancelBackingMessage = cancelBackingDisallowed
      .takeWhen(cancelPledgeSelected)
      .map { _ in
        // swiftformat:disable wrap
        Strings.We_dont_allow_cancelations_that_will_cause_a_project_to_fall_short_of_its_goal_within_the_last_24_hours()
        // swiftformat:enable wrap
      }

    let networkErrorMessage = Signal.merge(
      fetchProjectEvent.errors().ignoreValues(),
      graphBackingEvent.errors().ignoreValues()
    )
    .map { _ in Strings.Something_went_wrong_please_try_again() }

    let showErrorBannerWithMessage = Signal.merge(
      attemptedDisallowedCancelBackingMessage,
      networkErrorMessage
    )

    // Tracking

    Signal.zip(loadProjectAndRewardsIntoDataSource, backing)
      .map(unpack)
      .observeValues { project, rewards, backing in
        guard let reward = backing.reward else { return }

        let checkoutData = checkoutProperties(
          from: project,
          baseReward: reward,
          addOnRewards: rewards,
          selectedQuantities: selectedRewardQuantities(in: backing),
          additionalPledgeAmount: backing.bonusAmount,
          pledgeTotal: backing.amount,
          shippingTotal: Double(backing.shippingAmount ?? 0),
          isApplePay: backing.paymentSource?.paymentType == .applePay
        )

        AppEnvironment.current.ksrAnalytics.trackManagePledgePageViewed(
          project: project,
          reward: reward,
          checkoutData: checkoutData
        )
      }

    // Pledge Over Time

    let pledgeOverTimeEnabled = backing.map {
      isPledgeOverTime(with: $0)
    }

    let plotPaymentScheduleViewHidden = pledgeOverTimeEnabled.negate()

    let configurePlotPaymentScheduleView = backing
      .filterWhenLatestFrom(pledgeOverTimeEnabled, satisfies: { $0 })
      .map { $0.paymentIncrements }

    _ = endRefreshing.observeValues { [weak self] _ in self?.onEndRefreshing?() }
    _ = goToCancelPledge.observeValues { [weak self] value in self?.onCancelPledge?(value) }
    _ = goToChangePaymentMethod.observeValues { [weak self] value in self?.onChangePaymentMethod?(value) }
    _ = goToContactCreator.observeValues { [weak self] first, second in self?.onContactCreator?(first, second) }
    _ = fixPaymentMethodData.observeValues { [weak self] value in self?.currentFixPaymentMethodData = value }
    _ = goToRewards.observeValues { [weak self] value in self?.onRewards?(value) }
    _ = goToEditPledgeOverTime.observeValues { [weak self] value in self?.onEditPledgeOverTime?(value) }
    _ = loadProjectAndRewardsIntoDataSource.observeValues { [weak self] first, second in self?.onLoadProjectAndRewards?(first, second) }
    _ = loadPullToRefreshHeaderView.observeValues { [weak self] _ in self?.onLoadRefreshHeader?() }
    _ = notifyDelegateManagePledgeViewControllerFinishedWithMessage.observeValues { [weak self] value in self?.onFinish?(value) }
    _ = menuOptions.observeValues { [weak self] value in self?.currentMenuOptions = value }
    _ = showErrorBannerWithMessage.observeValues { [weak self] value in self?.onShowError?(value) }
    _ = startRefreshing.observeValues { [weak self] _ in self?.onStartRefreshing?() }
    _ = title.observeValues { [weak self] in self?.onTitle?($0) }
    _ = configurePaymentMethodView.observeValues { [weak self] in self?.onPaymentMethod?($0) }
    _ = configurePledgeSummaryView.observeValues { [weak self] in self?.onPledgeSummary?($0) }
    _ = paymentMethodViewHidden.observeValues { [weak self] in self?.onPaymentMethodHidden?($0) }
    _ = pledgeDetailsSectionLabelText.observeValues { [weak self] in self?.onPledgeDetailsLabel?($0) }
    _ = plotPaymentScheduleViewHidden.observeValues { [weak self] in self?.onPlotScheduleHidden?($0) }
    _ = configurePlotPaymentScheduleView.observeValues { [weak self] in self?.onPlotSchedule?($0) }
    _ = rightBarButtonItemHidden.observeValues { [weak self] in self?.onRightBarButtonHidden?($0) }
    _ = shouldFetchProjectWithParam
      .filter { [projectLoaded] _ in !projectLoaded.value }
      .observeValues { [weak self] param in self?.loadProject(param) }
    _ = shouldFetchGraphBackingWithParam.map(\.id).skipNil()
      .observeValues { [weak self] id in self?.loadBacking(id) }
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

  private let (beginRefreshSignal, beginRefreshObserver) = Signal<Void, Never>.pipe()
  public func beginRefresh() {
    self.beginRefreshObserver.send(value: ())
  }

  private let (configureWithProjectOrParamSignal, configureWithProjectOrParamObserver)
    = Signal<ManagePledgeViewParamConfigData, Never>.pipe()
  public func configureWith(_ params: ManagePledgeViewParamConfigData) {
    self.configureWithProjectOrParamObserver.send(value: params)
  }

  public func cancelPledgeDidFinish(with message: String) {
    self.onFinish?(message)
  }

  public func fixButtonTapped() {
    guard let data = self.currentFixPaymentMethodData else { return }
    self.onFixPaymentMethod?(data)
  }

  public func menuButtonTapped() {
    guard let options = self.currentMenuOptions else { return }
    self.onShowMenu?(options)
  }

  private let (menuOptionSelectedSignal, menuOptionSelectedObserver) = Signal<ManagePledgeAlertAction, Never>
    .pipe()
  public func menuOptionSelected(with action: ManagePledgeAlertAction) {
    self.menuOptionSelectedObserver.send(value: action)
  }

  public func termsOfUseTapped(with helpType: HelpType) {
    self.onShowHelp?(helpType)
  }

  private let (
    pledgeViewControllerDidUpdatePledgeWithMessageSignal,
    pledgeViewControllerDidUpdatePledgeWithMessageObserver
  ) = Signal<String, Never>.pipe()
  public func pledgeViewControllerDidUpdatePledgeWithMessage(_ message: String) {
    self.pledgeViewControllerDidUpdatePledgeWithMessageObserver.send(value: message)
    self.onShowSuccess?(message)
  }

  private let (viewDidLoadSignal, viewDidLoadObserver) = Signal<(), Never>.pipe()
  public func viewDidLoad() {
    self.viewDidLoadObserver.send(value: ())
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
