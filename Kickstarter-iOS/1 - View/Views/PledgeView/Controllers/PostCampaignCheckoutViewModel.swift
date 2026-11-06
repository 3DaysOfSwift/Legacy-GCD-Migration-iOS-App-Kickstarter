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
private final class PostCampaignApplePayState {
  var onStart: (() -> Void)?
  var onAuthorize: ((String) -> Void)?
  var onValidate: ((String, String, String) -> Void)?
  var onComplete: ((GraphAPI.CompleteOnSessionCheckoutInput) -> Void)?
  private var checkoutID: String?
  private var intentSecret: String?
  private var selectedSecret: String?
  private var paymentMethodID: String?

  func setCheckoutID(_ value: String) { checkoutID = value }
  func setIntentSecret(_ value: String) { intentSecret = value }
  func setPaymentMethodID(_ value: String) { paymentMethodID = value }
  func start() {
    guard checkoutID != nil else { return }
    onStart?()
    guard let intentSecret else { return }
    selectedSecret = intentSecret
    onAuthorize?(intentSecret)
  }
  func validate() {
    guard let checkoutID, let selectedSecret, let paymentMethodID else { return }
    onValidate?(checkoutID, paymentMethodID, selectedSecret)
  }
  func validationSucceeded() {
    guard let checkoutID, let selectedSecret else { return }
    onComplete?(GraphAPI.CompleteOnSessionCheckoutInput(
      checkoutId: encodeToBase64("Checkout-\(checkoutID)"), paymentIntentClientSecret: selectedSecret,
      paymentSourceId: nil, paymentSourceReusable: false, applePay: nil
    ))
  }
}

@MainActor
private final class PostCampaignCardState {
  var onReady: (() -> Void)?
  var onSubmit: ((String, PaymentSourceSelected, String) -> Void)?
  private var checkoutID: String?
  private var intentSecret: String?
  private var selectedCard: PaymentSourceSelected?
  private var selectedSecret: String?

  func setCheckoutID(_ value: String) { checkoutID = value; notifyIfReady() }
  func setIntentSecret(_ value: String) { intentSecret = value }
  func select(_ value: PaymentSourceSelected?) {
    guard let value else { return }
    selectedCard = value
    if let intentSecret { selectedSecret = intentSecret }
    notifyIfReady()
  }
  func submit() {
    guard let checkoutID, let selectedCard, let selectedSecret else { return }
    onSubmit?(checkoutID, selectedCard, selectedSecret)
  }
  func completionInput(clientSecret: String) -> GraphAPI.CompleteOnSessionCheckoutInput? {
    guard let checkoutID, let selectedCard else { return nil }
    return GraphAPI.CompleteOnSessionCheckoutInput(
      checkoutId: encodeToBase64("Checkout-\(checkoutID)"), paymentIntentClientSecret: clientSecret,
      paymentSourceId: GraphQLNullable.someOrNil(selectedCard.savedCreditCardId),
      paymentSourceReusable: true, applePay: nil
    )
  }
  var validation: PaymentSourceValidation? {
    guard let selectedCard, let selectedSecret else { return nil }
    return PaymentSourceValidation(paymentIntentClientSecret: selectedSecret,
                                   selectedCardStripeCardId: selectedCard.stripePaymentMethodId,
                                   requiresConfirmation: true)
  }
  private func notifyIfReady() {
    if checkoutID != nil && selectedCard != nil && selectedSecret != nil { onReady?() }
  }
}

@MainActor
private final class PostCampaignCTAState {
  var onChange: ((PledgeViewCTAContainerViewData) -> Void)?
  private var data: PledgeViewData?
  private var loggedIn: Bool?
  private var enabled: Bool?

  func configure(_ data: PledgeViewData) { self.data = data; publish() }
  func setLoggedIn(_ value: Bool) { loggedIn = value; publish() }
  func setEnabled(_ value: Bool) {
    guard enabled != value else { return }
    enabled = value
    publish()
  }

