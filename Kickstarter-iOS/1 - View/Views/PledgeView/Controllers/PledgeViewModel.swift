import Foundation
import KsApi
import PassKit
import Prelude

public typealias PledgeViewCTAContainerViewData = (
  project: Project,
  total: Double,
  isLoggedIn: Bool,
  isEnabled: Bool,
  context: PledgeViewContext,
  willRetryPaymentMethod: Bool
)

public typealias StripeConfigurationData = (merchantIdentifier: String, publishableKey: String)
public typealias CreateBackingData = (
  project: Project,
  rewards: [Reward],
  pledgeTotal: Double,
  selectedQuantities: SelectedRewardQuantities,
  shippingRule: ShippingRule?,
  paymentSourceId: String?,
  setupIntentClientSecret: String?,
  applePayParams: ApplePayParams?,
  refTag: RefTag?,
  incremental: Bool?
)
public typealias UpdateBackingData = (
  backing: Backing,
  rewards: [Reward],
  pledgeTotal: Double,
  selectedQuantities: SelectedRewardQuantities,
  shippingRule: ShippingRule?,
  paymentSourceId: String?,
  setupIntentClientSecret: String?,
  applePayParams: ApplePayParams?,
  pledgeContext: PledgeViewContext,
  incremental: Bool
)
public typealias PaymentAuthorizationData = (
  project: Project,
  reward: Reward,
  allRewardsTotal: Double,
  additionalPledgeAmount: Double,
  allRewardsShippingTotal: Double,
  merchantIdentifier: String
)
public typealias PKPaymentData = (displayName: String, network: String, transactionIdentifier: String)

public struct PledgeViewData: Equatable {
  public let project: Project
  public let rewards: [Reward]
  public let bonusSupport: Double?
  public let selectedShippingRule: ShippingRule?
  public let selectedQuantities: SelectedRewardQuantities
  public let selectedLocationId: Int?
  public let refTag: RefTag?
  public let context: PledgeViewContext
}

@MainActor
public protocol PledgeViewModelInputs {
  func applePayButtonTapped()
  func configure(with data: PledgeViewData)
  func creditCardSelected(with paymentSourceData: PaymentSourceSelected)
  func goToLoginSignupTapped()
  func userSessionDidChange()
  func paymentAuthorizationDidAuthorizePayment(
    paymentData: (displayName: String?, network: String?, transactionIdentifier: String)
  )
  func paymentAuthorizationViewControllerDidFinish()
  func paymentPlanSelected(_ paymentPlan: PledgePaymentPlansType)
  func pledgeDisclaimerViewDidTapLearnMore()
  func scaFlowCompleted(with result: StripePaymentHandlerActionStatusType, error: Error?)
  func stripeTokenCreated(token: String?, error: Error?) -> PKPaymentAuthorizationStatus
  func submitButtonTapped()
  func termsOfUseTapped(with: HelpType)
  func viewDidLoad()
}

@MainActor
public protocol PledgeViewModelOutputs: AnyObject {
  var onBeginSCA: ((String) -> Void)? { get set }
  var onEstimatedShipping: ((String?, String?) -> Void)? { get set }
  var onLocalPickupData: ((PledgeLocalPickupViewData) -> Void)? { get set }
  var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)? { get set }
  var onPledgeAmountSummary: ((PledgeAmountSummaryViewData) -> Void)? { get set }
  var onPledgeRewardsSummary: ((PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData) -> Void)? { get set }
  var onPledgeCTA: ((PledgeViewCTAContainerViewData) -> Void)? { get set }
  var onConfigureStripe: ((String, String) -> Void)? { get set }
  var onEstimatedShippingHidden: ((Bool) -> Void)? { get set }
  var onApplePayAuthorization: ((PaymentAuthorizationData) -> Void)? { get set }
  var onGoToThanks: ((ThanksPageData) -> Void)? { get set }
  var onGoToLoginSignup: ((LoginIntent) -> Void)? { get set }
  var onLocalPickupHidden: ((Bool) -> Void)? { get set }
  var onPledgeUpdateSucceeded: ((String) -> Void)? { get set }
  var onPaymentMethodsHidden: ((Bool) -> Void)? { get set }
  var onPledgeAmountSummaryHidden: ((Bool) -> Void)? { get set }
  var onProcessingHidden: ((Bool) -> Void)? { get set }
  var onShowError: ((String) -> Void)? { get set }
  var onShowWebHelp: ((HelpType) -> Void)? { get set }
  var onTitle: ((String) -> Void)? { get set }
  var onShowPledgeOverTime: ((Bool) -> Void)? { get set }
  var onPledgeOverTimeConfig: ((PledgePaymentPlansAndSelectionData?) -> Void)? { get set }
}

