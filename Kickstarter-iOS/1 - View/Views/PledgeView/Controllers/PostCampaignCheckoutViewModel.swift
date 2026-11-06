import Foundation
import GraphAPI
import KsApi
import PassKit
import Prelude
import ReactiveSwift
import Stripe

public struct PostCampaignCheckoutData: Equatable {
  public let project: Project
  public let baseReward: Reward
  public let rewards: [Reward]
  public let selectedQuantities: SelectedRewardQuantities
  public let bonusAmount: Double?
  public let total: Double
  public let shipping: PledgeShippingSummaryViewData?
  public let refTag: RefTag?
  public let context: PledgeViewContext
  public let checkoutId: String
  public let backingId: String
  public let selectedShippingRule: ShippingRule?
}

public struct PaymentSourceValidation {
  public let paymentIntentClientSecret: String
  public let selectedCardStripeCardId: String?
  public let requiresConfirmation: Bool
}

public struct PostCampaignPaymentAuthorizationData: Equatable {
  public let project: Project
  public let hasNoReward: Bool
  public let subtotal: Double
  public let bonus: Double
  public let shipping: Double
  public let total: Double
  public let merchantIdentifier: String
  public let paymentIntent: String
}

@MainActor
public protocol PostCampaignCheckoutViewModelInputs {
  func checkoutTerminated()
  func configure(with data: PledgeViewData)
  func confirmPaymentSuccessful(clientSecret: String)
  func creditCardSelected(source: PaymentSourceSelected)
  func goToLoginSignupTapped()
  func userSessionDidChange()
  func pledgeDisclaimerViewDidTapLearnMore()
  func submitButtonTapped()
  func termsOfUseTapped(with: HelpType)
  func viewDidLoad()
  func applePayButtonTapped()
  func applePayContextDidCreatePayment(with paymentMethodId: String)
  func applePayContextDidComplete()
}

@MainActor
public protocol PostCampaignCheckoutViewModelOutputs: AnyObject {
  var onEstimatedShipping: ((String?, String?) -> Void)? { get set }
  var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)? { get set }
  var onPledgeRewardsSummary: ((PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData) -> Void)? { get set }
  var onPledgeCTA: ((PledgeViewCTAContainerViewData) -> Void)? { get set }
  var onConfigureStripe: ((String, String) -> Void)? { get set }
  var onEstimatedShippingHidden: ((Bool) -> Void)? { get set }
  var onPaymentMethodsHidden: ((Bool) -> Void)? { get set }
  var onProcessingHidden: ((Bool) -> Void)? { get set }
  var onGoToLoginSignup: ((LoginIntent) -> Void)? { get set }
  var onShowError: ((String) -> Void)? { get set }
  var onShowWebHelp: ((HelpType) -> Void)? { get set }
  var onValidateCheckout: ((PaymentSourceValidation) -> Void)? { get set }
  var onApplePayAuthorization: ((PostCampaignPaymentAuthorizationData) -> Void)? { get set }
  var onCheckoutComplete: ((ThanksPageData) -> Void)? { get set }
  var onCheckoutError: ((ErrorEnvelope) -> Void)? { get set }
}

@MainActor
public protocol PostCampaignCheckoutViewModelType {
  var inputs: PostCampaignCheckoutViewModelInputs { get }
  var outputs: PostCampaignCheckoutViewModelOutputs { get }
}

