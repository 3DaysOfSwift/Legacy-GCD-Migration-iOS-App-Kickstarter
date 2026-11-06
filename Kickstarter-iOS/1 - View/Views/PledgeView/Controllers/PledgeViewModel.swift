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
  var beginSCAFlowWithClientSecret: Signal<String, Never> { get }
  var configureEstimatedShippingView: Signal<(String?, String?), Never> { get }
  var configureLocalPickupViewWithData: Signal<PledgeLocalPickupViewData, Never> { get }
  var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)? { get set }
  var configurePledgeAmountSummaryViewControllerWithData: Signal<PledgeAmountSummaryViewData, Never> { get }
  var configurePledgeRewardsSummaryViewWithData: Signal<
    (PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData),
    Never
  > { get }
  var configurePledgeViewCTAContainerView: Signal<PledgeViewCTAContainerViewData, Never> { get }
  var configureStripeIntegration: Signal<StripeConfigurationData, Never> { get }
  var descriptionSectionSeparatorHidden: Signal<Bool, Never> { get }
  var estimatedShippingViewHidden: Signal<Bool, Never> { get }
  var goToApplePayPaymentAuthorization: Signal<PaymentAuthorizationData, Never> { get }
  var goToThanks: Signal<ThanksPageData, Never> { get }
  var onGoToLoginSignup: ((LoginIntent) -> Void)? { get set }
  var localPickupViewHidden: Signal<Bool, Never> { get }
  var notifyDelegateUpdatePledgeDidSucceedWithMessage: Signal<String, Never> { get }
  var onPaymentMethodsHidden: ((Bool) -> Void)? { get set }
  var pledgeAmountSummaryViewHidden: Signal<Bool, Never> { get }
  var popToRootViewController: Signal<(), Never> { get }
  var processingViewIsHidden: Signal<Bool, Never> { get }
  var showErrorBannerWithMessage: Signal<String, Never> { get }
  var onShowWebHelp: ((HelpType) -> Void)? { get set }
  var title: Signal<String, Never> { get }
  var showPledgeOverTimeUI: Signal<Bool, Never> { get }
  var pledgeOverTimeConfigData: Signal<PledgePaymentPlansAndSelectionData?, Never> { get }
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
    let initialData = Signal.combineLatest(
      self.configureWithDataProperty.signal,
      self.viewDidLoadProperty.signal
    )
    .map(first)
    .skipNil()

    let project = initialData.map(\.project)
    let baseReward = initialData.map(\.rewards).map(\.first).skipNil()
    let rewards = initialData.map(\.rewards)
    let selectedQuantities = initialData.map(\.selectedQuantities)
    let selectedLocationId = initialData.map(\.selectedLocationId)
    let selectedShippingRule = initialData.map(\.selectedShippingRule)
    let refTag = initialData.map(\.refTag)
    let context = initialData.map(\.context)

    let initialDataUnpacked = Signal.zip(project, baseReward, refTag, context)

    let backing = project.map { $0.personalization.backing }.skipNil()

    self.pledgeAmountSummaryViewHidden = context.map { $0.pledgeAmountSummaryViewHidden }

    self.loginSignupUseCase = LoginSignupUseCase(withLoginIntent: .backProject)
    let login = self.loginSignupUseCase
    let loginState = self.loginStatePipe
    let loginSession = self.loginSessionPipe
    login.onLoginState = { loginState.input.send(value: $0) }
    login.onSessionChanged = { loginSession.input.send(value: ()) }
    initialData.observeValues { _ in login.initialDataAvailable() }

    self.paymentMethodsUseCase = PaymentMethodsUseCase()
    let paymentMethods = self.paymentMethodsUseCase
    let paymentSelected = self.paymentSelectedPipe
    let paymentValid = self.paymentValidPipe
    paymentMethods.onSelected = { paymentSelected.input.send(value: $0) }
    paymentMethods.onValidity = { paymentValid.input.send(value: $0) }
    initialData.observeValues { paymentMethods.configure($0) }
    self.loginStatePipe.output.observeValues { paymentMethods.loginChanged($0) }

    self.descriptionSectionSeparatorHidden = Signal.combineLatest(context, baseReward)
      .map { context, reward in
        if context.isAny(of: .pledge, .updateReward) {
          return reward.isNoReward == false
        }

        return context.sectionSeparatorsHidden
      }

    let allRewardsTotal = Signal.combineLatest(
      project, rewards, selectedQuantities, context
    )
    .map { project, rewards, selectedQuantities, context in
      if context == .fixPaymentMethod,
         let rewardsAmount = project.personalization.backing?.rewardsAmount {
        return rewardsAmount
      }
      return calculateAllRewardsTotal(addOnRewards: rewards, selectedQuantities: selectedQuantities)
    }

    let initialShippingTotal = project.map { project in
      guard let backing = project.personalization.backing else {
        return 0.0
      }
      return backing.shippingAmount ?? 0.0
    }

    let calculatedShippingTotal = Signal.combineLatest(
      selectedShippingRule.skipNil(),
      rewards,
      selectedQuantities
    )
    .map(calculateShippingTotal)

    let allRewardsShippingTotal = Signal.merge(
      initialShippingTotal,
      calculatedShippingTotal
    )

    // Initial pledge amount is zero if not backed and not set previously in the flow.
    let additionalPledgeAmount = initialData.map {
      if let bonusSupport = $0.bonusSupport {
        return bonusSupport
      } else if let backing = $0.project.personalization.backing {
        return backing.bonusAmount
      } else {
        return 0.0
      }
    }

    let projectAndReward = Signal.zip(project, baseReward)

    /**
     Shipping location selector is hidden if the context hides it,
     if the base reward has no shipping, when add-ons were selected or when base reward has local pickup option.
     */
    let nonLocalPickupShippingLocationViewHidden = Signal.combineLatest(baseReward, rewards, context)
      .map { baseReward, rewards, context in
        [
          context.shippingLocationViewHidden,
          !baseReward.shipping.enabled,
          rewards.count > 1
        ].contains(true)
      }

    /**
     if the base reward has no shipping, when NO add-ons were selected or when base reward has local pickup option.
     */
    let nonLocalPickupShippingSummaryViewHidden = Signal.combineLatest(baseReward, rewards, context)
      .map { baseReward, rewards, context in
        [
          context.isAny(of: .changePaymentMethod, .fixPaymentMethod),
          !baseReward.shipping.enabled,
          rewards.count == 1
        ].contains(true)
      }

    let shippingViewsHiddenConditionsForPledgeAmountSummary: Signal<Bool, Never> = Signal
      .combineLatest(
        nonLocalPickupShippingLocationViewHidden,
        nonLocalPickupShippingSummaryViewHidden
      )
      .map { a, b -> Bool in
        let r = a && b
        return r
      }

    self.localPickupViewHidden = baseReward.map(isRewardLocalPickup).negate()

    self.configureLocalPickupViewWithData = projectAndReward
      .switchMap { projectAndReward -> SignalProducer<PledgeLocalPickupViewData?, Never> in
        guard let locationName = projectAndReward.1.localPickup?.displayableName else {
          return SignalProducer(value: nil)
        }

        let localPickupLocationData = PledgeLocalPickupViewData(locationName: locationName)

        return SignalProducer(value: localPickupLocationData)
      }
      .skipNil()

    /**
     * The total pledge amount that will be used to create the backing.
     * For a regular reward this includes the bonus support amount,
     * the total of all rewards
     * For No Reward this is only the pledge amount.
     * Never calculate the pledge total in a fix payment method context.
     */
    let calculatedPledgeTotal = Signal.combineLatest(
      additionalPledgeAmount,
      allRewardsShippingTotal,
      allRewardsTotal,
      context
    )
    .filter { _, _, _, context in context != .fixPaymentMethod }
    .map { additionalPledgeAmount, allRewardsShippingTotal, allRewardsTotal, _ in
      calculatePledgeTotal(
        pledgeAmount: additionalPledgeAmount,
        shippingCost: allRewardsShippingTotal,
        addOnRewardsTotal: allRewardsTotal
      )
    }

    let pledgeTotal = Signal.merge(
      backing.map(\.amount),
      calculatedPledgeTotal
    )

    let projectAndConfirmationLabelHidden = Signal.combineLatest(
      project,
      context.map { $0.confirmationLabelHidden }
    )

    // The selected shipping rule, if present, is always the most up-to-date shipping information.
    // If not present, get shipping location from the backing instead.
    let shippingLocation: Signal<String?, Never> = Signal.combineLatest(project, selectedShippingRule)
      .map { project, shippingRule in
        if let shippingRule {
          return shippingRule.location.localizedName
        }
        if let backing = project.personalization.backing {
          return backing.locationName
        }
        return nil
      }

    let shippingSummaryViewDataNonnil = Signal.combineLatest(
      shippingLocation.skipNil(),
      project.map { $0.stats.omitUSCurrencyCode },
      project.map { $0.stats.projectCurrency },
      allRewardsShippingTotal
    )
    .map(PledgeShippingSummaryViewData.init)

    let shippingSummaryViewData = Signal.merge(
      shippingSummaryViewDataNonnil.wrapInOptional(),
      shippingLocation.filter(isNil).mapConst(nil)
    )

    self.configurePledgeRewardsSummaryViewWithData = Signal.combineLatest(
      initialData,
      pledgeTotal,
      additionalPledgeAmount,
      shippingSummaryViewData,
      rewards
    )
    .compactMap { data, pledgeTotal, additionalPledgeAmount, shipping, rewards in
      // This view controller isn't currently used for late pledges and fix payment method should
      // only happen for crowdfunding pledges, but calculating this just in case.
      let isLatePledge = data.context == .latePledge ||
        (
          data.context == .fixPaymentMethod &&
            data.project.personalization.backing?.isLatePledge == true
        )

      let rewardsData = PostCampaignRewardsSummaryViewData(
        rewards: data.rewards,
        selectedQuantities: data.selectedQuantities,
        currencyCode: data.project.statsCurrency,
        omitCurrencyCode: data.project.stats.omitUSCurrencyCode,
        shipping: shipping,
        useLatePledgeCosts: isLatePledge
      )
      let pledgeData = PledgeSummaryViewData(
        project: data.project,
        total: pledgeTotal,
        confirmationLabelHidden: false,
        pledgeHasNoReward: pledgeHasNoRewards(rewards: rewards)
      )
      return (rewardsData, additionalPledgeAmount, pledgeData)
    }

    self.configurePledgeAmountSummaryViewControllerWithData = Signal.combineLatest(
      projectAndReward,
      allRewardsTotal,
      additionalPledgeAmount,
      shippingViewsHiddenConditionsForPledgeAmountSummary
    )
    .map { projectAndReward, allRewardsTotal, amount, shippingViewsHidden in
      (projectAndReward.0, projectAndReward.1, allRewardsTotal, amount, shippingViewsHidden)
    }
    .map(pledgeAmountSummaryViewData)
    .skipNil()

    let configurePaymentMethodsViewController = Signal.merge(
      initialDataUnpacked,
      initialDataUnpacked.takeWhen(self.loginSessionPipe.output)
    )

    self.configureStripeIntegration = Signal.combineLatest(
      initialData,
      context
    )
    .filter { !$1.paymentMethodsViewHidden }
    .ignoreValues()
    .map { _ in
      (
        Secrets.ApplePay.merchantIdentifier,
        AppEnvironment.current.environmentType.stripePublishableKey
      )
    }

    self.configureEstimatedShippingView = Signal.combineLatest(
      project,
      rewards,
      selectedShippingRule,
      selectedQuantities
    )
    .map { project, rewards, shippingRule, selectedQuantities in
      guard let rule = shippingRule else { return (nil, nil) }

      return (
        estimatedShippingText(
          for: rewards,
          project: project,
          locationId: rule.location.id,
          selectedQuantities: selectedQuantities
        ),
        estimatedShippingConversionText(
          for: rewards,
          project: project,
          locationId: rule.location.id,
          selectedQuantities: selectedQuantities
        )
      )
    }

    self.estimatedShippingViewHidden = Signal.combineLatest(self.configureEstimatedShippingView, baseReward)
      .map { estimatedShippingStrings, reward in
        let (estimatedShipping, _) = estimatedShippingStrings
        return reward.shipping.enabled == false || estimatedShipping == nil
      }

    // MARK: - Apple Pay

    let changingApplePayPaymentMethod = self.applePayButtonTappedSignal
      .combineLatest(with: context)
      .map(second)
      .filter { $0 == .changePaymentMethod }
      .ignoreValues()

    let paymentAuthorizationData: Signal<PaymentAuthorizationData, Never> = Signal.combineLatest(
      project,
      baseReward,
      allRewardsTotal,
      additionalPledgeAmount,
      allRewardsShippingTotal
    )
    .map { project, reward, allRewardsTotal, additionalPledgeAmount, shippingTotal -> PaymentAuthorizationData in
      let r = (
        project,
        reward,
        allRewardsTotal,
        additionalPledgeAmount,
        shippingTotal,
        Secrets.ApplePay.merchantIdentifier
      ) as PaymentAuthorizationData

      return r
    }

    self.goToApplePayPaymentAuthorization = paymentAuthorizationData
      .takeWhen(self.applePayButtonTappedSignal)

    let applePayStatusSuccess = self.applePaySuccessPipe.output
    let willCreateApplePayBacking = applePayStatusSuccess
      .combineLatest(with: context)
      .map { $1.isCreating }
      .filter(isTrue)
    let applePayParamsData = Signal.merge(
      initialData.mapConst(nil),
      self.applePayParamsPipe.output.wrapInOptional()
    )
    let applePaySuccess = self.applePaySuccessPipe
    let applePayParams = self.applePayParamsPipe
    self.applePayAuthorization.onSuccess = { applePaySuccess.input.send(value: ()) }
    self.applePayAuthorization.onParams = { applePayParams.input.send(value: $0) }

    // MARK: Pledge Over Time

    self.pledgeOverTimeUseCase = PledgeOverTimeUseCase(feature: feature)
    let planUseCase = self.pledgeOverTimeUseCase
    let planShow = self.planShowPipe
    let planConfig = self.planConfigPipe
    let planLoading = self.planLoadingPipe
    planUseCase.onShow = { planShow.input.send(value: $0) }
    planUseCase.onConfig = { planConfig.input.send(value: $0) }
    planUseCase.onLoading = { planLoading.input.send(value: $0) }
    project.observeValues { planUseCase.updateProject($0) }
    pledgeTotal.observeValues { planUseCase.updateTotal($0) }
    context.observeValues { planUseCase.updateContext($0) }

    // MARK: - Create Backing

    let selectedPaymentPlan = self.planConfigPipe.output
      .map { $0?.selectedPlan ?? .pledgeInFull }

    let createBackingData = Signal.combineLatest(
      project,
      rewards,
      pledgeTotal,
      selectedQuantities,
      selectedShippingRule,
      self.paymentSelectedPipe.output,
      applePayParamsData,
      selectedPaymentPlan,
      refTag
    )
    .map {
      project,
        rewards,
        pledgeTotal,
        selectedQuantities,
        selectedShippingRule,
        selectedPaymentSource,
        applePayParams,
        selectedPaymentPlan,
        refTag
        -> CreateBackingData in

      let paymentSourceId = selectedPaymentSource?.savedCreditCardId

      return (
        project: project,
        rewards: rewards,
        pledgeTotal: pledgeTotal,
        selectedQuantities: selectedQuantities,
        shippingRule: selectedShippingRule,
        paymentSourceId: paymentSourceId,
        setupIntentClientSecret: nil,
        applePayParams: applePayParams,
        refTag: refTag,
        incremental: selectedPaymentPlan == .pledgeOverTime
      )
    }

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
    let processingViewIsHidden = MutableProperty<Bool>(true)

    let createBackingEvents = createBackingDataAndIsApplePay
      .map(CreateBackingInput.input(from:isApplePay:))
      .switchMap { [checkoutIdProperty] input in
        feature.delayedResult(feature.createResult(input))
          .on(
            starting: {
              processingViewIsHidden.value = false
            },
            terminated: {
              processingViewIsHidden.value = true
            }
          )
          .map { envelope -> StripeSCARequiring in
            checkoutIdProperty.value = decompose(id: envelope.createBacking.checkout.id)
            return envelope as StripeSCARequiring
          }
          .materialize()
      }

    // MARK: - Update Backing

    let updateBackingData = Signal.combineLatest(
      backing,
      rewards,
      pledgeTotal,
      selectedQuantities,
      selectedShippingRule,
      self.paymentSelectedPipe.output,
      applePayParamsData,
      context,
      selectedPaymentPlan
    )
    .map {
      backing,
        rewards,
        pledgeTotal,
        selectedQuantities,
        selectedShippingRule,
        selectedPaymentSource,
        applePayParams,
        context,
        selectedPaymentPlan
        -> UpdateBackingData in
      let paymentSourceId = selectedPaymentSource?.savedCreditCardId

      return (
        backing: backing,
        rewards: rewards,
        pledgeTotal: pledgeTotal,
        selectedQuantities: selectedQuantities,
        shippingRule: selectedShippingRule,
        paymentSourceId: paymentSourceId,
        setupIntentClientSecret: nil,
        applePayParams: applePayParams,
        context,
        incremental: selectedPaymentPlan == .pledgeOverTime
      )
    }

    let willUpdateApplePayBacking = Signal.combineLatest(
      applePayStatusSuccess,
      context
    )
    .map { $1.isUpdating }
    .filter(isTrue)

    let updateButtonTapped = context
      .takeWhen(self.submitButtonTappedSignal)
      .filter { context in context.isUpdating }
      .ignoreValues()

    let updateBackingDataAndIsApplePay = updateBackingData.takePairWhen(
      Signal.merge(
        updateButtonTapped.mapConst(false),
        willUpdateApplePayBacking
      )
    )

    let updateBackingEvents = updateBackingDataAndIsApplePay
      .map(UpdateBackingInput.input(from:isApplePay:))
      .switchMap { input in
        feature.delayedResult(feature.updateResult(input))
          .on(
            starting: {
              processingViewIsHidden.value = false
            },
            terminated: {
              processingViewIsHidden.value = true
            }
          )
          .map { $0 as StripeSCARequiring }
          .materialize()
      }

    let createOrUpdateEvent = Signal.merge(
      createBackingEvents,
      updateBackingEvents
    )

    self.processingViewIsHidden = processingViewIsHidden.signal

    // MARK: - Form Validation

    let valuesChangedAndValid = Signal.combineLatest(
      self.paymentValidPipe.output,
      self.planLoadingPipe.output,
      context
    )
    .map(allValuesChangedAndValid)

    let didCreateOrUpdateBacking = createOrUpdateEvent.filter { $0.isTerminating }

    let isEnabled = Signal.merge(
      self.viewDidLoadProperty.signal.mapConst(false)
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

    self.beginSCAFlowWithClientSecret = createOrUpdateBackingEventValuesRequiresSCA
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

    self.goToThanks = thanksPageData
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

    self.notifyDelegateUpdatePledgeDidSucceedWithMessage = updateBackingCompletionEvents
      .mapConst(Strings.Got_it_your_changes_have_been_saved())

    let graphErrors = Signal.merge(
      createOrUpdateApplePayBackingError,
      createOrUpdateBackingError
    )
    .map { $0.localizedDescription }

    let scaErrors = scaFlowCompletedWithError.map { $0.localizedDescription }

    self.showErrorBannerWithMessage = Signal.merge(
      graphErrors,
      scaErrors
    )

    self.popToRootViewController = self.notifyDelegateUpdatePledgeDidSucceedWithMessage.ignoreValues()

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

    self.configurePledgeViewCTAContainerView = Signal.combineLatest(
      project,
      pledgeTotal.skipRepeats(),
      self.loginStatePipe.output,
      isEnabled,
      context,
      willRetryPaymentMethod
    )
    .map { $0 as PledgeViewCTAContainerViewData }

    self.title = context.map { $0.title }

    let trackCheckoutPageViewData = Signal.zip(
      project,
      baseReward,
      rewards,
      selectedQuantities,
      refTag,
      additionalPledgeAmount,
      pledgeTotal,
      context
    )

    // MARK: - Tracking

    trackCheckoutPageViewData
      .observeValues { project, baseReward, rewards, selectedQuantities, refTag, additionalPledgeAmount, pledgeTotal, pledgeViewContext in
        let checkoutData = checkoutProperties(
          from: project,
          baseReward: baseReward,
          addOnRewards: rewards,
          selectedQuantities: selectedQuantities,
          additionalPledgeAmount: additionalPledgeAmount,
          pledgeTotal: pledgeTotal,
          shippingTotal: 0,
          checkoutId: nil,
          isApplePay: false
        )

        AppEnvironment.current.ksrAnalytics.trackCheckoutPaymentPageViewed(
          project: project,
          reward: baseReward,
          pledgeViewContext: pledgeViewContext,
          checkoutData: checkoutData,
          refTag: refTag
        )
      }

    let pledgeSubmitEventsSignal = Signal.combineLatest(
      createBackingData,
      baseReward,
      additionalPledgeAmount
    )

    // Pledge pledge_submit event
    pledgeSubmitEventsSignal
      .takeWhen(self.submitButtonTappedSignal)
      .map { data, baseReward, additionalPledgeAmount in
        let checkoutData = checkoutProperties(
          from: data.project,
          baseReward: baseReward,
          addOnRewards: data.rewards,
          selectedQuantities: data.selectedQuantities,
          additionalPledgeAmount: additionalPledgeAmount,
          pledgeTotal: data.pledgeTotal,
          shippingTotal: 0,
          checkoutId: nil,
          isApplePay: false
        )

        return (data.project, baseReward, data.refTag, checkoutData)
      }
      .observeValues { project, reward, refTag, checkoutData in
        AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
          project: project,
          reward: reward,
          typeContext: .creditCard,
          checkoutData: checkoutData,
          refTag: refTag
        )
      }

    // Pay With Apple pledge_submit event
    pledgeSubmitEventsSignal
      .takeWhen(self.applePayButtonTappedSignal)
      .map { data, baseReward, additionalPledgeAmount in
        let checkoutData = checkoutProperties(
          from: data.project,
          baseReward: baseReward,
          addOnRewards: data.rewards,
          selectedQuantities: data.selectedQuantities,
          additionalPledgeAmount: additionalPledgeAmount,
          pledgeTotal: data.pledgeTotal,
          shippingTotal: 0,
          checkoutId: nil,
          isApplePay: true
        )

        return (data.project, baseReward, data.refTag, checkoutData)
      }
      .observeValues { project, reward, refTag, checkoutData in
        AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
          project: project,
          reward: reward,
          typeContext: .applePay,
          checkoutData: checkoutData,
          refTag: refTag
        )
      }
    login.onLogin = { [weak self] in self?.onGoToLoginSignup?($0) }
    paymentMethods.onHidden = { [weak self] in self?.onPaymentMethodsHidden?($0) }
    paymentMethods.onConfiguration = { [weak self] in self?.onConfigurePaymentMethods?($0) }
  }

  // MARK: - Inputs

  private let (applePayButtonTappedSignal, applePayButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func applePayButtonTapped() {
    self.applePayButtonTappedObserver.send(value: ())
  }

  private let configureWithDataProperty = MutableProperty<PledgeViewData?>(nil)
  public func configure(with data: PledgeViewData) {
    self.configureWithDataProperty.value = data
  }

  public func creditCardSelected(with paymentSourceData: PaymentSourceSelected) {
    self.paymentMethodsUseCase.creditCardSelected(with: paymentSourceData)
  }

  private let applePayAuthorization = ApplePayAuthorization()
  private let applePaySuccessPipe = Signal<Void, Never>.pipe()
  private let applePayParamsPipe = Signal<ApplePayParams, Never>.pipe()
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
  }

  public func stripeTokenCreated(token: String?, error: Error?) -> PKPaymentAuthorizationStatus {
    self.applePayAuthorization.tokenCreated(token: token, error: error)
  }

  public func termsOfUseTapped(with helpType: HelpType) {
    self.onShowWebHelp?(helpType)
  }

  private let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  public func userSessionDidChange() {
    self.loginSignupUseCase.userSessionDidChange()
  }

  // MARK: - Outputs

  public let beginSCAFlowWithClientSecret: Signal<String, Never>
  public let configureEstimatedShippingView: Signal<(String?, String?), Never>
  public let configureLocalPickupViewWithData: Signal<PledgeLocalPickupViewData, Never>
  public var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)?

  public let configurePledgeAmountSummaryViewControllerWithData: Signal<PledgeAmountSummaryViewData, Never>
  public let configurePledgeRewardsSummaryViewWithData: Signal<
    (PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData),
    Never
  >
  public let configurePledgeViewCTAContainerView: Signal<PledgeViewCTAContainerViewData, Never>
  public let configureStripeIntegration: Signal<StripeConfigurationData, Never>
  public let descriptionSectionSeparatorHidden: Signal<Bool, Never>
  public let estimatedShippingViewHidden: Signal<Bool, Never>
  public let goToApplePayPaymentAuthorization: Signal<PaymentAuthorizationData, Never>
  public let goToThanks: Signal<ThanksPageData, Never>
  public var onGoToLoginSignup: ((LoginIntent) -> Void)?

  public let localPickupViewHidden: Signal<Bool, Never>
  public let notifyDelegateUpdatePledgeDidSucceedWithMessage: Signal<String, Never>
  public var onPaymentMethodsHidden: ((Bool) -> Void)?

  public let pledgeAmountSummaryViewHidden: Signal<Bool, Never>
  public let popToRootViewController: Signal<(), Never>
  public let processingViewIsHidden: Signal<Bool, Never>
  public let showErrorBannerWithMessage: Signal<String, Never>
  public var onShowWebHelp: ((HelpType) -> Void)?
  public let title: Signal<String, Never>

  public var showPledgeOverTimeUI: Signal<Bool, Never> {
    return self.planShowPipe.output
  }

  public var pledgeOverTimeConfigData: Signal<PledgePaymentPlansAndSelectionData?, Never> {
    return self.planConfigPipe.output
  }

  public var inputs: PledgeViewModelInputs { return self }
  public var outputs: PledgeViewModelOutputs { return self }

  // MARK: - Use cases

  private let pledgeOverTimeUseCase: PledgeOverTimeUseCase
  private let planShowPipe = Signal<Bool, Never>.pipe()
  private let planLoadingPipe = Signal<Bool, Never>.pipe()
  private let planConfigPipe = Signal<PledgePaymentPlansAndSelectionData?, Never>.pipe()
  private let loginSignupUseCase: LoginSignupUseCase
  private let loginStatePipe = Signal<Bool, Never>.pipe()
  private let loginSessionPipe = Signal<Void, Never>.pipe()
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