@MainActor
public protocol PledgeViewModelType {
  var inputs: PledgeViewModelInputs { get }
  var outputs: PledgeViewModelOutputs { get }
}

@MainActor
public class PledgeViewModel: PledgeViewModelType, PledgeViewModelInputs,
  PledgeViewModelOutputs {
  public init(feature: PledgeFeature = AppModel.shared.pledgeFeature) {
    let formState = self.formState
    let ctaState = PledgeCTAState()
    let requestState = PledgeRequestState()
    formState.onChange = { ctaState.setEnabled($0) }

    self.loginSignupUseCase = LoginSignupUseCase(withLoginIntent: .backProject)
    let login = self.loginSignupUseCase

    self.paymentMethodsUseCase = PaymentMethodsUseCase()
    let paymentMethods = self.paymentMethodsUseCase
    paymentMethods.onSelected = { value in
      ctaState.selectPayment(value)
      requestState.selectPayment(value)
    }
    paymentMethods.onValidity = { formState.setPaymentValid($0) }
    login.onLoginState = { value in
      ctaState.setLoggedIn(value)
      paymentMethods.loginChanged(value)
    }

    // MARK: - Apple Pay

    self.applePayAuthorization.onParams = { requestState.setApplePayParams($0) }

    // MARK: Pledge Over Time

    self.pledgeOverTimeUseCase = PledgeOverTimeUseCase(feature: feature)
    let planUseCase = self.pledgeOverTimeUseCase
    planUseCase.onLoading = { formState.setPlanLoading($0) }

    // MARK: - Create Backing

    let processingState = PledgeProcessingState()
    let completionState = self.completionState
    let scheduler = AppEnvironment.current.scheduler
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let scheduleResponse: (PledgeResponse, Bool, Int?, Int, UUID) -> Void = { [weak self] response, isCreate, userID, generation, id in
      let action = { [weak self] in
        MainActor.assumeIsolated {
          guard let self else { return }
          let identity = isCreate ? self.createIdentity : self.updateIdentity
          guard identity.id == id else { return }
          guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else {
            identity.id = UUID()
            processingState.setHidden(true)
            return
          }
          switch response {
          case let .created(envelope):
            self.thanksState.checkoutID = decompose(id: envelope.createBacking.checkout.id)
            self.thanksState.hasCheckoutResult = true
            completionState.received(envelope)
            processingState.setHidden(true)
            formState.requestFinished()
            completionState.requestFinished()
          case let .updated(envelope):
            completionState.received(envelope)
            processingState.setHidden(true)
            formState.requestFinished()
            completionState.requestFinished()
          case let .failed(error):
            processingState.setHidden(true)
            formState.requestFinished()
            completionState.failed(error)
          }
        }
      }
      if delay.isInfinite { return }
      _ = scheduler.schedule(after: scheduler.currentDate.addingTimeInterval(max(0, delay)), action: action)
    }

    self.presentData = { [weak self] data in
      self?.onTitle?(data.context.title)
      self?.completionState.setContext(data.context)
      let amounts = PledgeAmounts(data)
      let rewardsTotal = amounts.rewards
      let shippingTotal = amounts.shipping
      let bonusAmount = amounts.bonus
      let total = amounts.total
      let locationName = data.selectedShippingRule?.location.localizedName ?? data.project.personalization.backing?.locationName
      let shippingSummary = locationName.map {
        PledgeShippingSummaryViewData(locationName: $0, omitUSCurrencyCode: data.project.stats.omitUSCurrencyCode,
                                      currencyCode: data.project.stats.projectCurrency, total: shippingTotal)
      }
      if let total {
        let rewardsData = PostCampaignRewardsSummaryViewData(
          rewards: data.rewards, selectedQuantities: data.selectedQuantities, currencyCode: data.project.statsCurrency,
          omitCurrencyCode: data.project.stats.omitUSCurrencyCode, shipping: shippingSummary,
          useLatePledgeCosts: data.context == .latePledge ||
            (data.context == .fixPaymentMethod && data.project.personalization.backing?.isLatePledge == true)
        )
        let pledgeData = PledgeSummaryViewData(project: data.project, total: total, confirmationLabelHidden: false,
                                               pledgeHasNoReward: pledgeHasNoRewards(rewards: data.rewards))
        self?.onPledgeRewardsSummary?(rewardsData, bonusAmount, pledgeData)
      }
      if let reward = data.rewards.first {
        let locationHidden = data.context.shippingLocationViewHidden || !reward.shipping.enabled || data.rewards.count > 1
        let summaryHidden = data.context.isAny(of: .changePaymentMethod, .fixPaymentMethod) ||
          !reward.shipping.enabled || data.rewards.count == 1
        if let summary = pledgeAmountSummaryViewData(with: data.project, reward: reward, allRewardsTotal: rewardsTotal,
                                                     additionalPledgeAmount: bonusAmount,
                                                     shippingViewsHidden: locationHidden && summaryHidden) {
          self?.onPledgeAmountSummary?(summary)
        }
      }
      if let locationName = data.rewards.first?.localPickup?.displayableName {
        self?.onLocalPickupData?(PledgeLocalPickupViewData(locationName: locationName))
      }
      let shipping: String?
      let conversion: String?
      if let rule = data.selectedShippingRule {
        shipping = estimatedShippingText(for: data.rewards, project: data.project,
          locationId: rule.location.id, selectedQuantities: data.selectedQuantities)
        conversion = estimatedShippingConversionText(for: data.rewards, project: data.project,
          locationId: rule.location.id, selectedQuantities: data.selectedQuantities)
      } else {
        shipping = nil
        conversion = nil
      }
      self?.onEstimatedShipping?(shipping, conversion)
      if let reward = data.rewards.first {
        self?.onEstimatedShippingHidden?(!reward.shipping.enabled || shipping == nil)
      }
      self?.onPledgeAmountSummaryHidden?(data.context.pledgeAmountSummaryViewHidden)
      if let reward = data.rewards.first { self?.onLocalPickupHidden?(!isRewardLocalPickup(reward)) }
      guard !data.context.paymentMethodsViewHidden else { return }
      self?.onConfigureStripe?(
        Secrets.ApplePay.merchantIdentifier,
        AppEnvironment.current.environmentType.stripePublishableKey
      )
    }
    requestState.onCreate = { [weak self] in self?.latestCreateBackingData = $0 }
    requestState.onUpdate = { [weak self] in self?.latestUpdateBackingData = $0 }
    self.configureState = { data in
      ctaState.configure(data)
      formState.configure()
      requestState.configure(data)
      login.initialDataAvailable()
      paymentMethods.configure(data)
      planUseCase.updateProject(data.project)
      if let total = PledgeAmounts(data).total { planUseCase.updateTotal(total) }
      planUseCase.updateContext(data.context)
    }
    ctaState.onChange = { [weak self] in self?.onPledgeCTA?($0) }
    processingState.onChange = { [weak self] in self?.onProcessingHidden?($0) }
    self.startCreate = { [weak self] data, isApplePay in
      guard let self else { return }
      let input = CreateBackingInput.input(from: data, isApplePay: isApplePay)
      self.createTask?.cancel()
      let userID = feature.sessionFeature.currentUser?.id
      let generation = feature.sessionFeature.generation
      let id = UUID()
      self.createIdentity.id = id
      let request = feature.startCreate(input)
      processingState.setHidden(false)
      self.createTask = Task { [weak self] in
        do {
          let result = try await request.value
          guard !Task.isCancelled else { return }
          scheduleResponse(.created(result), true, userID, generation, id)
        } catch {
          if Task.isCancelled || error is CancellationError {
            if self?.createIdentity.id == id { processingState.setHidden(true) }
            return
          }
          scheduleResponse(.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), true, userID, generation, id)
        }
      }
    }
    self.startUpdate = { [weak self] data, isApplePay in
      guard let self else { return }
      let input = UpdateBackingInput.input(from: data, isApplePay: isApplePay)
      self.updateTask?.cancel()
      let userID = feature.sessionFeature.currentUser?.id
      let generation = feature.sessionFeature.generation
      let id = UUID()
      self.updateIdentity.id = id
      let request = feature.startUpdate(input)
      processingState.setHidden(false)
      self.updateTask = Task { [weak self] in
        do {
          let result = try await request.value
          guard !Task.isCancelled else { return }
          scheduleResponse(.updated(result), false, userID, generation, id)
        } catch {
          if Task.isCancelled || error is CancellationError {
            if self?.updateIdentity.id == id { processingState.setHidden(true) }
            return
          }
          scheduleResponse(.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), false, userID, generation, id)
        }
      }
    }
    completionState.onSuccess = { [weak self] context in
      guard let self else { return }
      if context.isCreating, let data = self.thanksState.pageData() { self.onGoToThanks?(data) }
      if context.isUpdating { self.onPledgeUpdateSucceeded?(Strings.Got_it_your_changes_have_been_saved()) }
    }
    completionState.onError = { [weak self] in self?.onShowError?($0) }
    completionState.onSCA = { [weak self] in self?.onBeginSCA?($0) }
    self.applePayAuthorization.onSuccess = { [weak self] in
      self?.startBacking(isApplePay: true)
    }
    planUseCase.onShow = { [weak self] in self?.onShowPledgeOverTime?($0) }
    planUseCase.onConfig = { [weak self] data in
      requestState.selectPlan(data?.selectedPlan ?? .pledgeInFull)
      self?.onPledgeOverTimeConfig?(data)
    }
    login.onLogin = { [weak self] in self?.onGoToLoginSignup?($0) }
    paymentMethods.onHidden = { [weak self] in self?.onPaymentMethodsHidden?($0) }
    paymentMethods.onConfiguration = { [weak self] in self?.onConfigurePaymentMethods?($0) }
  }

  // MARK: - Inputs

  public func applePayButtonTapped() {
    guard self.hasLoadedView, let data = self.configuredData, let reward = data.rewards.first else {
      return
    }
    let amounts = PledgeAmounts(data)
    self.trackPledgeSubmission(isApplePay: true)
    self.onApplePayAuthorization?((data.project, reward, amounts.rewards, amounts.bonus, amounts.shipping,
                                   Secrets.ApplePay.merchantIdentifier))
  }

  private var configuredData: PledgeViewData?
  private var latestCreateBackingData: CreateBackingData?
  private var latestUpdateBackingData: UpdateBackingData?
  private let thanksState = PledgeThanksState()
  private let completionState = PledgeCompletionState()
  private var hasLoadedView = false
  private var configureState: ((PledgeViewData) -> Void)?
  private var presentData: ((PledgeViewData) -> Void)?
  private let formState = PledgeFormState()

  public func configure(with data: PledgeViewData) {
    // A request from the previous configuration must never be submitted for this pledge.
    self.latestCreateBackingData = nil
    self.latestUpdateBackingData = nil
    self.configuredData = data
    self.publishInitialDataWhenReady()
  }

  private func publishInitialDataWhenReady() {
    guard self.hasLoadedView, let data = self.configuredData else { return }
    self.configureState?(data)
    self.presentData?(data)
    guard let reward = data.rewards.first, let total = PledgeAmounts(data).total else { return }
    let checkoutData = checkoutProperties(
      from: data.project, baseReward: reward, addOnRewards: data.rewards,
      selectedQuantities: data.selectedQuantities, additionalPledgeAmount: PledgeAmounts(data).bonus,
      pledgeTotal: total, shippingTotal: 0, checkoutId: nil, isApplePay: false
    )
    AppEnvironment.current.ksrAnalytics.trackCheckoutPaymentPageViewed(
      project: data.project, reward: reward, pledgeViewContext: data.context,
      checkoutData: checkoutData, refTag: data.refTag
    )
  }

  public func creditCardSelected(with paymentSourceData: PaymentSourceSelected) {
    self.paymentMethodsUseCase.creditCardSelected(with: paymentSourceData)
  }

  private let applePayAuthorization = ApplePayAuthorization()
  public func paymentAuthorizationDidAuthorizePayment(paymentData: (
    displayName: String?, network: String?, transactionIdentifier: String
  )) {
    self.applePayAuthorization.authorized(paymentData)
  }

  public func paymentAuthorizationViewControllerDidFinish() {
    self.completionState.applePayFinished()
  }

  public func paymentPlanSelected(_ paymentPlan: PledgePaymentPlansType) {
    self.pledgeOverTimeUseCase.paymentPlanSelected(paymentPlan)
  }

  public func goToLoginSignupTapped() {
    self.loginSignupUseCase.goToLoginSignupTapped()
  }

  public func pledgeDisclaimerViewDidTapLearnMore() {
    self.onShowWebHelp?(.trust)
  }

  public func scaFlowCompleted(with result: StripePaymentHandlerActionStatusType, error: Error?) {
    self.completionState.scaFinished(result.status, error: error)
  }

  public func submitButtonTapped() {
    self.formState.submitted()
    self.startBacking(isApplePay: false)
    self.trackPledgeSubmission(isApplePay: false)
  }

  private func startBacking(isApplePay: Bool) {
    guard self.hasLoadedView, let context = self.configuredData?.context else { return }
    self.completionState.begin(context: context, isApplePay: isApplePay)
    if context.isCreating, let data = self.latestCreateBackingData {
      self.thanksState.configure(data: data, pledge: self.configuredData, isApplePay: isApplePay)
      self.startCreate?(data, isApplePay)
    } else if context.isUpdating, let data = self.latestUpdateBackingData {
      self.startUpdate?(data, isApplePay)
    }
  }

  private func trackPledgeSubmission(isApplePay: Bool) {
    guard let data = self.latestCreateBackingData, let configuredData = self.configuredData,
          let reward = configuredData.rewards.first else { return }
    let checkoutData = checkoutProperties(
      from: data.project, baseReward: reward, addOnRewards: data.rewards,
      selectedQuantities: data.selectedQuantities, additionalPledgeAmount: PledgeAmounts(configuredData).bonus,
      pledgeTotal: data.pledgeTotal, shippingTotal: 0, checkoutId: nil, isApplePay: isApplePay
    )
    AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
      project: data.project, reward: reward, typeContext: isApplePay ? .applePay : .creditCard,
      checkoutData: checkoutData, refTag: data.refTag
    )
  }

  public func stripeTokenCreated(token: String?, error: Error?) -> PKPaymentAuthorizationStatus {
    self.applePayAuthorization.tokenCreated(token: token, error: error)
  }

  public func termsOfUseTapped(with helpType: HelpType) {
    self.onShowWebHelp?(helpType)
  }

  public func viewDidLoad() {
    self.hasLoadedView = true
    self.publishInitialDataWhenReady()
    self.formState.viewLoaded()
  }

  public func userSessionDidChange() {
    self.loginSignupUseCase.userSessionDidChange()
  }

  // MARK: - Outputs

  public var onBeginSCA: ((String) -> Void)?
  public var onEstimatedShipping: ((String?, String?) -> Void)?
  public var onLocalPickupData: ((PledgeLocalPickupViewData) -> Void)?
  public var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)?

  public var onPledgeAmountSummary: ((PledgeAmountSummaryViewData) -> Void)?
  public var onPledgeRewardsSummary: ((PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData) -> Void)?
  public var onPledgeCTA: ((PledgeViewCTAContainerViewData) -> Void)?
  public var onConfigureStripe: ((String, String) -> Void)?
  public var onEstimatedShippingHidden: ((Bool) -> Void)?
  public var onApplePayAuthorization: ((PaymentAuthorizationData) -> Void)?
  public var onGoToThanks: ((ThanksPageData) -> Void)?
  public var onGoToLoginSignup: ((LoginIntent) -> Void)?

  public var onLocalPickupHidden: ((Bool) -> Void)?
  public var onPledgeUpdateSucceeded: ((String) -> Void)?
  public var onPaymentMethodsHidden: ((Bool) -> Void)?

  public var onPledgeAmountSummaryHidden: ((Bool) -> Void)?
  public var onProcessingHidden: ((Bool) -> Void)?
  public var onShowError: ((String) -> Void)?
  public var onShowWebHelp: ((HelpType) -> Void)?
  public var onTitle: ((String) -> Void)?

  public var onShowPledgeOverTime: ((Bool) -> Void)?
  public var onPledgeOverTimeConfig: ((PledgePaymentPlansAndSelectionData?) -> Void)?

  public var inputs: PledgeViewModelInputs { return self }
  public var outputs: PledgeViewModelOutputs { return self }

  // MARK: - Use cases

  private let createIdentity = PledgeWriteIdentity()
  private var startCreate: ((CreateBackingData, Bool) -> Void)?
  private var createTask: Task<Void, Never>?

  private let updateIdentity = PledgeWriteIdentity()
  private var startUpdate: ((UpdateBackingData, Bool) -> Void)?
  private var updateTask: Task<Void, Never>?

  deinit {
    self.updateTask?.cancel()
    self.createTask?.cancel()
  }

  private let pledgeOverTimeUseCase: PledgeOverTimeUseCase
  private let loginSignupUseCase: LoginSignupUseCase
  private let paymentMethodsUseCase: PaymentMethodsUseCase
}

