import Foundation
import KsApi
import PassKit
import Prelude
import ReactiveSwift

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
    let initialData = self.initialDataEvents.output

    let project = initialData.map(\.project)
    let baseReward = initialData.map(\.rewards).map(\.first).skipNil()
    let context = initialData.map(\.context)
    let requestState = PledgeRequestState()
    let createDataPipe = Signal<CreateBackingData, Never>.pipe()
    let updateDataPipe = Signal<UpdateBackingData, Never>.pipe()
    requestState.onCreate = { createDataPipe.input.send(value: $0) }
    requestState.onUpdate = { updateDataPipe.input.send(value: $0) }
    initialData.observeValues { requestState.configure($0) }

    self.loginSignupUseCase = LoginSignupUseCase(withLoginIntent: .backProject)
    let login = self.loginSignupUseCase
    let loginState = self.loginStatePipe
    login.onLoginState = { loginState.input.send(value: $0) }
    initialData.observeValues { _ in login.initialDataAvailable() }

    self.paymentMethodsUseCase = PaymentMethodsUseCase()
    let paymentMethods = self.paymentMethodsUseCase
    let paymentSelected = self.paymentSelectedPipe
    let paymentValid = self.paymentValidPipe
    paymentMethods.onSelected = { value in
      paymentSelected.input.send(value: value)
      requestState.selectPayment(value)
    }
    paymentMethods.onValidity = { paymentValid.input.send(value: $0) }
    initialData.observeValues { paymentMethods.configure($0) }
    self.loginStatePipe.output.observeValues { paymentMethods.loginChanged($0) }

    let amounts = initialData.map(PledgeAmounts.init)
    let allRewardsShippingTotal = amounts.map(\.shipping)
    let additionalPledgeAmount = amounts.map(\.bonus)
    let pledgeTotal = amounts.map(\.total).skipNil()

    // MARK: - Apple Pay

    let changingApplePayPaymentMethod = self.applePayButtonTappedSignal
      .combineLatest(with: context)
      .map(second)
      .filter { $0 == .changePaymentMethod }
      .ignoreValues()

    let applePayStatusSuccess = self.applePaySuccessPipe.output
    let willCreateApplePayBacking = applePayStatusSuccess
      .combineLatest(with: context)
      .map { $1.isCreating }
      .filter(isTrue)
    let applePaySuccess = self.applePaySuccessPipe
    self.applePayAuthorization.onParams = { requestState.setApplePayParams($0) }

    // MARK: Pledge Over Time

    self.pledgeOverTimeUseCase = PledgeOverTimeUseCase(feature: feature)
    let planUseCase = self.pledgeOverTimeUseCase
    let planLoading = self.planLoadingPipe
    planUseCase.onLoading = { planLoading.input.send(value: $0) }
    initialData.observeValues { data in
      planUseCase.updateProject(data.project)
      if let total = PledgeAmounts(data).total { planUseCase.updateTotal(total) }
      planUseCase.updateContext(data.context)
    }

    // MARK: - Create Backing

    let createBackingData = createDataPipe.output

    let createButtonTapped = context
      .takeWhen(self.submitButtonTappedSignal)
      .filter { context in context.isCreating }
      .ignoreValues()

    let createBackingDataAndIsApplePay = createBackingData.takePairWhen(
      Signal.merge(
        createButtonTapped.mapConst(false),
        willCreateApplePayBacking
      )
    )

    // Captures the checkoutId immediately and avoids a race condition further down the chain.
    let checkoutIdProperty = MutableProperty<Int?>(nil)
    let processingState = PledgeProcessingState()

    let createIdentity = self.createIdentity
    let createBackingEvents: Signal<Signal<StripeSCARequiring, ErrorEnvelope>.Event, Never> = self.createEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [feature, createIdentity] _, userID, generation, id in
        guard createIdentity.id == id else { return false }
        guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else {
          createIdentity.id = UUID()
          processingState.setHidden(true)
          return false
        }
        return true
      }
      .map { event, _, _, _ in
        switch event {
        case let .value(envelope):
          checkoutIdProperty.value = decompose(id: envelope.createBacking.checkout.id)
          return .value(envelope as StripeSCARequiring)
        case let .failed(error):
          processingState.setHidden(true)
          return .failed(error)
        case .completed:
          processingState.setHidden(true)
          return .completed
        case .interrupted:
          processingState.setHidden(true)
          return .interrupted
        }
      }

    // MARK: - Update Backing

    let updateBackingData = updateDataPipe.output

    let willUpdateApplePayBacking = Signal.combineLatest(
      applePayStatusSuccess,
      context
    )
    .map { $1.isUpdating }
    .filter(isTrue)

    let updateIdentity = self.updateIdentity
    let updateBackingEvents: Signal<Signal<StripeSCARequiring, ErrorEnvelope>.Event, Never> = self.updateEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [feature, updateIdentity] _, userID, generation, id in
        guard updateIdentity.id == id else { return false }
        guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else {
          updateIdentity.id = UUID()
          processingState.setHidden(true)
          return false
        }
        return true
      }
      .map { event, _, _, _ in
        switch event {
        case let .value(envelope): return .value(envelope as StripeSCARequiring)
        case let .failed(error):
          processingState.setHidden(true)
          return .failed(error)
        case .completed:
          processingState.setHidden(true)
          return .completed
        case .interrupted:
          processingState.setHidden(true)
          return .interrupted
        }
      }

    let createOrUpdateEvent = Signal.merge(
      createBackingEvents,
      updateBackingEvents
    )


    // MARK: - Form Validation

    let valuesChangedAndValid = Signal.combineLatest(
      self.paymentValidPipe.output,
      self.planLoadingPipe.output,
      context
    )
    .map(allValuesChangedAndValid)

    let didCreateOrUpdateBacking = createOrUpdateEvent.filter { $0.isTerminating }

    let isEnabled = Signal.merge(
      self.viewDidLoadEvents.output.mapConst(false)
        .take(until: valuesChangedAndValid.ignoreValues()),
      valuesChangedAndValid,
      self.submitButtonTappedSignal.mapConst(false),
      valuesChangedAndValid.takeWhen(didCreateOrUpdateBacking)
    )
    .skipRepeats()

    let isCreateOrUpdateBacking = Signal.merge(
      self.submitButtonTappedSignal.mapConst(true),
      Signal.merge(willUpdateApplePayBacking, willCreateApplePayBacking).mapConst(false)
    )

    // MARK: - Success/Failure

    let scaFlowCompletedWithError = self.scaFlowCompletedWithResultSignal
      .filter { $0.0.status == .failed }
      .map(second)
      .skipNil()

    let scaFlowCompletedWithSuccess = self.scaFlowCompletedWithResultSignal
      .filter { $0.0.status == .succeeded }
      .map(first)
      .ignoreValues()

    let didInitiateApplePayBacking = Signal.merge(
      willCreateApplePayBacking,
      willUpdateApplePayBacking
    )

    let paymentAuthorizationDidFinish = didInitiateApplePayBacking
      .takeWhen(self.paymentAuthorizationDidFinishSignal)

    let createOrUpdateApplePayBackingCompleted = Signal.zip(
      didInitiateApplePayBacking,
      createOrUpdateEvent.filter { $0.isTerminating }.ignoreValues(),
      paymentAuthorizationDidFinish
    )

    let valuesOrNil = Signal.merge(
      createOrUpdateEvent.values().wrapInOptional(),
      isCreateOrUpdateBacking.mapConst(nil)
    )

    let createOrUpdateBackingEventValuesNoSCA = valuesOrNil
      .skipNil()
      .filter(requiresSCA >>> isFalse)

    let createOrUpdateBackingDidCompleteNoSCA = isCreateOrUpdateBacking
      .takeWhen(createOrUpdateBackingEventValuesNoSCA)
      .filter(isTrue)
      .ignoreValues()

    let createOrUpdateBackingEventValuesRequiresSCA = valuesOrNil
      .skipNil()
      .filter(requiresSCA)

    let beginSCAFlowWithClientSecret: Signal<String, Never> = createOrUpdateBackingEventValuesRequiresSCA
      .map { $0.clientSecret }
      .skipNil()

    let didCompleteApplePayBacking = valuesOrNil
      .takeWhen(createOrUpdateApplePayBackingCompleted)
      .skipNil()

    let creatingContext = context.filter { $0.isCreating }

    let createBackingCompletionEvents = Signal.merge(
      didCompleteApplePayBacking.combineLatest(with: willCreateApplePayBacking).ignoreValues(),
      createOrUpdateBackingDidCompleteNoSCA.combineLatest(with: creatingContext).ignoreValues(),
      scaFlowCompletedWithSuccess.combineLatest(with: creatingContext).ignoreValues()
    )

    let thanksPageData = Signal.combineLatest(
      createBackingDataAndIsApplePay,
      checkoutIdProperty.signal,
      baseReward,
      additionalPledgeAmount,
      allRewardsShippingTotal
    )
    .map { dataAndIsApplePay, checkoutId, baseReward, additionalPledgeAmount, shippingTotal
      -> (CreateBackingData, Bool, String?, Reward, Double, Double) in
      let (data, isApplePay) = dataAndIsApplePay
      guard let checkoutId = checkoutId else {
        return (
          data,
          isApplePay,
          nil,
          baseReward,
          additionalPledgeAmount,
          shippingTotal
        )
      }
      return (
        data,
        isApplePay,
        String(checkoutId),
        baseReward,
        additionalPledgeAmount,
        shippingTotal
      )
    }
    .map { data, isApplePay, checkoutId, baseReward, additionalPledgeAmount, shippingTotal
      -> ThanksPageData? in
      let checkoutPropsData = checkoutProperties(
        from: data.project,
        baseReward: baseReward,
        addOnRewards: data.rewards,
        selectedQuantities: data.selectedQuantities,
        additionalPledgeAmount: additionalPledgeAmount,
        pledgeTotal: data.pledgeTotal,
        shippingTotal: shippingTotal,
        checkoutId: checkoutId,
        isApplePay: isApplePay
      )

      return (data.project, baseReward, checkoutPropsData, data.pledgeTotal)
    }
    .skipNil()

    let goToThanks: Signal<ThanksPageData, Never> = thanksPageData
      .takeWhen(createBackingCompletionEvents)

    let errorsOrNil = Signal.merge(
      createOrUpdateEvent.errors().wrapInOptional(),
      isCreateOrUpdateBacking.mapConst(nil)
    )

    let createOrUpdateApplePayBackingError = createOrUpdateApplePayBackingCompleted
      .withLatest(from: errorsOrNil)
      .map(second)
      .skipNil()

    let createOrUpdateBackingError = isCreateOrUpdateBacking
      .takePairWhen(errorsOrNil.skipNil())
      .filter(first >>> isTrue)
      .map(second)

    let updatingContext = context.filter { $0.isUpdating }

    let updateBackingCompletionEvents = Signal.merge(
      didCompleteApplePayBacking.combineLatest(with: willUpdateApplePayBacking).ignoreValues(),
      createOrUpdateBackingDidCompleteNoSCA.combineLatest(with: updatingContext).ignoreValues(),
      scaFlowCompletedWithSuccess.combineLatest(with: updatingContext).ignoreValues()
    )

    let graphErrors = Signal.merge(
      createOrUpdateApplePayBackingError,
      createOrUpdateBackingError
    )
    .map { $0.localizedDescription }

    let scaErrors = scaFlowCompletedWithError.map { $0.localizedDescription }

    let errorMessages = Signal.merge(
      graphErrors,
      scaErrors
    )

    let willRetryPaymentMethod = Signal.combineLatest(
      context,
      project,
      self.paymentSelectedPipe.output
    )
    .map { context, project, selectedPaymentSource -> Bool in

      context == .fixPaymentMethod
        && project.personalization.backing?.paymentSource?.id == selectedPaymentSource?.savedCreditCardId
    }
    .skipRepeats()

    let pledgeCTA: Signal<PledgeViewCTAContainerViewData, Never> = Signal.combineLatest(
      project,
      pledgeTotal.skipRepeats(),
      self.loginStatePipe.output,
      isEnabled,
      context,
      willRetryPaymentMethod
    )
    .map { $0 as PledgeViewCTAContainerViewData }

    _ = createBackingData.observeValues { [weak self] in self?.latestCreateBackingData = $0 }
    _ = updateBackingData.observeValues { [weak self] in self?.latestUpdateBackingData = $0 }
    _ = initialData.observeValues { [weak self] data in
      self?.onTitle?(data.context.title)
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
    _ = pledgeCTA.observeValues { [weak self] in self?.onPledgeCTA?($0) }
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
          self?.createEvents.input.send(value: (.value(result), userID, generation, id))
          self?.createEvents.input.send(value: (.completed, userID, generation, id))
        } catch {
          if Task.isCancelled || error is CancellationError {
            if self?.createIdentity.id == id { processingState.setHidden(true) }
            return
          }
          self?.createEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
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
          self?.updateEvents.input.send(value: (.value(result), userID, generation, id))
          self?.updateEvents.input.send(value: (.completed, userID, generation, id))
        } catch {
          if Task.isCancelled || error is CancellationError {
            if self?.updateIdentity.id == id { processingState.setHidden(true) }
            return
          }
          self?.updateEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
        }
      }
    }
    _ = updateBackingCompletionEvents.observeValues { [weak self] in
      self?.onPledgeUpdateSucceeded?(Strings.Got_it_your_changes_have_been_saved())
    }
    _ = errorMessages.observeValues { [weak self] in self?.onShowError?($0) }
    _ = beginSCAFlowWithClientSecret.observeValues { [weak self] in self?.onBeginSCA?($0) }
    _ = goToThanks.observeValues { [weak self] in self?.onGoToThanks?($0) }
    self.applePayAuthorization.onSuccess = { [weak self] in
      applePaySuccess.input.send(value: ())
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

  private let (applePayButtonTappedSignal, applePayButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func applePayButtonTapped() {
    guard self.hasLoadedView, let data = self.configuredData, let reward = data.rewards.first else {
      self.applePayButtonTappedObserver.send(value: ())
      return
    }
    let amounts = PledgeAmounts(data)
    self.applePayButtonTappedObserver.send(value: ())
    self.trackPledgeSubmission(isApplePay: true)
    self.onApplePayAuthorization?((data.project, reward, amounts.rewards, amounts.bonus, amounts.shipping,
                                   Secrets.ApplePay.merchantIdentifier))
  }

  private var configuredData: PledgeViewData?
  private var latestCreateBackingData: CreateBackingData?
  private var latestUpdateBackingData: UpdateBackingData?
  private var hasLoadedView = false
  private let initialDataEvents = Signal<PledgeViewData, Never>.pipe()
  private let viewDidLoadEvents = Signal<Void, Never>.pipe()

  public func configure(with data: PledgeViewData) {
    self.configuredData = data
    self.publishInitialDataWhenReady()
  }

  private func publishInitialDataWhenReady() {
    guard self.hasLoadedView, let data = self.configuredData else { return }
    self.initialDataEvents.input.send(value: data)
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
  private let applePaySuccessPipe = Signal<Void, Never>.pipe()
  public func paymentAuthorizationDidAuthorizePayment(paymentData: (
    displayName: String?, network: String?, transactionIdentifier: String
  )) {
    self.applePayAuthorization.authorized(paymentData)
  }

  private let (paymentAuthorizationDidFinishSignal, paymentAuthorizationDidFinishObserver)
    = Signal<Void, Never>.pipe()
  public func paymentAuthorizationViewControllerDidFinish() {
    self.paymentAuthorizationDidFinishObserver.send(value: ())
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

  private let (scaFlowCompletedWithResultSignal, scaFlowCompletedWithResultObserver)
    = Signal<(StripePaymentHandlerActionStatusType, Error?), Never>.pipe()
  public func scaFlowCompleted(with result: StripePaymentHandlerActionStatusType, error: Error?) {
    self.scaFlowCompletedWithResultObserver.send(value: (result, error))
  }

  private let (submitButtonTappedSignal, submitButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func submitButtonTapped() {
    self.submitButtonTappedObserver.send(value: ())
    self.startBacking(isApplePay: false)
    self.trackPledgeSubmission(isApplePay: false)
  }

  private func startBacking(isApplePay: Bool) {
    guard self.hasLoadedView, let context = self.configuredData?.context else { return }
    if context.isCreating, let data = self.latestCreateBackingData {
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
    self.viewDidLoadEvents.input.send(value: ())
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

  private let createEvents = Signal<(Signal<CreateBackingEnvelope, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let createIdentity = PledgeWriteIdentity()
  private var startCreate: ((CreateBackingData, Bool) -> Void)?
  private var createTask: Task<Void, Never>?

  private let updateEvents = Signal<(Signal<UpdateBackingEnvelope, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let updateIdentity = PledgeWriteIdentity()
  private var startUpdate: ((UpdateBackingData, Bool) -> Void)?
  private var updateTask: Task<Void, Never>?

  deinit {
    self.updateTask?.cancel()
    self.createTask?.cancel()
  }

  private let pledgeOverTimeUseCase: PledgeOverTimeUseCase
  private let planLoadingPipe = Signal<Bool, Never>.pipe()
  private let loginSignupUseCase: LoginSignupUseCase
  private let loginStatePipe = Signal<Bool, Never>.pipe()
  private let paymentMethodsUseCase: PaymentMethodsUseCase
  private let paymentSelectedPipe = Signal<PaymentSourceSelected?, Never>.pipe()
  private let paymentValidPipe = Signal<Bool, Never>.pipe()
}

// MARK: - Functions

private func requiresSCA(_ envelope: StripeSCARequiring) -> Bool {
  return envelope.requiresSCAFlow
}

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

private func allValuesChangedAndValid(
  paymentSourceValid: Bool,
  pledgeOverTimeIsLoading: Bool,
  context _: PledgeViewContext
) -> Bool {
  return paymentSourceValid && !pledgeOverTimeIsLoading
}

// MARK: - Helper Functions

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
