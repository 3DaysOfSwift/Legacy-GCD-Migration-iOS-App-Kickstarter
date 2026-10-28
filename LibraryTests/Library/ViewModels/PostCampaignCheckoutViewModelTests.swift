import Apollo
import GraphAPI
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

@MainActor
final class PostCampaignCheckoutViewModelTests: TestCase {

  private func advancePayments(by interval: DispatchTimeInterval = .seconds(0)) async {
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.advance(by: interval)
    // A successful store can trigger a card reload during delivery.
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.advance()
  }
  private func runPayments() async {
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.run()
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
    await self.scheduler.run()
  }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let pledgeFeature = PledgeFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService, "Tests require MockService")
      return AsyncPledgeProvider(service: AppEnvironment.current.apiService)
    })
  private lazy var vm = PostCampaignCheckoutViewModel(
    stripeIntentService: MockStripeIntentService(), feature: self.pledgeFeature)
  private let mockStripeIntentService = MockStripeIntentService()

  private let checkoutResponse = CreateCheckoutEnvelope(
    checkout: CreateCheckoutEnvelope.Checkout(id: "19", paymentUrl: "fake", backingId: "93")
  )

  private let goToApplePayPaymentAuthorization = TestObserver<
    PostCampaignPaymentAuthorizationData,
    Never
  >()
  private let checkoutComplete = TestObserver<ThanksPageData, Never>()
  private let processingViewIsHidden = TestObserver<Bool, Never>()
  private let validateCheckoutSuccess = TestObserver<PaymentSourceValidation, Never>()
  private let checkoutError = TestObserver<ErrorEnvelope, Never>()
  private let goToLoginSignup = TestObserver<LoginIntent, Never>()

  private let configurePaymentMethodsViewControllerWithUser = TestObserver<User, Never>()
  private let configurePaymentMethodsViewControllerWithProject = TestObserver<Project, Never>()
  private let configurePaymentMethodsViewControllerWithCheckoutId = TestObserver<String, Never>()
  private let configurePaymentMethodsViewControllerWithReward = TestObserver<Reward, Never>()
  private let configurePaymentMethodsViewControllerWithContext = TestObserver<
    PledgeViewContext, Never
  >()

  private let configurePledgeViewCTAContainerViewIsLoggedIn = TestObserver<Bool, Never>()
  private let configurePledgeViewCTAContainerViewIsEnabled = TestObserver<Bool, Never>()
  private let configurePledgeViewCTAContainerViewContext = TestObserver<PledgeViewContext, Never>()

  private let configureStripeIntegrationMerchantId = TestObserver<String, Never>()
  private let configureStripeIntegrationPublishableKey = TestObserver<String, Never>()

  private let showWebHelp = TestObserver<HelpType, Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {

      self.vm = PostCampaignCheckoutViewModel(
        stripeIntentService: self.mockStripeIntentService, feature: self.pledgeFeature)

      self.vm.goToApplePayPaymentAuthorization.observe(
        self.goToApplePayPaymentAuthorization.observer)
      self.vm.checkoutComplete.observe(self.checkoutComplete.observer)
      self.vm.processingViewIsHidden.observe(self.processingViewIsHidden.observer)
      self.vm.validateCheckoutSuccess.observe(self.validateCheckoutSuccess.observer)
      self.vm.checkoutError.observe(self.checkoutError.observer)
      self.vm.goToLoginSignup.observe(self.goToLoginSignup.observer)

      self.vm.outputs.configurePaymentMethodsViewControllerWithValue.map { $0.0 }
        .observe(self.configurePaymentMethodsViewControllerWithUser.observer)
      self.vm.outputs.configurePaymentMethodsViewControllerWithValue.map { $0.1 }
        .observe(self.configurePaymentMethodsViewControllerWithProject.observer)
      self.vm.outputs.configurePaymentMethodsViewControllerWithValue.map { $0.2 }
        .observe(self.configurePaymentMethodsViewControllerWithCheckoutId.observer)
      self.vm.outputs.configurePaymentMethodsViewControllerWithValue.map { $0.3 }
        .observe(self.configurePaymentMethodsViewControllerWithReward.observer)
      self.vm.outputs.configurePaymentMethodsViewControllerWithValue.map { $0.4 }
        .observe(self.configurePaymentMethodsViewControllerWithContext.observer)

      self.vm.outputs.configurePledgeViewCTAContainerView.map { $0.2 }
        .observe(self.configurePledgeViewCTAContainerViewIsLoggedIn.observer)
      self.vm.outputs.configurePledgeViewCTAContainerView.map { $0.3 }
        .observe(self.configurePledgeViewCTAContainerViewIsEnabled.observer)
      self.vm.outputs.configurePledgeViewCTAContainerView.map { $0.4 }
        .observe(self.configurePledgeViewCTAContainerViewContext.observer)

      self.vm.outputs.configureStripeIntegration.map(first)
        .observe(self.configureStripeIntegrationMerchantId.observer)
      self.vm.outputs.configureStripeIntegration.map(second)
        .observe(self.configureStripeIntegrationPublishableKey.observer)

      self.vm.outputs.showWebHelp.observe(self.showWebHelp.observer)
    }
  }

  // MARK: - Web Help

  func testShowWebHelp() async {
    self.vm.inputs.viewDidLoad()

    self.vm.inputs.termsOfUseTapped(with: .terms)

    self.showWebHelp.assertValues([HelpType.terms])
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
  }

  func testShowWebHelpLearnMore() async {
    self.vm.inputs.viewDidLoad()

    self.vm.inputs.pledgeDisclaimerViewDidTapLearnMore()

    self.showWebHelp.assertValues([HelpType.trust])
    await self.pledgeFeature.waitForOperations()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    await self.pledgeFeature.waitForOperations()
  }

  // MARK: - Stripe

  func testStripeConfiguration_StagingEnvironment() async {
    let mockService = MockService(serverConfig: ServerConfig.staging)

    await withEnvironment(apiService: mockService) {
      self.configureStripeIntegrationMerchantId.assertDidNotEmitValue()
      self.configureStripeIntegrationPublishableKey.assertDidNotEmitValue()

      let project = Project.template
      let reward = Reward.template

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: 0,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      self.configureStripeIntegrationMerchantId.assertValues([Secrets.ApplePay.merchantIdentifier])
      self.configureStripeIntegrationPublishableKey.assertValues([
        Secrets.StripePublishableKey.staging
      ])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testStripeConfiguration_ProductionEnvironment() async {
    let mockService = MockService(serverConfig: ServerConfig.production)

    await withEnvironment(apiService: mockService) {
      self.configureStripeIntegrationMerchantId.assertDidNotEmitValue()

      let project = Project.template
      let reward = Reward.template

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: 0,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      self.configureStripeIntegrationMerchantId.assertValues([Secrets.ApplePay.merchantIdentifier])
      self.configureStripeIntegrationPublishableKey.assertValues([
        Secrets.StripePublishableKey.production
      ])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  // MARK: - Apple Pay

  func testApplePayAuthorization_noReward_isCorrect() async {
    let project = Project.cosmicSurgery
    let reward = Reward.noReward

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 5,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      await self.runPayments()

      self.goToApplePayPaymentAuthorization.assertValueCount(1)
      let output = self.goToApplePayPaymentAuthorization.lastValue!

      XCTAssertEqual(output.project, project)
      XCTAssertEqual(output.hasNoReward, true)
      XCTAssertEqual(output.subtotal, 5)
      XCTAssertEqual(output.bonus, 0)
      XCTAssertEqual(output.shipping, 0)
      XCTAssertEqual(output.total, 5)

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testApplePayAuthorization_reward_isCorrect() async {
    let project = Project.cosmicSurgery
    let reward = project.rewards.first!

    XCTAssertEqual(reward.minimum, 6)

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 3],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      await self.runPayments()

      self.goToApplePayPaymentAuthorization.assertValueCount(1)
      let output = self.goToApplePayPaymentAuthorization.lastValue!

      XCTAssertEqual(output.project, project)
      XCTAssertEqual(output.hasNoReward, false)
      XCTAssertEqual(output.subtotal, 18)
      XCTAssertEqual(output.bonus, 0)
      XCTAssertEqual(output.shipping, 0)
      XCTAssertEqual(output.total, 18)

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testApplePayAuthorization_rewardAndShipping_isCorrect() async {
    let project = Project.cosmicSurgery
    let reward =
      project.rewards.first!

      |> Reward.lens.shipping.enabled .~ true

    XCTAssertEqual(reward.minimum, 6)

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: ShippingRule.template,
      selectedQuantities: [reward.id: 3],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      await self.runPayments()

      self.goToApplePayPaymentAuthorization.assertValueCount(1)
      let output = self.goToApplePayPaymentAuthorization.lastValue!

      XCTAssertEqual(output.project, project)
      XCTAssertEqual(output.hasNoReward, false)
      XCTAssertEqual(output.subtotal, 18)
      XCTAssertEqual(output.bonus, 0)
      XCTAssertEqual(output.shipping, 15)
      XCTAssertEqual(output.total, 33)

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testApplePayAuthorization_rewardAndShippingAndBonus_isCorrect() async {
    let shippingRule = ShippingRule.template
    var project = Project.cosmicSurgery
    let reward1 =
      project.rewards[0]

      |> Reward.lens.shipping.enabled .~ true
    let reward2 =
      project.rewards[1]

      |> Reward.lens.shipping.enabled .~ true

    XCTAssertEqual(reward1.minimum, 6)
    XCTAssertEqual(reward2.minimum, 25)

    let data = PledgeViewData(
      project: project,
      rewards: [reward1, reward2],
      bonusSupport: 5,
      selectedShippingRule: shippingRule,
      selectedQuantities: [reward1.id: 1, reward2.id: 2],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      await self.runPayments()

      self.goToApplePayPaymentAuthorization.assertValueCount(1)
      let output = self.goToApplePayPaymentAuthorization.lastValue!

      XCTAssertEqual(output.project, project)
      XCTAssertEqual(output.hasNoReward, false)
      XCTAssertEqual(output.subtotal, 56)
      XCTAssertEqual(output.bonus, 5)
      XCTAssertEqual(output.shipping, 15)
      XCTAssertEqual(output.total, 76)

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testTapApplePayButton_createsPaymentIntent_beforePresentingAuthorizationController() async {
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()
      self.vm.inputs.applePayButtonTapped()
      await self.runPayments()
      self.goToApplePayPaymentAuthorization.assertDidEmitValue()

      let output = self.goToApplePayPaymentAuthorization.lastValue!
      XCTAssertEqual(output.paymentIntent, "foo")

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testTapApplePayButton_processingViewShows_createCheckoutSuccess() async {
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()
      self.vm.inputs.applePayButtonTapped()
      await self.runPayments()
      self.processingViewIsHidden.assertLastValue(false)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testTapApplePayButton_processingViewStaysHidden_createCheckoutFail() async {
    let mockService = MockService(
      createCheckoutResult: .failure(.couldNotParseErrorEnvelopeJSON)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()
      self.vm.inputs.applePayButtonTapped()
      await self.runPayments()
      // Processing view starts hidden and should stay hidden.
      self.processingViewIsHidden.assertDidNotEmitValue()
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testApplePay_completesCheckoutFlow() async {
    // Mock data for API requests
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let validateCheckout = ValidateCheckoutEnvelope(messages: ["message"])
    let completeSessionJsonString = """
      {
        "completeOnSessionCheckout": {
          "__typename": "CompleteOnSessionCheckoutPayload",
          "checkout": {
            "__typename": "Checkout",
            "id": "Q2hlY2tvdXQtMTk4MzM2OTIz",
            "state": "successful",
            "backing": {
              "requiresAction": false,
              "clientSecret": "super-secret",
              "__typename": "Backing"
            }
          }
        }
      }
      """
    let completeSessionData:
      GraphAPI.CompleteOnSessionCheckoutMutation
        .Data = try! testGraphObject(jsonString: completeSessionJsonString)
    let mockService = MockService(
      completeOnSessionCheckoutResult: .success(completeSessionData),
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent),
      validateCheckoutResult: .success(validateCheckout)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.configure(with: data)
      self.vm.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      await self.runPayments()

      self.processingViewIsHidden.assertLastValue(false)
      self.goToApplePayPaymentAuthorization.assertDidEmitValue()

      self.vm.inputs.applePayContextDidCreatePayment(with: "Fake Payment Method id")

      self.checkoutComplete.assertDidNotEmitValue()
      self.processingViewIsHidden.assertLastValue(false)

      self.vm.inputs.applePayContextDidComplete()

      await self.runPayments()

      self.checkoutComplete.assertDidEmitValue()
      self.processingViewIsHidden.assertLastValue(true)

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testApplePay_paymentIntentFails() async {
    // Mock data for API requests
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .failure(.couldNotParseErrorEnvelopeJSON)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.configure(with: data)
      self.vm.viewDidLoad()

      await self.runPayments()

      self.vm.inputs.applePayButtonTapped()

      self.processingViewIsHidden.assertLastValue(false)

      await self.runPayments()

      self.goToApplePayPaymentAuthorization.assertDidNotEmitValue()
      self.processingViewIsHidden.assertValues([true, false])

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  // MARK: - Pledge

  func testPledge_completesCheckoutFlow() async {
    // Mock data for API requests
    let validateCheckout = ValidateCheckoutEnvelope(messages: ["message"])
    let completeSessionJsonString = """
      {
        "completeOnSessionCheckout": {
          "__typename": "CompleteOnSessionCheckoutPayload",
          "checkout": {
            "__typename": "Checkout",
            "id": "Q2hlY2tvdXQtMTk4MzM2OTIz",
            "state": "successful",
            "backing": {
              "requiresAction": false,
              "clientSecret": "super-secret",
              "__typename": "Backing"
            }
          }
        }
      }
      """
    let completeSessionJson =
      try! JSONSerialization
      .jsonObject(with: completeSessionJsonString.data(using: .utf8)!)
    let completeSessionData:
      GraphAPI.CompleteOnSessionCheckoutMutation
        .Data = try! testGraphObject(jsonObject: completeSessionJson as! JSONObject)
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let graphUser =
      GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let userResponse = UserEnvelope<GraphUser>(me: graphUser)

    let mockService = MockService(
      completeOnSessionCheckoutResult: .success(completeSessionData),
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent),
      fetchGraphUserResult: .success(userResponse),
      validateCheckoutResult: .success(validateCheckout)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.configure(with: data)
      self.vm.viewDidLoad()

      await self.runPayments()

      self.vm.inputs
        .creditCardSelected(
          source: .savedCreditCard(UserCreditCards.visa.id, "pm_fake")
        )

      await self.runPayments()

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertValues([true, true])
      self.configurePledgeViewCTAContainerViewIsEnabled.assertValues([false, true])
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge, .latePledge])

      self.vm.inputs.submitButtonTapped()

      self.processingViewIsHidden.assertLastValue(false)

      await self.runPayments()

      self.validateCheckoutSuccess.assertDidEmitValue()
      self.checkoutComplete.assertDidNotEmitValue()

      self.vm.inputs.confirmPaymentSuccessful(clientSecret: "super-secret")
      await self.pledgeFeature.waitForOperations()

      self.checkoutComplete.assertDidEmitValue()
      self.processingViewIsHidden.assertLastValue(true)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testPledge_validationFails() async {
    // Mock data for API requests
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let graphUser =
      GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let userResponse = UserEnvelope<GraphUser>(me: graphUser)

    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent),
      fetchGraphUserResult: .success(userResponse),
      validateCheckoutResult: .failure(.couldNotParseErrorEnvelopeJSON)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.configure(with: data)
      self.vm.viewDidLoad()
      await self.runPayments()

      self.vm.inputs
        .creditCardSelected(
          source: .savedCreditCard(UserCreditCards.visa.id, "pm_fake")
        )

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertValues([true, true])
      self.configurePledgeViewCTAContainerViewIsEnabled.assertValues([false, true])
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge, .latePledge])

      self.vm.inputs.submitButtonTapped()

      self.processingViewIsHidden.assertLastValue(false)

      await self.runPayments()

      self.validateCheckoutSuccess.assertDidNotEmitValue()
      self.processingViewIsHidden.assertValues([false, true])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testCheckoutTerminated_cancelsCheckoutFlow() async {
    // Mock data for API requests
    let validateCheckout = ValidateCheckoutEnvelope(messages: ["message"])
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")

    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent),
      validateCheckoutResult: .success(validateCheckout)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.configure(with: data)
      self.vm.viewDidLoad()
      await self.runPayments()

      self.vm.inputs
        .creditCardSelected(
          source: .savedCreditCard(UserCreditCards.visa.id, "pm_fake")
        )

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertValues([true, true])
      self.configurePledgeViewCTAContainerViewIsEnabled.assertValues([false, true])
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge, .latePledge])

      self.vm.inputs.submitButtonTapped()

      self.processingViewIsHidden.assertLastValue(false)

      await self.runPayments()

      self.validateCheckoutSuccess.assertDidEmitValue()

      self.vm.inputs.checkoutTerminated()

      self.checkoutComplete.assertDidNotEmitValue()
      self.processingViewIsHidden.assertLastValue(true)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  // MARK: - Login

  func testPledgeViewCTAEnabled_afterSelectingNewPaymentMethod_LoggedIn() async {
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      serverConfig: ServerConfig.staging,
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    await withEnvironment(apiService: mockService, currentUser: .template) {
      let project = Project.cosmicSurgery
      let reward = Reward.noReward |> Reward.lens.minimum .~ 5

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: 0,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()

      self.vm.inputs
        .creditCardSelected(
          source: .savedCreditCard(UserCreditCards.visa.id, "pm_fake")
        )

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertValues([true, true])
      self.configurePledgeViewCTAContainerViewIsEnabled.assertValues([false, true])
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge, .latePledge])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testPledgeViewCTADisabled_onViewDidLoad_LoggedIn() async {
    let mockService = MockService(serverConfig: ServerConfig.staging)

    await withEnvironment(apiService: mockService, currentUser: .template) {
      let project = Project.cosmicSurgery
      let reward = Reward.noReward |> Reward.lens.minimum .~ 5

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: 0,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertLastValue(true)
      self.configurePledgeViewCTAContainerViewIsEnabled.assertLastValue(false)
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testPledgeViewCTADisabled_onViewDidLoad_LoggedOut() async {
    let mockService = MockService(serverConfig: ServerConfig.staging)

    await withEnvironment(apiService: mockService) {
      let project = Project.cosmicSurgery
      let reward = Reward.noReward |> Reward.lens.minimum .~ 5

      let data = PledgeViewData(
        project: project,
        rewards: [reward],
        bonusSupport: 0,
        selectedShippingRule: nil,
        selectedQuantities: [reward.id: 1],
        selectedLocationId: nil,
        refTag: nil,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()
      await self.runPayments()

      self.configurePledgeViewCTAContainerViewIsLoggedIn.assertLastValue(false)
      self.configurePledgeViewCTAContainerViewIsEnabled.assertLastValue(false)
      self.configurePledgeViewCTAContainerViewContext.assertValues([.latePledge])
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testGoToLoginSignup_emitsWhenLoggedOut_CheckoutErrorDoesNotEmit() async {
    let mockService = MockService(createCheckoutResult: .failure(.couldNotParseJSON))

    await withEnvironment(apiService: mockService, currentUser: nil) {
      let data = PledgeViewData(
        project: Project.template,
        rewards: [Reward.template],
        bonusSupport: nil,
        selectedShippingRule: nil,
        selectedQuantities: [Reward.template.id: 1],
        selectedLocationId: nil,
        refTag: .projectPage,
        context: .latePledge
      )

      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      self.vm.inputs.goToLoginSignupTapped()

      self.goToLoginSignup.assertDidEmitValue()
      self.checkoutError.assertDidNotEmitValue()
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }

  func testCreatePaymentIntent_emitsOnViewDidLoad() async {
    let paymentIntent = PaymentIntentEnvelope(clientSecret: "foo")
    let mockService = MockService(
      createCheckoutResult: .success(self.checkoutResponse),
      createPaymentIntentResult: .success(paymentIntent)
    )

    let project = Project.cosmicSurgery
    let reward = Reward.noReward |> Reward.lens.minimum .~ 5

    let data = PledgeViewData(
      project: project,
      rewards: [reward],
      bonusSupport: 0,
      selectedShippingRule: nil,
      selectedQuantities: [reward.id: 1],
      selectedLocationId: nil,
      refTag: nil,
      context: .latePledge
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm.inputs.configure(with: data)
      self.vm.inputs.viewDidLoad()

      await self.runPayments()

      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 1)
      await self.pledgeFeature.waitForOperations()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
      await self.pledgeFeature.waitForOperations()
    }
  }
}