// MARK: - Functions

// MARK: - Validation Functions

private func shippingRuleValid(
  project: Project,
  reward: Reward,
  shippingRule: ShippingRule?,
  context: PledgeViewContext
) -> Bool {
  if context.isCreating || context == .updateReward {
    return !reward.shipping.enabled || shippingRule != nil
  }

  guard
    let backing = project.personalization.backing,
    let shippingRule = shippingRule,
    context.isUpdating
  else {
    return false
  }

  return backing.locationId != shippingRule.location.id
}

// MARK: - Helper Functions

private enum PledgeResponse {
  case created(CreateBackingEnvelope)
  case updated(UpdateBackingEnvelope)
  case failed(ErrorEnvelope)
}

@MainActor
private final class PledgeCompletionState {
  var onSuccess: ((PledgeViewContext) -> Void)?
  var onError: ((String) -> Void)?
  var onSCA: ((String) -> Void)?
  private var context: PledgeViewContext?
  private var isApplePay = false
  private var hasStarted = false
  private var hasValue = false
  private var terminal = false
  private var didFinishApplePay = false
  private var error: ErrorEnvelope?

  func setContext(_ context: PledgeViewContext) { self.context = context }

  func begin(context: PledgeViewContext, isApplePay: Bool) {
    self.context = context
    self.isApplePay = isApplePay
    hasStarted = true
    hasValue = false
    terminal = false
    didFinishApplePay = false
    error = nil
  }