  private func publish() {
    guard let data, let loggedIn, let enabled else { return }
    onChange?((data.project, PostCampaignAmounts(data).total, loggedIn, enabled, data.context, false))
  }
}

@MainActor
private final class PostCampaignOpeningState {
  var onOpen: ((KsApi.CreateCheckoutInput) -> Void)?
  private var data: PledgeViewData?
  private var loggedIn = false

  func configure(_ data: PledgeViewData) { self.data = data; openIfReady() }
  func setLoggedIn(_ value: Bool) { loggedIn = value; openIfReady() }

  private func openIfReady() {
    guard loggedIn, let data else { return }
    let rewardIDs = data.rewards.first?.isNoReward == true ? [] : data.rewards.flatMap { reward in
      [String](repeating: reward.graphID, count: data.selectedQuantities[reward.id] ?? 0)
    }
    onOpen?(KsApi.CreateCheckoutInput(
      projectId: data.project.graphID, amount: String(format: "%.2f", PostCampaignAmounts(data).total),
      locationId: data.selectedShippingRule.map { String($0.location.id) }, rewardIds: rewardIDs,
      refParam: data.refTag?.stringTag
    ))
  }
}

private struct PostCampaignAmounts {
  let rewards: Double
  let shipping: Double
  let total: Double

  init(_ data: PledgeViewData) {
    rewards = calculateAllRewardsTotal(addOnRewards: data.rewards, selectedQuantities: data.selectedQuantities)
    shipping = data.selectedShippingRule.map {
      calculateShippingTotal(shippingRule: $0, addOnRewards: data.rewards, quantities: data.selectedQuantities)
    } ?? 0
    total = calculatePledgeTotal(pledgeAmount: data.bonusSupport ?? 0, shippingCost: shipping, addOnRewardsTotal: rewards)
  }
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

    let ctaState = self.ctaState
    let cardState = self.cardState
    let appleState = self.applePayState

    self.loginSignupUseCase = LoginSignupUseCase(withLoginIntent: .backProject)
    let login = self.loginSignupUseCase
    let openingState = PostCampaignOpeningState()
    login.onLoginState = { value in
      ctaState.setLoggedIn(value)
      openingState.setLoggedIn(value)
    }

    self.paymentMethodsUseCase = PaymentMethodsUseCase()
    let paymentMethods = self.paymentMethodsUseCase
    paymentMethods.onSelected = { value in
      cardState.select(value)
    }
    let previousLoginHandler = login.onLoginState
    login.onLoginState = { value in
      previousLoginHandler?(value)
      paymentMethods.loginChanged(value)
    }

    // MARK: Create checkout

    // MARK: Configure views

    // MARK: Create Payment Intent

    let paymentIntentEvent = self.paymentIntentPipe.output

    let paymentIntentClientSecret = paymentIntentEvent.values()
      .map { $0.clientSecret }

    let paymentIntentErrors = paymentIntentEvent.errors()

    // MARK: Validate Existing Cards

    paymentIntentClientSecret.observeValues { value in
      cardState.setIntentSecret(value)
      appleState.setIntentSecret(value)
    }
    let validateCheckoutExistingCard = self.cardValidation.events(feature: feature)

    // MARK: ApplePay

    /*

     Order of operations:
     1) Apple pay button tapped
     3) Present the payment authorization form
     4) Payment authorization form calls applePayContextDidCreatePayment with the payment method Id
     5) Payment authorization form calls paymentAuthorizationDidFinish
     6) Validate checkout using the checkoutId, payment source id, and payment intent
     */

    let validateCheckoutWithApplePay = self.applePayValidation.events(feature: feature)

    let validateCheckoutError = Signal
      .merge(
        validateCheckoutExistingCard.errors(),
        validateCheckoutWithApplePay.errors()
      )

    // MARK: CompleteOnSessionCheckout