public class PostCampaignCheckoutViewModel: PostCampaignCheckoutViewModelType,
  PostCampaignCheckoutViewModelInputs,
  PostCampaignCheckoutViewModelOutputs {
  let stripeIntentService: StripeIntentServiceType

  public init(stripeIntentService: StripeIntentServiceType, feature: PledgeFeature = AppModel.shared.pledgeFeature) {
    self.stripeIntentService = stripeIntentService

    let initialData = self.initialDataEvents.output

    let context = initialData.map(\.context)
    let rewards = initialData.map(\.rewards)
    let baseReward = initialData.map(\.rewards).map(\.first).skipNil()
    let project = initialData.map(\.project)
    let selectedShippingRule = initialData.map(\.selectedShippingRule)
    let selectedQuantities = initialData.map(\.selectedQuantities)
    let refTag = initialData.map(\.refTag)
    let bonusAmount = initialData.map { $0.bonusSupport ?? 0.0 }

    let backing = project.map(\.personalization.backing).skipNil()

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

    // MARK: Calculate totals

    let calculatedShippingTotal = Signal.combineLatest(
      selectedShippingRule.skipNil(),
      rewards,
      selectedQuantities
    )
    .map(calculateShippingTotal)

    let allRewardsShippingTotal = Signal.merge(
      selectedShippingRule.filter(isNil).mapConst(0.0),
      calculatedShippingTotal
    )

    let allRewardsTotal = Signal.combineLatest(
      rewards,
      selectedQuantities
    )
    .map(calculateAllRewardsTotal)

    /**
     * For a regular reward this includes the bonus support amount,
     * the total of all rewards and their respective shipping costs.
     * For No Reward this is only the pledge amount.
     */
    let calculatedPledgeTotal = Signal.combineLatest(
      bonusAmount,
      allRewardsShippingTotal,
      allRewardsTotal
    )
    .map(calculatePledgeTotal)

    let pledgeTotal = Signal.merge(
      backing.map(\.amount),
      calculatedPledgeTotal
    )

    // MARK: Create checkout

    let pledgeDetailsData = Signal.combineLatest(
      project,
      rewards,
      bonusAmount,
      selectedQuantities,
      selectedShippingRule,
      pledgeTotal,
      refTag
    )

    let createCheckoutInput = Signal.combineLatest(
      self.loginStatePipe.output,
      pledgeDetailsData
    )
    .filter { isLoggedIn, _ in isLoggedIn }
    .map { _, data in
      let (
        project,
        rewards,
        _,
        selectedQuantities,
        selectedShippingRule,
        pledgeTotal,
        refTag
      ) = data
      let rewardsIDs: [String] = rewards.first?.isNoReward == true
        ? []
        : rewards.flatMap { reward -> [String] in
          guard let count = selectedQuantities[reward.id] else {
            return []
          }
          return [String](repeating: reward.graphID, count: count)
        }

      let locationId = selectedShippingRule.flatMap { String($0.location.id) }

      return CreateCheckoutInput(
        projectId: project.graphID,
        amount: String(format: "%.2f", pledgeTotal),
        locationId: locationId,
        rewardIds: rewardsIDs,
        refParam: refTag?.stringTag
      )
    }


    let checkoutIdentity = self.checkoutIdentity
    let createCheckoutEvents = self.checkoutEvents.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [feature, checkoutIdentity] _, userID, generation, id in
        checkoutIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let checkoutId = createCheckoutEvents.values()
      .map { values in
        var checkoutId = values.checkout.id
        if let decoded = decodeBase64(checkoutId), let range = decoded.range(of: "Checkout-") {
          let id = decoded[range.upperBound...]
          checkoutId = String(id)
        }
        return checkoutId
      }

    let backingId = createCheckoutEvents.values().map(\.checkout.backingId)

    let createCheckoutErrors = createCheckoutEvents.errors()

    // MARK: Configure views

    let pledgeRewardsSummary = Signal.combineLatest(
      initialData,
      allRewardsShippingTotal,
      pledgeTotal
    )
    .compactMap { data, shippingTotal, pledgeTotal in
      var rewards = data.rewards
      var bonus = data.bonusSupport
      if let reward = rewards.first, reward.isNoReward, let bonusAmount = bonus {
        rewards[0] = reward
          |> Reward.lens.minimum .~ bonusAmount
          |> Reward.lens.title .~ Strings.Pledge_without_a_reward()
        bonus = 0
      }
      let omitUSCurrencyCode = data.project.stats.omitUSCurrencyCode
      let projectCurrency = data.project.statsCurrency
      let shippingSummary = data.selectedShippingRule.flatMap {
        PledgeShippingSummaryViewData(
          locationName: $0.location.localizedName,
          omitUSCurrencyCode: omitUSCurrencyCode,
          currencyCode: projectCurrency,
          total: shippingTotal
        )
      }
      let rewardsData = PostCampaignRewardsSummaryViewData(
        rewards: data.rewards,
        selectedQuantities: data.selectedQuantities,
        currencyCode: projectCurrency,
        omitCurrencyCode: omitUSCurrencyCode,
        shipping: shippingSummary,
        useLatePledgeCosts: true
      )
      let pledgeData = PledgeSummaryViewData(
        project: data.project,
        total: pledgeTotal,
        confirmationLabelHidden: true,
        pledgeHasNoReward: pledgeHasNoRewards(rewards: rewardsData.rewards)
      )
      return (rewardsData, bonus, pledgeData)
    }

    // MARK: Create Payment Intent

    /// Called once on viewDidLoad. All signals, except checkoutId and backingId, are linked ot initialData.
    let paymentIntentInput = Signal.combineLatest(project, pledgeTotal, checkoutId, backingId)
    let paymentIntentEvent = self.paymentIntentPipe.output

    let paymentIntentClientSecret = paymentIntentEvent.values()
      .map { $0.clientSecret }

    let paymentIntentErrors = paymentIntentEvent.errors()

    // MARK: Validate Existing Cards

    let selectedCard = self.paymentSelectedPipe.output.skipNil()

    let paymentIntentClientSecretForExistingCards = paymentIntentClientSecret
      .takeWhen(selectedCard)

    let validateCheckoutExistingCardInput = Signal
      .combineLatest(
        checkoutId,
        selectedCard,
        paymentIntentClientSecretForExistingCards
      )

    // Runs validation for pre-existing cards that were created with setup intents originally but require payment intents for late pledges.
    let validateExistingCardRequests = validateCheckoutExistingCardInput
      .takeWhen(self.submitButtonTappedProperty.signal)
    let validateCheckoutExistingCard = self.cardValidation.events(feature: feature)

    let validateCheckoutSuccess: Signal<PaymentSourceValidation, Never> = Signal
      .combineLatest(paymentIntentClientSecretForExistingCards, selectedCard)
      .takeWhen(validateCheckoutExistingCard.values())
      .map { paymentIntentClientSecret, selectedCard in

        PaymentSourceValidation(
          paymentIntentClientSecret: paymentIntentClientSecret,
          selectedCardStripeCardId: selectedCard.stripePaymentMethodId,
          requiresConfirmation: true
        )
      }

    // MARK: ApplePay

    /*

     Order of operations:
     1) Apple pay button tapped
     3) Present the payment authorization form
     4) Payment authorization form calls applePayContextDidCreatePayment with the payment method Id
     5) Payment authorization form calls paymentAuthorizationDidFinish
     6) Validate checkout using the checkoutId, payment source id, and payment intent
     */

    // Ensure all required data exists before assuming apple pay flow starts.
    let startApplePayFlow = Signal.combineLatest(project, pledgeTotal, checkoutId, backingId)
      .takeWhen(self.applePayButtonTappedSignal)

    let paymentIntentClientSecretForApplePay: Signal<String, Never> = paymentIntentClientSecret
      .takeWhen(startApplePayFlow)

    let goToApplePayPaymentAuthorization: Signal<PostCampaignPaymentAuthorizationData, Never> = Signal.combineLatest(
      project,
      baseReward,
      allRewardsTotal,
      bonusAmount,
      allRewardsShippingTotal,
      pledgeTotal,
      paymentIntentClientSecretForApplePay
    )
    .map { (
      project,
      baseReward,
      allRewardsTotal,
      bonusAmount,
      allRewardsShippingTotal,
      pledgeTotal,
      paymentIntent: String
    ) -> PostCampaignPaymentAuthorizationData? in

      PostCampaignPaymentAuthorizationData(
        project: project,
        hasNoReward: baseReward.isNoReward,
        subtotal: baseReward.isNoReward ? bonusAmount : allRewardsTotal,
        bonus: baseReward.isNoReward ? 0.0 : bonusAmount,
        shipping: allRewardsShippingTotal,
        total: pledgeTotal,
        merchantIdentifier: Secrets.ApplePay.merchantIdentifier,
        paymentIntent: paymentIntent
      )
    }
    .skipNil()

    let validateApplePayRequests = Signal.combineLatest(
      paymentIntentClientSecretForApplePay,
      checkoutId,
      self.applePayPaymentMethodIdSignal.signal
    )
    .takeWhen(self.applePayContextDidCompleteSignal)
    let validateCheckoutWithApplePay = self.applePayValidation.events(feature: feature)

    let validateCheckoutError = Signal
      .merge(
        validateCheckoutExistingCard.errors(),
        validateCheckoutWithApplePay.errors()
      )

    // MARK: CompleteOnSessionCheckout

    let completeCheckoutWithCreditCardInput: Signal<GraphAPI.CompleteOnSessionCheckoutInput, Never> = Signal
      .combineLatest(self.confirmPaymentSuccessfulProperty.signal.skipNil(), checkoutId, selectedCard)
      .takeWhen(self.confirmPaymentSuccessfulProperty.signal.skipNil())
      .map { (
        clientSecret: String,
        checkoutId: String,
        selectedCard: PaymentSourceSelected
      ) -> GraphAPI.CompleteOnSessionCheckoutInput in

        GraphAPI
          .CompleteOnSessionCheckoutInput(
            checkoutId: encodeToBase64("Checkout-\(checkoutId)"),
            paymentIntentClientSecret: clientSecret,
            paymentSourceId: GraphQLNullable.someOrNil(selectedCard.savedCreditCardId),
            paymentSourceReusable: true,
            applePay: nil
          )
      }

    let completeCheckoutWithApplePayInput: Signal<GraphAPI.CompleteOnSessionCheckoutInput, Never> = Signal
      .combineLatest(paymentIntentClientSecretForApplePay, checkoutId)
      .takeWhen(validateCheckoutWithApplePay.values())
      .map {
        (
          clientSecret: String,
          checkoutId: String
        ) -> GraphAPI.CompleteOnSessionCheckoutInput in
        GraphAPI
          .CompleteOnSessionCheckoutInput(
            checkoutId: encodeToBase64("Checkout-\(checkoutId)"),
            paymentIntentClientSecret: clientSecret,
            paymentSourceId: nil,
            paymentSourceReusable: false,
            /* We are no longer sending ApplePay parameters to the backend, because Stripe Tokens are
              considered deprecated and are incompatible with PaymentIntent-based payments.

              In the future, we may use the other parameters in the ApplePayParams object, but for now,
              send nil.
              */
            applePay: nil
          )
      }

    let completeCheckoutRequests = Signal.merge(
      completeCheckoutWithCreditCardInput, completeCheckoutWithApplePayInput
    )
    let completionIdentity = self.completionIdentity
    let checkoutCompleteSignal = self.completionEvents.output
      .filter { [feature, completionIdentity] _, userID, generation, id in
        completionIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let thanksPageData = Signal.combineLatest(project, baseReward, pledgeTotal)
      .compactMap { project, baseReward, pledgeTotal -> ThanksPageData in
        (project, baseReward, nil, pledgeTotal)
      }

    let checkoutComplete: Signal<ThanksPageData, Never> = thanksPageData
      .takeWhen(checkoutCompleteSignal.values())
      .map { $0 }

    let checkoutErrors = checkoutCompleteSignal.errors()

    // MARK: - Error handling

    let errorMessages = Signal.merge(createCheckoutErrors, validateCheckoutError)
      .map { error in
        switch error.ksrCode {
        case .ValidateCheckoutError:
          return error.errorMessages.first ?? Strings.Something_went_wrong_please_try_again()
        default:
          return Strings.Something_went_wrong_please_try_again()
        }
      }

    // MARK: - UI related to checkout flow

    let existingCardActivatesPledgeButton = validateCheckoutExistingCardInput
      .mapConst(true)

    let pledgeButtonEnabled = Signal.merge(
      self.viewDidLoadEvents.output.mapConst(false),
      existingCardActivatesPledgeButton
    )
    .skipRepeats()

    let pledgeCTA: Signal<PledgeViewCTAContainerViewData, Never> = Signal.combineLatest(
      project,
      pledgeTotal,
      pledgeButtonEnabled,
      context,
      self.loginStatePipe.output
    )
    .map { project, pledgeTotal, pledgeButtonEnabled, context, isLoggedIn in
      PledgeViewCTAContainerViewData(
        project: project,
        total: pledgeTotal,
        isLoggedIn: isLoggedIn,
        isEnabled: pledgeButtonEnabled,
        context: context,
        willRetryPaymentMethod: false // Only retry in the `fixPaymentMethod` context.
      )
    }

    let processingViewIsHidden = Signal.merge(
      // Processing view starts hidden, so show at the start of a pledge flow.
      self.submitButtonTappedProperty.signal.mapConst(false),
      startApplePayFlow.mapConst(false),
      // Hide view again whenever pledge flow is completed/cancelled/errors.
      paymentIntentErrors.mapConst(true),
      validateCheckoutError.mapConst(true),
      self.checkoutTerminatedProperty.signal.mapConst(true),
      checkoutCompleteSignal.mapConst(true)
    )

    // MARK: - Tracking

    // Use checkoutId in tracking, or default to nil if creating it errors.
    let checkoutIdOrNil = Signal.merge(
      checkoutId.wrapInOptional(),
      createCheckoutErrors.mapConst(nil).take(first: 1)
    )

    let checkoutData = Signal.combineLatest(
      initialData,
      baseReward,
      pledgeTotal,
      allRewardsShippingTotal,
      checkoutIdOrNil
    )

    // Page viewed event
    checkoutData.take(first: 1)
      .observeValues { data, baseReward, pledgeTotal, shippingTotal, checkoutId in
        let checkoutData = self.trackingDataFromCheckoutParams(
          data,
          baseReward: baseReward,
          pledgeTotal: pledgeTotal,
          shippingTotal: shippingTotal,
          checkoutId: checkoutId
        )
        AppEnvironment.current.ksrAnalytics.trackCheckoutPaymentPageViewed(
          project: data.project,
          reward: data.rewards[0],
          pledgeViewContext: data.context,
          checkoutData: checkoutData,
          refTag: data.refTag
        )
      }

    // Pledge button tapped event
    checkoutData
      .takeWhen(self.submitButtonTappedProperty.signal)
      .observeValues { data, baseReward, pledgeTotal, shippingTotal, checkoutId in
        let checkoutData = self.trackingDataFromCheckoutParams(
          data,
          baseReward: baseReward,
          pledgeTotal: pledgeTotal,
          shippingTotal: shippingTotal,
          checkoutId: checkoutId
        )
        AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
          project: data.project,
          reward: baseReward,
          typeContext: .creditCard,
          checkoutData: checkoutData,
          refTag: data.refTag
        )
      }

    // Apple pay button tapped event
    checkoutData
      .takeWhen(self.applePayButtonTappedSignal)
      .observeValues { data, baseReward, pledgeTotal, shippingTotal, checkoutId in
        let checkoutData = self.trackingDataFromCheckoutParams(
          data,
          baseReward: baseReward,
          pledgeTotal: pledgeTotal,
          shippingTotal: shippingTotal,
          checkoutId: checkoutId,
          isApplePay: true
        )
        AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
          project: data.project,
          reward: baseReward,
          typeContext: .applePay,
          checkoutData: checkoutData,
          refTag: data.refTag
        )
      }
    self.checkoutObservation = createCheckoutInput.observeValues { [weak self] input in
      guard let self else { return }
      self.checkoutTask?.cancel()
      let userID = feature.sessionFeature.currentUser?.id
      let generation = feature.sessionFeature.generation
      let id = UUID()
      self.checkoutIdentity.id = id
      let request = feature.startOpenCheckout(input)
      self.checkoutTask = Task { [weak self] in
        do {
          let checkout = try await request.value
          guard !Task.isCancelled else { return }
          self?.checkoutEvents.input.send(value: (.value(checkout), userID, generation, id))
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          self?.checkoutEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
        }
      }
    }
    self.completionObservation = completeCheckoutRequests.observeValues { [weak self] input in
      guard let self else { return }
      self.completionTask?.cancel()
      let userID = feature.sessionFeature.currentUser?.id
      let generation = feature.sessionFeature.generation
      let id = UUID()
      self.completionIdentity.id = id
      let request = feature.startCompleteCheckout(input)
      self.completionTask = Task { [weak self] in
        do {
          try await request.value
          guard !Task.isCancelled else { return }
          self?.completionEvents.input.send(value: (.value(()), userID, generation, id))
          self?.completionEvents.input.send(value: (.completed, userID, generation, id))
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          self?.completionEvents.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
        }
      }
    }
    self.cardValidationObservation = validateExistingCardRequests.observeValues { [weak self] checkoutID, card, secret in
      assert(card.stripePaymentMethodId.isSome && card.stripePaymentMethodId != "",
             "Payment method ID should not be missing in a late pledge context.")
      self?.cardValidation.start(feature: feature, checkoutID: checkoutID,
                                 sourceID: card.stripePaymentMethodId ?? "", secret: secret)
    }
    self.applePayValidationObservation = validateApplePayRequests.observeValues { [weak self] secret, checkoutID, paymentMethodID in
      self?.applePayValidation.start(feature: feature, checkoutID: checkoutID,
                                     sourceID: paymentMethodID, secret: secret)
    }
    self.paymentIntentObservation = paymentIntentInput.observeValues { [weak self] project, total, checkoutID, backingID in
      guard let self else { return }
      self.paymentIntentTask?.cancel()
      let request = self.stripeIntentService.createPaymentIntent(
        for: project.graphID, backingId: backingID, checkoutId: checkoutID, pledgeTotal: total
      )
      self.paymentIntentTask = Task { [weak self] in
        do {
          let intent = try await request.value
          guard !Task.isCancelled else { return }
          self?.paymentIntentPipe.input.send(value: .value(intent))
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          self?.paymentIntentPipe.input.send(value: .failed((error as? ErrorEnvelope) ?? .couldNotParseJSON))
        }
      }
    }

    _ = initialData.observeValues { [weak self] data in
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
      guard !data.context.paymentMethodsViewHidden else { return }
      self?.onConfigureStripe?(
        Secrets.ApplePay.merchantIdentifier,
        AppEnvironment.current.environmentType.stripePublishableKey
      )
    }
    _ = pledgeRewardsSummary.observeValues { [weak self] in self?.onPledgeRewardsSummary?($0.0, $0.1, $0.2) }
    _ = pledgeCTA.observeValues { [weak self] in self?.onPledgeCTA?($0) }
    _ = processingViewIsHidden.observeValues { [weak self] in self?.onProcessingHidden?($0) }
    _ = errorMessages.observeValues { [weak self] in self?.onShowError?($0) }
    _ = checkoutErrors.observeValues { [weak self] in self?.onCheckoutError?($0) }
    _ = validateCheckoutSuccess.observeValues { [weak self] in self?.onValidateCheckout?($0) }
    _ = goToApplePayPaymentAuthorization.observeValues { [weak self] in self?.onApplePayAuthorization?($0) }
    _ = checkoutComplete.observeValues { [weak self] in self?.onCheckoutComplete?($0) }
    login.onLogin = { [weak self] in self?.onGoToLoginSignup?($0) }
    paymentMethods.onHidden = { [weak self] in self?.onPaymentMethodsHidden?($0) }
    paymentMethods.onConfiguration = { [weak self] in self?.onConfigurePaymentMethods?($0) }
  }

  // MARK: - Helpers

  private func trackingDataFromCheckoutParams(
    _ data: PledgeViewData,
    baseReward: Reward,
    pledgeTotal: Double,
    shippingTotal: Double,
    checkoutId: String?,
    isApplePay: Bool = false
  )
    -> KSRAnalytics.CheckoutPropertiesData {
    return checkoutProperties(
      from: data.project,
      baseReward: baseReward,
      addOnRewards: data.rewards,
      selectedQuantities: data.selectedQuantities,
      additionalPledgeAmount: data.bonusSupport ?? 0,
      pledgeTotal: pledgeTotal,
      shippingTotal: shippingTotal,
      checkoutId: checkoutId,
      isApplePay: isApplePay
    )
  }

  // MARK: - Inputs

  private let checkoutTerminatedProperty = MutableProperty(())
  public func checkoutTerminated() {
    self.checkoutTerminatedProperty.value = ()
  }

  private var configuredData: PledgeViewData?
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
  }

  private let confirmPaymentSuccessfulProperty = MutableProperty<String?>(nil)
  public func confirmPaymentSuccessful(clientSecret: String) {
    self.confirmPaymentSuccessfulProperty.value = clientSecret
  }

  public func creditCardSelected(
    source: PaymentSourceSelected
  ) {
    self.paymentMethodsUseCase.creditCardSelected(with: source)
  }

  public func goToLoginSignupTapped() {
    self.loginSignupUseCase.goToLoginSignupTapped()
  }

  public func pledgeDisclaimerViewDidTapLearnMore() {
    self.onShowWebHelp?(.trust)
  }

  private let submitButtonTappedProperty = MutableProperty(())
  public func submitButtonTapped() {
    self.submitButtonTappedProperty.value = ()
  }

  public func termsOfUseTapped(with helpType: HelpType) {
    self.onShowWebHelp?(helpType)
  }

  public func userSessionDidChange() {
    self.loginSignupUseCase.userSessionDidChange()
  }

  public func viewDidLoad() {
    self.hasLoadedView = true
    self.publishInitialDataWhenReady()
    self.viewDidLoadEvents.input.send(value: ())
  }

  private let (applePayButtonTappedSignal, applePayButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func applePayButtonTapped() {
    self.applePayButtonTappedObserver.send(value: ())
  }

  private let (applePayPaymentMethodIdSignal, applePayPaymentMethodIdObserver) = Signal<String, Never>.pipe()
  public func applePayContextDidCreatePayment(with paymentMethodId: String) {
    self.applePayPaymentMethodIdObserver.send(value: paymentMethodId)
  }

  private let (applePayContextDidCompleteSignal, applePayContextDidCompleteObserver)
    = Signal<Void, Never>.pipe()
  public func applePayContextDidComplete() {
    self.applePayContextDidCompleteObserver.send(value: ())
  }

  // MARK: - Outputs

  public var onEstimatedShipping: ((String?, String?) -> Void)?
  public var onConfigurePaymentMethods: ((PledgePaymentMethodsValue) -> Void)?

  public var onPledgeRewardsSummary: ((PostCampaignRewardsSummaryViewData, Double?, PledgeSummaryViewData) -> Void)?
  public var onPledgeCTA: ((PledgeViewCTAContainerViewData) -> Void)?
  public var onConfigureStripe: ((String, String) -> Void)?
  public var onEstimatedShippingHidden: ((Bool) -> Void)?
  public var onGoToLoginSignup: ((LoginIntent) -> Void)?

  public var onProcessingHidden: ((Bool) -> Void)?
  public var onShowError: ((String) -> Void)?
  public var onShowWebHelp: ((HelpType) -> Void)?
  public var onPaymentMethodsHidden: ((Bool) -> Void)?

  public var onValidateCheckout: ((PaymentSourceValidation) -> Void)?
  public var onApplePayAuthorization: ((PostCampaignPaymentAuthorizationData) -> Void)?
  public var onCheckoutComplete: ((ThanksPageData) -> Void)?
  public var onCheckoutError: ((ErrorEnvelope) -> Void)?

  public var inputs: PostCampaignCheckoutViewModelInputs { return self }
  public var outputs: PostCampaignCheckoutViewModelOutputs { return self }

  // MARK: - Use cases

  private let loginSignupUseCase: LoginSignupUseCase
  private let checkoutEvents = Signal<(Signal<CreateCheckoutEnvelope, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let checkoutIdentity = CheckoutRequestIdentity()
  private var checkoutObservation: (any Disposable)?
  private var checkoutTask: Task<Void, Never>?
  private let completionEvents = Signal<(Signal<Void, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let completionIdentity = CheckoutRequestIdentity()
  private var completionObservation: (any Disposable)?
  private var completionTask: Task<Void, Never>?
  private let cardValidation = CheckoutValidationLane()
  private let applePayValidation = CheckoutValidationLane()
  private var cardValidationObservation: (any Disposable)?
  private var applePayValidationObservation: (any Disposable)?
  private let paymentIntentPipe = Signal<Signal<PaymentIntentEnvelope, ErrorEnvelope>.Event, Never>.pipe()
  private var paymentIntentObservation: (any Disposable)?
  private var paymentIntentTask: Task<Void, Never>?

  deinit {
    self.checkoutObservation?.dispose()
    self.checkoutTask?.cancel()
    self.completionObservation?.dispose()
    self.completionTask?.cancel()
    self.cardValidationObservation?.dispose()
    self.applePayValidationObservation?.dispose()
    self.paymentIntentObservation?.dispose()
    self.paymentIntentTask?.cancel()
  }

  private let loginStatePipe = Signal<Bool, Never>.pipe()
  private let loginSessionPipe = Signal<Void, Never>.pipe()
  private let paymentMethodsUseCase: PaymentMethodsUseCase
  private let paymentSelectedPipe = Signal<PaymentSourceSelected?, Never>.pipe()
  private let paymentValidPipe = Signal<Bool, Never>.pipe()
}

@MainActor
private final class CheckoutRequestIdentity {
  var id = UUID()
}

@MainActor
private final class CheckoutValidationLane {
  private let output = Signal<(Signal<ValidateCheckoutEnvelope, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let identity = CheckoutRequestIdentity()
  private var task: Task<Void, Never>?

  deinit { self.task?.cancel() }

  func events(feature: PledgeFeature) -> Signal<Signal<ValidateCheckoutEnvelope, ErrorEnvelope>.Event, Never> {
    let identity = self.identity
    return self.output.output
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { [feature, identity] _, userID, generation, id in
        identity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }
  }

  func start(feature: PledgeFeature, checkoutID: String, sourceID: String, secret: String) {
    self.task?.cancel()
    let userID = feature.sessionFeature.currentUser?.id
    let generation = feature.sessionFeature.generation
    let id = UUID()
    self.identity.id = id
    let request = feature.startValidateCheckout(checkoutID: checkoutID, sourceID: sourceID, secret: secret)
    self.task = Task { [weak self] in
      do {
        let result = try await request.value
        guard !Task.isCancelled else { return }
        self?.output.input.send(value: (.value(result), userID, generation, id))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        self?.output.input.send(value: (.failed((error as? ErrorEnvelope) ?? .couldNotParseJSON), userID, generation, id))
      }
    }
  }
}