  func received(_ value: StripeSCARequiring) {
    hasValue = true
    if value.requiresSCAFlow {
      if let secret = value.clientSecret { onSCA?(secret) }
    } else if hasStarted && !isApplePay, let context {
      onSuccess?(context)
    }
  }

  func failed(_ error: ErrorEnvelope) {
    self.error = error
    terminal = true
    if isApplePay { completeApplePayIfReady() }
    else if hasStarted { onError?(error.localizedDescription) }
  }

  func requestFinished() {
    terminal = true
    if isApplePay { completeApplePayIfReady() }
  }

  func applePayFinished() {
    guard hasStarted && isApplePay else { return }
    didFinishApplePay = true
    completeApplePayIfReady()
  }

  func scaFinished(_ status: StripePaymentHandlerActionStatus, error: Error?) {
    if status == .failed, let error { onError?(error.localizedDescription) }
    if status == .succeeded, let context { onSuccess?(context) }
  }

  private func completeApplePayIfReady() {
    guard terminal, didFinishApplePay else { return }
    terminal = false
    if let error { onError?(error.localizedDescription) }
    else if hasValue, let context { onSuccess?(context) }
  }
}

@MainActor
private final class PledgeThanksState {
  var checkoutID: Int?
  var hasCheckoutResult = false
  private var data: CreateBackingData?
  private var pledge: PledgeViewData?
  private var isApplePay = false