    validateCheckoutWithApplePay.values().observeValues { _ in appleState.validationSucceeded() }
    let completionIdentity = self.completionIdentity
    let checkoutCompleteSignal = self.completionEvents.output
      .filter { [feature, completionIdentity] _, userID, generation, id in
        completionIdentity.id == id && feature.sessionFeature.isCurrent(userID: userID, generation: generation)
      }
      .map { event, _, _, _ in event }

    let checkoutErrors = checkoutCompleteSignal.errors()

    // MARK: - Error handling

    let errorMessages = validateCheckoutError
      .map { error in
        switch error.ksrCode {
        case .ValidateCheckoutError:
          return error.errorMessages.first ?? Strings.Something_went_wrong_please_try_again()
        default:
          return Strings.Something_went_wrong_please_try_again()
        }
      }

    // MARK: - UI related to checkout flow

    cardState.onReady = { ctaState.setEnabled(true) }

    appleState.onStart = { [weak self] in self?.onProcessingHidden?(false) }
    paymentIntentErrors.observeValues { [weak self] _ in self?.onProcessingHidden?(true) }
    validateCheckoutError.observeValues { [weak self] _ in self?.onProcessingHidden?(true) }
    checkoutCompleteSignal.observeValues { [weak self] _ in self?.onProcessingHidden?(true) }