  func configure(data: CreateBackingData, pledge: PledgeViewData?, isApplePay: Bool) {
    self.data = data
    self.pledge = pledge
    self.isApplePay = isApplePay
    checkoutID = nil
    hasCheckoutResult = false
  }

  func pageData() -> ThanksPageData? {
    guard hasCheckoutResult, let data, let pledge, let reward = pledge.rewards.first else { return nil }
    let amounts = PledgeAmounts(pledge)
    let checkout = checkoutProperties(
      from: data.project, baseReward: reward, addOnRewards: data.rewards,
      selectedQuantities: data.selectedQuantities, additionalPledgeAmount: amounts.bonus,
      pledgeTotal: data.pledgeTotal, shippingTotal: amounts.shipping,
      checkoutId: checkoutID.map(String.init), isApplePay: isApplePay
    )
    return (data.project, reward, checkout, data.pledgeTotal)
  }
}

@MainActor
private final class PledgeCTAState {
  var onChange: ((PledgeViewCTAContainerViewData) -> Void)?
  private var data: PledgeViewData?
  private var loggedIn: Bool?
  private var enabled: Bool?
  private var payment: PaymentSourceSelected?
  private var hasPaymentSelection = false

  func configure(_ data: PledgeViewData) { self.data = data; publish() }
  func setLoggedIn(_ value: Bool) { loggedIn = value; publish() }
  func setEnabled(_ value: Bool) { enabled = value; publish() }
  func selectPayment(_ value: PaymentSourceSelected?) {
    let previousRetry = retryState
    let hadSelection = hasPaymentSelection
    payment = value
    hasPaymentSelection = true
    if !hadSelection || previousRetry != retryState { publish() }
  }

  private var retryState: Bool {
    guard let data else { return false }
    return data.context == .fixPaymentMethod &&
      data.project.personalization.backing?.paymentSource?.id == payment?.savedCreditCardId
  }

  private func publish() {
    guard let data, let total = PledgeAmounts(data).total, let loggedIn, let enabled,
          hasPaymentSelection else { return }
    onChange?((data.project, total, loggedIn, enabled, data.context, retryState))
  }
}

@MainActor
private final class PledgeFormState {
  var onChange: ((Bool) -> Void)?
  private var hasContext = false
  private var paymentValid: Bool?
  private var planLoading: Bool?
  private var lastEmitted: Bool?

  func configure() { hasContext = true; publishCurrent() }
  func setPaymentValid(_ value: Bool) { paymentValid = value; publishCurrent() }
  func setPlanLoading(_ value: Bool) { planLoading = value; publishCurrent() }
  func submitted() { publish(false) }
  func requestFinished() { publishCurrent() }
  func viewLoaded() { if lastEmitted == nil { publish(false) } }

  private func publishCurrent() {
    guard hasContext, let paymentValid, let planLoading else { return }
    publish(paymentValid && !planLoading)
  }

  private func publish(_ value: Bool) {
    guard lastEmitted != value else { return }
    lastEmitted = value
    onChange?(value)
  }
}