    openingState.onOpen = { [weak self] input in
      guard let self, let data = self.configuredData else { return }
      self.activeCheckoutData = data
      self.checkoutTask?.cancel()
      let userID = feature.sessionFeature.currentUser?.id
      let generation = feature.sessionFeature.generation
      let id = UUID()
      self.checkoutIdentity.id = id
      let request = feature.startOpenCheckout(input)
      self.checkoutTask = Task { [weak self] in
        do {
          let checkout = try await request.value
          try await Self.waitForPresentationDelay()
          guard !Task.isCancelled, let self, self.checkoutIdentity.id == id,
                feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
          self.deliverCheckout?(.success(checkout))
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          do { try await Self.waitForPresentationDelay() } catch { return }
          guard let self, self.checkoutIdentity.id == id,
                feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
          self.deliverCheckout?(.failure((error as? ErrorEnvelope) ?? .couldNotParseJSON))
        }
      }
    }
    self.startCompletion = { [weak self] input in
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
    appleState.onComplete = { [weak self] in self?.startCompletion?($0) }
    cardState.onSubmit = { [weak self] checkoutID, card, secret in
      assert(card.stripePaymentMethodId.isSome && card.stripePaymentMethodId != "",
             "Payment method ID should not be missing in a late pledge context.")
      self?.cardValidation.start(feature: feature, checkoutID: checkoutID,
                                 sourceID: card.stripePaymentMethodId ?? "", secret: secret)
    }
    appleState.onValidate = { [weak self] checkoutID, paymentMethodID, secret in
      self?.applePayValidation.start(feature: feature, checkoutID: checkoutID,
                                     sourceID: paymentMethodID, secret: secret)
    }
    self.deliverCheckout = { [weak self] result in
      guard let self else { return }
      switch result {
      case let .failure(error):
        let message = error.ksrCode == .ValidateCheckoutError
          ? (error.errorMessages.first ?? Strings.Something_went_wrong_please_try_again())
          : Strings.Something_went_wrong_please_try_again()
        self.onShowError?(message)
        if !self.hasTrackedCheckoutError {
          self.hasTrackedCheckoutError = true
          self.trackingCheckoutID = nil
          self.hasTrackingCheckoutResult = true
          self.trackPageIfReady()
        }
      case let .success(checkout):
        guard let data = self.activeCheckoutData else { return }
        var decodedCheckoutID = checkout.checkout.id
        if let decoded = decodeBase64(decodedCheckoutID), let range = decoded.range(of: "Checkout-") {
          decodedCheckoutID = String(decoded[range.upperBound...])
        }
        cardState.setCheckoutID(decodedCheckoutID)
        appleState.setCheckoutID(decodedCheckoutID)
        self.trackingCheckoutID = decodedCheckoutID
        self.hasTrackingCheckoutResult = true
        self.trackPageIfReady()
        self.paymentIntentTask?.cancel()
        let request = self.stripeIntentService.createPaymentIntent(
          for: data.project.graphID, backingId: checkout.checkout.backingId, checkoutId: decodedCheckoutID,
          pledgeTotal: PostCampaignAmounts(data).total
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
    }

    self.presentData = { [weak self] data in
      let amounts = PostCampaignAmounts(data)
      let bonus = data.rewards.first?.isNoReward == true && data.bonusSupport != nil ? 0 : data.bonusSupport
      let shippingSummary = data.selectedShippingRule.map {
        PledgeShippingSummaryViewData(locationName: $0.location.localizedName,
          omitUSCurrencyCode: data.project.stats.omitUSCurrencyCode,
          currencyCode: data.project.statsCurrency, total: amounts.shipping)
      }
      let rewardsData = PostCampaignRewardsSummaryViewData(
        rewards: data.rewards, selectedQuantities: data.selectedQuantities,
        currencyCode: data.project.statsCurrency, omitCurrencyCode: data.project.stats.omitUSCurrencyCode,
        shipping: shippingSummary, useLatePledgeCosts: true
      )
      let pledgeData = PledgeSummaryViewData(project: data.project, total: amounts.total,
        confirmationLabelHidden: true, pledgeHasNoReward: pledgeHasNoRewards(rewards: data.rewards))
      self?.onPledgeRewardsSummary?(rewardsData, bonus, pledgeData)
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
    self.configureState = { data in
      ctaState.configure(data)
      openingState.configure(data)
      login.initialDataAvailable()
      paymentMethods.configure(data)
    }
    ctaState.onChange = { [weak self] in self?.onPledgeCTA?($0) }
    _ = errorMessages.observeValues { [weak self] in self?.onShowError?($0) }
    _ = checkoutErrors.observeValues { [weak self] in self?.onCheckoutError?($0) }
    validateCheckoutExistingCard.values().observeValues { [weak self] _ in
      guard let self, let validation = cardState.validation else { return }
      self.onValidateCheckout?(validation)
    }
    appleState.onAuthorize = { [weak self] secret in
      guard let self, let data = self.activeCheckoutData, let reward = data.rewards.first else { return }
      let amounts = PostCampaignAmounts(data)
      let bonus = data.bonusSupport ?? 0
      self.onApplePayAuthorization?(PostCampaignPaymentAuthorizationData(
        project: data.project, hasNoReward: reward.isNoReward,
        subtotal: reward.isNoReward ? bonus : amounts.rewards, bonus: reward.isNoReward ? 0 : bonus,
        shipping: amounts.shipping, total: amounts.total,
        merchantIdentifier: Secrets.ApplePay.merchantIdentifier, paymentIntent: secret
      ))
    }
    checkoutCompleteSignal.values().observeValues { [weak self] _ in
      guard let self, let data = self.activeCheckoutData, let reward = data.rewards.first else { return }
      self.onCheckoutComplete?((data.project, reward, nil, PostCampaignAmounts(data).total))
    }
    login.onLogin = { [weak self] in self?.onGoToLoginSignup?($0) }
    paymentMethods.onHidden = { [weak self] in self?.onPaymentMethodsHidden?($0) }
    paymentMethods.onConfiguration = { [weak self] in self?.onConfigurePaymentMethods?($0) }
  }

  // MARK: - Helpers

  private static func waitForPresentationDelay() async throws {
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
    else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
  }


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

  private func trackPageIfReady() {
    guard !hasTrackedPage, hasTrackingCheckoutResult, let data = configuredData,
          let reward = data.rewards.first else { return }
    hasTrackedPage = true
    let amounts = PostCampaignAmounts(data)
    let checkout = trackingDataFromCheckoutParams(data, baseReward: reward, pledgeTotal: amounts.total,
      shippingTotal: amounts.shipping, checkoutId: trackingCheckoutID)
    AppEnvironment.current.ksrAnalytics.trackCheckoutPaymentPageViewed(
      project: data.project, reward: reward, pledgeViewContext: data.context,
      checkoutData: checkout, refTag: data.refTag
    )
  }

  private func trackSubmission(isApplePay: Bool) {
    guard hasTrackingCheckoutResult, let data = configuredData, let reward = data.rewards.first else { return }
    let amounts = PostCampaignAmounts(data)
    let checkout = trackingDataFromCheckoutParams(data, baseReward: reward, pledgeTotal: amounts.total,
      shippingTotal: amounts.shipping, checkoutId: trackingCheckoutID, isApplePay: isApplePay)
    AppEnvironment.current.ksrAnalytics.trackPledgeSubmitButtonClicked(
      project: data.project, reward: reward, typeContext: isApplePay ? .applePay : .creditCard,
      checkoutData: checkout, refTag: data.refTag
    )
  }

  // MARK: - Inputs

  public func checkoutTerminated() {
    self.onProcessingHidden?(true)
  }

  private var configuredData: PledgeViewData?
  private var activeCheckoutData: PledgeViewData?
  private var trackingCheckoutID: String?
  private var hasTrackingCheckoutResult = false
  private var hasTrackedCheckoutError = false
  private var hasTrackedPage = false
  private var hasLoadedView = false
  private var configureState: ((PledgeViewData) -> Void)?
  private var presentData: ((PledgeViewData) -> Void)?
  private let ctaState = PostCampaignCTAState()
  private let cardState = PostCampaignCardState()
  private let applePayState = PostCampaignApplePayState()

  public func configure(with data: PledgeViewData) {
    self.configuredData = data
    self.publishInitialDataWhenReady()
  }

  private func publishInitialDataWhenReady() {
    guard self.hasLoadedView, let data = self.configuredData else { return }
    self.configureState?(data)
    self.presentData?(data)
    self.trackPageIfReady()
  }

  public func confirmPaymentSuccessful(clientSecret: String) {
    guard let input = self.cardState.completionInput(clientSecret: clientSecret) else { return }
    self.startCompletion?(input)
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

  public func submitButtonTapped() {
    self.cardState.submit()
    self.trackSubmission(isApplePay: false)
    self.onProcessingHidden?(false)
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
    self.ctaState.setEnabled(false)
  }

  public func applePayButtonTapped() {
    self.applePayState.start()
    self.trackSubmission(isApplePay: true)
  }

  public func applePayContextDidCreatePayment(with paymentMethodId: String) {
    self.applePayState.setPaymentMethodID(paymentMethodId)
  }

  public func applePayContextDidComplete() {
    self.applePayState.validate()
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
  private var deliverCheckout: ((Result<CreateCheckoutEnvelope, ErrorEnvelope>) -> Void)?
  private let checkoutIdentity = CheckoutRequestIdentity()
  private var checkoutTask: Task<Void, Never>?
  private let completionEvents = Signal<(Signal<Void, ErrorEnvelope>.Event, Int?, Int, UUID), Never>.pipe()
  private let completionIdentity = CheckoutRequestIdentity()
  private var startCompletion: ((GraphAPI.CompleteOnSessionCheckoutInput) -> Void)?
  private var completionTask: Task<Void, Never>?
  private let cardValidation = CheckoutValidationLane()
  private let applePayValidation = CheckoutValidationLane()
  private let paymentIntentPipe = Signal<Signal<PaymentIntentEnvelope, ErrorEnvelope>.Event, Never>.pipe()
  private var paymentIntentTask: Task<Void, Never>?

  deinit {
    self.checkoutTask?.cancel()
    self.completionTask?.cancel()
    self.paymentIntentTask?.cancel()
  }

  private let paymentMethodsUseCase: PaymentMethodsUseCase
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