@MainActor
final class PledgeRequestState {
  var onCreate: ((CreateBackingData) -> Void)?
  var onUpdate: ((UpdateBackingData) -> Void)?
  private var data: PledgeViewData?
  private var payment: PaymentSourceSelected?
  private var hasPaymentSelection = false
  private var plan: PledgePaymentPlansType?
  private var applePay: ApplePayParams?

  func configure(_ data: PledgeViewData) {
    self.data = data
    self.applePay = nil
    self.publish()
  }

  func selectPayment(_ payment: PaymentSourceSelected?) {
    self.payment = payment
    self.hasPaymentSelection = true
    self.publish()
  }

  func selectPlan(_ plan: PledgePaymentPlansType) {
    self.plan = plan
    self.publish()
  }

  func setApplePayParams(_ params: ApplePayParams) {
    self.applePay = params
    self.publish()
  }

  private func publish() {
    guard let data, let plan, hasPaymentSelection, let total = PledgeAmounts(data).total else { return }
    let paymentID = payment?.savedCreditCardId
    let incremental = plan == .pledgeOverTime
    onCreate?((project: data.project, rewards: data.rewards, pledgeTotal: total,
               selectedQuantities: data.selectedQuantities, shippingRule: data.selectedShippingRule,
               paymentSourceId: paymentID, setupIntentClientSecret: nil, applePayParams: applePay,
               refTag: data.refTag, incremental: incremental))
    if let backing = data.project.personalization.backing {
      onUpdate?((backing: backing, rewards: data.rewards, pledgeTotal: total,
                 selectedQuantities: data.selectedQuantities, shippingRule: data.selectedShippingRule,
                 paymentSourceId: paymentID, setupIntentClientSecret: nil, applePayParams: applePay,
                 pledgeContext: data.context, incremental: incremental))
    }
  }
}

private struct PledgeAmounts {
  let rewards: Double
  let shipping: Double
  let bonus: Double
  let total: Double?

  init(_ data: PledgeViewData) {
    let calculatedRewards = calculateAllRewardsTotal(addOnRewards: data.rewards, selectedQuantities: data.selectedQuantities)
    rewards = data.context == .fixPaymentMethod
      ? data.project.personalization.backing?.rewardsAmount ?? calculatedRewards
      : calculatedRewards
    shipping = data.selectedShippingRule.map {
      calculateShippingTotal(shippingRule: $0, addOnRewards: data.rewards, quantities: data.selectedQuantities)
    } ?? data.project.personalization.backing?.shippingAmount ?? 0
    bonus = data.bonusSupport ?? data.project.personalization.backing?.bonusAmount ?? 0
    total = data.context == .fixPaymentMethod
      ? data.project.personalization.backing?.amount
      : calculatePledgeTotal(pledgeAmount: bonus, shippingCost: shipping, addOnRewardsTotal: rewards)
  }
}


private func pledgeAmountSummaryViewData(
  with project: Project,
  reward _: Reward,
  allRewardsTotal: Double,
  additionalPledgeAmount: Double,
  shippingViewsHidden: Bool
) -> PledgeAmountSummaryViewData? {
  guard let backing = project.personalization.backing else { return nil }

  let rewardIsLocalPickup = isRewardLocalPickup(backing.reward)

  return .init(
    bonusAmount: additionalPledgeAmount,
    bonusAmountHidden: false,
    isNoReward: backing.reward?.isNoReward ?? false,
    locationName: backing.locationName,
    omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
    currencyCode: project.statsCurrency,
    pledgedOn: backing.pledgedAt,
    rewardMinimum: allRewardsTotal,
    shippingAmount: backing.shippingAmount.flatMap(Double.init),
    shippingAmountHidden: !shippingViewsHidden,
    rewardIsLocalPickup: rewardIsLocalPickup
  )
}

@MainActor
private final class ApplePayAuthorization {
  var onSuccess: (() -> Void)?
  var onParams: ((ApplePayParams) -> Void)?
  private var payment: PKPaymentData?

  func authorized(_ data: (displayName: String?, network: String?, transactionIdentifier: String)) {
    guard let name = data.displayName, let network = data.network else { self.payment = nil; return }
    self.payment = (name, network, data.transactionIdentifier)
  }

  func tokenCreated(token: String?, error: Error?) -> PKPaymentAuthorizationStatus {
    guard error == nil, let token, let payment = self.payment else { return .failure }
    self.onParams?(ApplePayParams(paymentInstrumentName: payment.displayName, paymentNetwork: payment.network, transactionIdentifier: payment.transactionIdentifier, token: token))
    self.onSuccess?()
    return .success
  }
}

@MainActor
private final class PledgeProcessingState {
  var onChange: ((Bool) -> Void)?

  func setHidden(_ hidden: Bool) {
    self.onChange?(hidden)
  }
}

@MainActor
private final class PledgeWriteIdentity {
  var id = UUID()
}
