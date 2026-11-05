@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
@testable import StripePaymentSheet
import XCTest

@MainActor
final class PledgePaymentMethodsViewModelTests: TestCase {

  private func advancePayments(by _: DispatchTimeInterval = .seconds(0)) async {
    await self.vm.waitForPending()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
  }
  private func runPayments() async { await self.advancePayments() }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private var vm: PledgePaymentMethodsViewModel =
    PledgePaymentMethodsViewModel(stripeIntentService: MockStripeIntentService())
  private var mockStripeIntentService = MockStripeIntentService()

  private let userTemplate = GraphUser.template |> \.storedCards .~ UserCreditCards.template

  private let goToAddStripeCardIntent = PledgePaymentRecorder<PaymentSheetSetupData>()
  private let goToProject = PledgePaymentRecorder<Project>()
  private let notifyDelegateCreditCardSelected = PledgePaymentRecorder<PaymentSourceSelected>()
  private let notifyDelegateLoadPaymentMethodsError = PledgePaymentRecorder<String>()

  private let reloadPaymentMethodsCards = PledgePaymentRecorder<[UserCreditCards.CreditCard]>()
  private let reloadPaymentSheetPaymentMethodsCards = PledgePaymentRecorder<[PledgePaymentMethodCellData]>()
  private let reloadPaymentMethodsAvailableCardTypes = PledgePaymentRecorder<[Bool]>()
  private let reloadPaymentMethodsIsLoading = PledgePaymentRecorder<Bool>()
  private let reloadPaymentMethodsIsSelected = PledgePaymentRecorder<[Bool]>()
  private let reloadPaymentMethodsProjectCountry = PledgePaymentRecorder<[String]>()
  private let reloadPaymentMethodsSelectedCardId = PledgePaymentRecorder<String?>()
  private let reloadPaymentMethodsShouldReload = PledgePaymentRecorder<Bool>()
  private let addNewCardLoadingState = PledgePaymentRecorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    self.vm = PledgePaymentMethodsViewModel(stripeIntentService: self.mockStripeIntentService, sleep: { _ in try Task.checkCancellation() })
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .notifyDelegateCreditCardSelected(value): self.notifyDelegateCreditCardSelected.record(value)
      case let .notifyDelegateLoadPaymentMethodsError(value): self.notifyDelegateLoadPaymentMethodsError.record(value)
      case let .goToAddCardViaStripeScreen(value): self.goToAddStripeCardIntent.record(value)
      case let .updateAddNewCardLoading(value): self.addNewCardLoadingState.record(value)
      case let .reloadPaymentMethods(data):
        self.reloadPaymentMethodsCards.record(data.existingPaymentMethods.map { $0.card })
        self.reloadPaymentMethodsAvailableCardTypes.record(data.existingPaymentMethods.map { $0.isEnabled })
        self.reloadPaymentMethodsIsSelected.record(data.existingPaymentMethods.map { $0.isSelected })
        self.reloadPaymentMethodsProjectCountry.record(data.existingPaymentMethods.map { $0.projectCountry })
        self.reloadPaymentSheetPaymentMethodsCards.record(data.newPaymentMethods)
        self.reloadPaymentMethodsSelectedCardId.record(data.selectedPaymentMethod?.savedCreditCardId)
        self.reloadPaymentMethodsShouldReload.record(data.shouldReload)
        self.reloadPaymentMethodsIsLoading.record(data.isLoading)
      }
    }
  }

  func testAccountChangeDuringCardDelaySuppressesOldCards() async {
    let gate = PledgePaymentDelayGate()
    let vm = PledgePaymentMethodsViewModel(stripeIntentService: self.mockStripeIntentService, sleep: { _ in
      try await gate.wait()
    })
    var completedLoads = 0
    vm.onEvent = { event in
      if case let .reloadPaymentMethods(data) = event, !data.isLoading { completedLoads += 1 }
    }
    let response = UserEnvelope<GraphUser>(me: self.userTemplate)
    await withEnvironment(apiService: MockService(fetchGraphUserResult: .success(response)), currentUser: .template) {
      vm.configure(with: (.template, .template, "checkout", .template, .pledge, nil))
      vm.viewDidLoad()
      await gate.waitUntilBlocked()
      self.mockStripeIntentService.paymentsFeature.sessionFeature.sessionChanged()
      gate.resume()
      await vm.waitForPending()
      XCTAssertEqual(completedLoads, 0)
    }
  }

  // MARK: - New card added

  func testReloadPaymentMethods_NewCardAdded_UnavailableIsLast() async {
    let sampleSetupIntent = "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ"

    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")

    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
      self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([[], response.me.storedCards.storedCards])
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([
        [],
        [true, true, true, true, true, true, true, false]
      ])
      self.reloadPaymentMethodsIsSelected.assertValues([
        [],
        [true, false, false, false, false, false, false, false]
      ], "First card is selected")
      self.reloadPaymentMethodsProjectCountry.assertValues([
        [],
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" }
      ], "One card is unavailable")
      self.reloadPaymentMethodsSelectedCardId
        .assertValues([nil, response.me.storedCards.storedCards.first?.id])
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])
      self.reloadPaymentMethodsIsLoading.assertValues([true, false])

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 2)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: sampleSetupIntent,
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 3)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour,
        addPaymentSheetResponse.createPaymentSource.paymentSource.lastFour
      )
      XCTAssertEqual(
        self.reloadPaymentMethodsSelectedCardId.lastValue!,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )

      self.reloadPaymentMethodsCards.assertValues(
        [
          [],
          [
            UserCreditCards.amex,
            UserCreditCards.masterCard,
            UserCreditCards.visa,
            UserCreditCards.diners,
            UserCreditCards.jcb,
            UserCreditCards.discover,
            UserCreditCards.unionPay,
            UserCreditCards.generic
          ], [
            UserCreditCards.amex,
            UserCreditCards.masterCard,
            UserCreditCards.visa,
            UserCreditCards.diners,
            UserCreditCards.jcb,
            UserCreditCards.discover,
            UserCreditCards.unionPay,
            UserCreditCards.generic
          ]
        ]
      )
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([
        [],
        [true, true, true, true, true, true, true, false],
        [true, true, true, true, true, true, true, false]
      ])
      self.reloadPaymentMethodsIsSelected.assertValues([
        [],
        [true, false, false, false, false, false, false, false],
        [false, false, false, false, false, false, false, false]
      ], "Deselect pre-existing card.")
      self.reloadPaymentMethodsProjectCountry.assertValues([
        [],
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" },
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" }
      ], "No changes")
      self.reloadPaymentMethodsSelectedCardId.assertValues([
        nil,
        response.me.storedCards.storedCards.first?.id,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      ])
      self.reloadPaymentMethodsShouldReload.assertValues([true, true, true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_NewCardAdded_ProjectHasBacking() async {
    let setupIntent = "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ"
    let cards = UserCreditCards.withCards([
      UserCreditCards.amex,
      UserCreditCards.visa,
      UserCreditCards.masterCard,
      UserCreditCards.diners,
      UserCreditCards.generic
    ])
    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")

    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    self.reloadPaymentMethodsCards.assertDidNotEmitValue()
    self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
    self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
    self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
    self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
    self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
    self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      let paymentSource = Backing.PaymentSource.template
        |> \.id .~ "2" // Matches UserCreditCards.visa template id

      let project = Project.template
        |> Project.lens.personalization.backing .~ (
          Backing.template
            |> Backing.lens.paymentSource .~ paymentSource
        )

      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          .template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([
        [],
        [
          UserCreditCards.visa,
          UserCreditCards.amex,
          UserCreditCards.masterCard,
          UserCreditCards.diners,
          UserCreditCards.generic
        ]
      ], "Card used for backing is first")
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([
        [],
        [true, true, true, true, false]
      ])
      self.reloadPaymentMethodsIsSelected.assertValues([
        [],
        [true, false, false, false, false]
      ], "First card is selected")
      self.reloadPaymentMethodsProjectCountry.assertValues([
        [],
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" }
      ], "One card is unavailable")
      self.reloadPaymentMethodsSelectedCardId.assertValues(
        [nil, UserCreditCards.visa.id],
        "Card used for backing is selected"
      )
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 2)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 3)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour,
        addPaymentSheetResponse.createPaymentSource.paymentSource.lastFour
      )
      XCTAssertEqual(
        self.reloadPaymentMethodsSelectedCardId.lastValue!,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )

      self.reloadPaymentMethodsCards.assertValues([
        [],
        [
          UserCreditCards.visa,
          UserCreditCards.amex,
          UserCreditCards.masterCard,
          UserCreditCards.diners,
          UserCreditCards.generic
        ],
        [
          UserCreditCards.visa,
          UserCreditCards.amex,
          UserCreditCards.masterCard,
          UserCreditCards.diners,
          UserCreditCards.generic
        ]
      ], "No new card added to payment methods.")
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([
        [],
        [true, true, true, true, false],
        [true, true, true, true, false]
      ])
      self.reloadPaymentMethodsIsSelected.assertValues([
        [],
        [true, false, false, false, false],
        [false, false, false, false, false]
      ], "Deselect previously selected card.")
      self.reloadPaymentMethodsProjectCountry.assertValues([
        [],
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" },
        (0...response.me.storedCards.storedCards.count - 1).map { _ in "Brooklyn, NY" }
      ], "No changes")
      self.reloadPaymentMethodsSelectedCardId.assertValues(
        [
          nil,
          UserCreditCards.visa.id,
          addPaymentSheetResponse.createPaymentSource.paymentSource.id
        ],
        "No changes"
      )
      self.reloadPaymentMethodsShouldReload.assertValues([true, true, true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_NewCardAdded_NoStoredCards() async {
    let emptyTemplate = GraphUser.template |> \.storedCards .~ .emptyTemplate
    let response = UserEnvelope<GraphUser>(me: emptyTemplate)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")

    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentSheetPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
      self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([[], []])
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 2)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([[], []])
      self.reloadPaymentMethodsIsSelected.assertValues([[], []])
      self.reloadPaymentMethodsProjectCountry.assertValues([[], []])
      self.reloadPaymentMethodsSelectedCardId.assertValues([nil, nil], "No card to select")
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.count, 3)
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[0].isEmpty
      )
      XCTAssertTrue(
        self.reloadPaymentSheetPaymentMethodsCards.values[1].isEmpty
      )
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour,
        addPaymentSheetResponse.createPaymentSource.paymentSource.lastFour
      )
      self.reloadPaymentMethodsCards.assertValues([[], [], []])
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([[], [], []])
      self.reloadPaymentMethodsIsSelected.assertValues([[], [], []])
      self.reloadPaymentMethodsProjectCountry.assertValues([[], [], []])
      self.reloadPaymentMethodsSelectedCardId
        .assertValues([nil, nil, addPaymentSheetResponse.createPaymentSource.paymentSource.id])
      self.reloadPaymentMethodsShouldReload.assertValues([true, true, true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_NewPaymentSheetCardAdded_WithExistingStoredCard_Success() async {
    let userTemplate = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([
      UserCreditCards.masterCard
    ])
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentSheetPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([[], [UserCreditCards.masterCard]])
      self.reloadPaymentSheetPaymentMethodsCards.assertValueCount(2)
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.first?.count, 0)
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.last?.count, 0)
      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [nil, UserCreditCards.masterCard.id],
          "Previous card selected before new payment sheet card added."
        )
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])
      self.reloadPaymentMethodsIsLoading.assertValues([true, false])

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      let expectedPaymentSheetPaymentMethodCard = PledgePaymentMethodCellData(
        card: addPaymentSheetResponse.createPaymentSource.paymentSource,
        isEnabled: true,
        isSelected: true,
        projectCountry: "US",
        isErroredPaymentMethod: false
      )

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      self.reloadPaymentMethodsCards
        .assertValues(
          [[], [UserCreditCards.masterCard], [UserCreditCards.masterCard]],
          "Previous non payment sheet cards still emit."
        )
      self.reloadPaymentSheetPaymentMethodsCards.assertValueCount(3)
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour,
        expectedPaymentSheetPaymentMethodCard.card.lastFour
      )
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.isSelected,
        expectedPaymentSheetPaymentMethodCard.isSelected
      )
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.isEnabled,
        expectedPaymentSheetPaymentMethodCard.isEnabled
      )
      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [nil, UserCreditCards.masterCard.id, expectedPaymentSheetPaymentMethodCard.card.id]
        )
      self.reloadPaymentMethodsShouldReload.assertValues([true, true, true])
      self.reloadPaymentMethodsIsLoading.assertValues([true, false, false])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_NewPaymentSheetCardAdded_WithExistingStoredCard_ErroredBacking_Success() async {
    let userTemplate = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([
      UserCreditCards.masterCard
    ])
    let projectWithErroredBacking = Project.template
      |> \.personalization.backing .~ Backing.errored

    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentSheetPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          projectWithErroredBacking,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([[], [UserCreditCards.masterCard]])
      self.reloadPaymentSheetPaymentMethodsCards.assertValueCount(2)
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.first?.count, 0)
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.values.last?.count, 0)
      self.reloadPaymentMethodsSelectedCardId
        .assertValues([nil, nil], "No selected card due to backing error.")
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])
      self.reloadPaymentMethodsIsLoading.assertValues([true, false])

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      let expectedPaymentSheetPaymentMethodCard = PledgePaymentMethodCellData(
        card: addPaymentSheetResponse.createPaymentSource.paymentSource,
        isEnabled: true,
        isSelected: true,
        projectCountry: "US",
        isErroredPaymentMethod: false
      )

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      self.reloadPaymentMethodsCards
        .assertValues(
          [[], [UserCreditCards.masterCard], [UserCreditCards.masterCard]],
          "Previous non payment sheet cards still emit."
        )
      self.reloadPaymentSheetPaymentMethodsCards.assertValueCount(3)
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour,
        expectedPaymentSheetPaymentMethodCard.card.lastFour
      )
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.isSelected,
        expectedPaymentSheetPaymentMethodCard.isSelected
      )
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.isEnabled,
        expectedPaymentSheetPaymentMethodCard.isEnabled
      )
      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [nil, nil, expectedPaymentSheetPaymentMethodCard.card.id],
          "Newly added payment sheet card still selected even on errored backing."
        )
      self.reloadPaymentMethodsShouldReload.assertValues([true, true, true])
      self.reloadPaymentMethodsIsLoading.assertValues([true, false, false])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testSelectNewPaymentSheetCard_ViceVersa_AfterNewPaymentSheetCardsAdded_Success() async {
    let userTemplate = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([
      UserCreditCards.masterCard
    ])
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentSheetPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [nil, UserCreditCards.masterCard.id],
          "Previous card selected before new payment sheet card added."
        )

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [nil, UserCreditCards.masterCard.id, addPaymentSheetResponse.createPaymentSource.paymentSource.id]
        )

      let indexPath = IndexPath(row: 1, section: 0)

      self.vm.didSelectRowAtIndexPath(indexPath)
      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [
            nil,
            UserCreditCards.masterCard.id,
            addPaymentSheetResponse.createPaymentSource.paymentSource.id,
            UserCreditCards.masterCard.id
          ]
        )

      let indexPath2 = IndexPath(row: 0, section: 0)

      self.vm.didSelectRowAtIndexPath(indexPath2)
      self.reloadPaymentMethodsSelectedCardId
        .assertValues(
          [
            nil,
            UserCreditCards.masterCard.id,
            addPaymentSheetResponse.createPaymentSource.paymentSource.id,
            UserCreditCards.masterCard.id,
            addPaymentSheetResponse.createPaymentSource.paymentSource.id
          ],
          "No card to select after payment sheet card added."
        )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_FirstCardUnavailable_UnavailableCardOrderedLast() async {
    let cards = UserCreditCards.withCards([
      UserCreditCards.discover,
      UserCreditCards.visa,
      UserCreditCards.amex
    ])

    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let mockService = MockService(fetchGraphUserResult: .success(response))
    let project = Project.template
      |> \.availableCardTypes .~ ["AMEX", "VISA", "MASTERCARD"]

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
      self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()

      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([
        [],
        [
          UserCreditCards.visa,
          UserCreditCards.amex,
          UserCreditCards.discover
        ]
      ])
      self.reloadPaymentMethodsAvailableCardTypes.assertValues([[], [true, true, false]])
      self.reloadPaymentMethodsIsSelected.assertValues([[], [true, false, false]])
      self.reloadPaymentMethodsProjectCountry.assertValues([
        [],
        ["Brooklyn, NY", "Brooklyn, NY", "Brooklyn, NY"]
      ])
      self.reloadPaymentMethodsSelectedCardId.assertValues([nil, UserCreditCards.visa.id])
      self.reloadPaymentMethodsShouldReload.assertValues([true, true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testReloadPaymentMethods_LoggedOut() async {
    let response = UserEnvelope<GraphUser>(me: GraphUser.template)
    let mockService = MockService(fetchGraphUserResult: .success(response))

    await withEnvironment(apiService: mockService, currentUser: nil) {
      self.vm.viewDidLoad()

      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
      self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()
      self.notifyDelegateLoadPaymentMethodsError.assertDidNotEmitValue()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertDidNotEmitValue()
      self.reloadPaymentMethodsAvailableCardTypes.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsSelected.assertDidNotEmitValue()
      self.reloadPaymentMethodsProjectCountry.assertDidNotEmitValue()
      self.reloadPaymentMethodsSelectedCardId.assertDidNotEmitValue()
      self.reloadPaymentMethodsShouldReload.assertDidNotEmitValue()
      self.reloadPaymentMethodsIsLoading.assertDidNotEmitValue()
      self.notifyDelegateLoadPaymentMethodsError.assertDidNotEmitValue()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testCreditCardSelected() async {
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let mockService = MockService(fetchGraphUserResult: .success(response))

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.notifyDelegateCreditCardSelected.assertValues(
        [PaymentSourceSelected.savedCreditCard(UserCreditCards.amex.id, "pm_fake_amex")],
        "First card selected by default"
      )

      let discoverIndexPath = IndexPath(
        row: 5,
        section: PaymentMethodsTableViewSection.paymentMethods.rawValue
      )

      self.vm.didSelectRowAtIndexPath(discoverIndexPath)

      self.notifyDelegateCreditCardSelected.assertValues([
        PaymentSourceSelected.savedCreditCard(UserCreditCards.amex.id, "pm_fake_amex"),
        PaymentSourceSelected.savedCreditCard(UserCreditCards.discover.id, "pm_fake_discover")
      ])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPaymentSheetCardSetupIntent_UsedToNotifyDelegate_WhenPaymentSheetCardAdded_Success() async {
    let userTemplateWithCards = self.userTemplate
      |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let response = UserEnvelope<GraphUser>(me: userTemplateWithCards)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId(
      "999",
      stripeCardId: nil
    )
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.notifyDelegateCreditCardSelected.assertValues(
        [PaymentSourceSelected.savedCreditCard(UserCreditCards.visa.id, "pm_fake_visa")],
        "First card selected by default"
      )

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake_from_viewmodel"
        )

      await self.advancePayments(by: .seconds(1))

      self.notifyDelegateCreditCardSelected.assertValues([
        PaymentSourceSelected.savedCreditCard(UserCreditCards.visa.id, "pm_fake_visa"),
        PaymentSourceSelected
          .savedCreditCard(
            addPaymentSheetResponse.createPaymentSource.paymentSource.id,
            "pm_fake_from_viewmodel"
          )
      ])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPaymentSheetCardPaymentIntent_UsedToNotifyDelegate_WhenPaymentSheetCardAdded_Success() async {
    let userTemplateWithCards = self.userTemplate
      |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let response = UserEnvelope<GraphUser>(me: userTemplateWithCards)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId(
      "999",
      stripeCardId: "pm_fake_from_response"
    )
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          Project.template,
          "checkoutID",
          Reward.template,
          .latePledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.notifyDelegateCreditCardSelected.assertValues(
        [PaymentSourceSelected.savedCreditCard(UserCreditCards.visa.id, "pm_fake_visa")],
        "First card selected by default"
      )

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }

      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "fake_payment_intent",
          paymentMethod: "pm_fake_from_response"
        )

      await self.advancePayments(by: .seconds(1))

      self.notifyDelegateCreditCardSelected.assertValues([
        PaymentSourceSelected.savedCreditCard(UserCreditCards.visa.id, "pm_fake_visa"),
        PaymentSourceSelected
          .savedCreditCard(
            addPaymentSheetResponse.createPaymentSource.paymentSource.id,
            "pm_fake_from_response"
          )
      ])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testCantSelectUnavailableCards() async {
    let cards = UserCreditCards.withCards([
      UserCreditCards.visa,
      UserCreditCards.discover,
      UserCreditCards.amex
    ])
    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let mockService = MockService(fetchGraphUserResult: .success(response))
    let project = Project.template
      |> \.availableCardTypes .~ ["AMEX", "VISA", "MASTERCARD"]

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      self.reloadPaymentMethodsCards.assertValues([
        [],
        [
          UserCreditCards.visa,
          UserCreditCards.amex,
          UserCreditCards.discover
        ]
      ], "Discover unavailable and ordered last")

      let discoverIndexPath = IndexPath(
        row: 2,
        section: PaymentMethodsTableViewSection.paymentMethods.rawValue
      )
      XCTAssertNil(self.vm.willSelectRowAtIndexPath(discoverIndexPath))

      let amexIndexPath = IndexPath(
        row: 1,
        section: PaymentMethodsTableViewSection.paymentMethods.rawValue
      )
      XCTAssertEqual(self.vm.willSelectRowAtIndexPath(amexIndexPath), amexIndexPath)

      let outOfBoundsIndexPath = IndexPath(
        row: 1, section: PaymentMethodsTableViewSection.loading.rawValue
      )
      XCTAssertNil(self.vm.willSelectRowAtIndexPath(outOfBoundsIndexPath))
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewCard_PledgeContext_Failure() async {
    let project = Project.template
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      let addNewCardIndexPath = IndexPath(
        row: 0,
        section: PaymentMethodsTableViewSection.addNewCard.rawValue
      )
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      self.goToAddStripeCardIntent.assertDidNotEmitValue()

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewCard_UpdatePledgeContext_Failure() async {
    let project = Project.template
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .update,
          .discovery
        ))

      let addNewCardIndexPath = IndexPath(
        row: 0,
        section: PaymentMethodsTableViewSection.addNewCard.rawValue
      )
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      self.goToAddStripeCardIntent.assertDidNotEmitValue()

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewCard_UpdateRewardContexts_Failure() async {
    let project = Project.template
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .updateReward,
          .discovery
        ))

      let addNewCardIndexPath = IndexPath(
        row: 0,
        section: PaymentMethodsTableViewSection.addNewCard.rawValue
      )
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      self.goToAddStripeCardIntent.assertDidNotEmitValue()

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewCard_ChangePaymentMethodContext_Failure() async {
    let project = Project.template
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .changePaymentMethod,
          .discovery
        ))

      let addNewCardIndexPath = IndexPath(
        row: 0,
        section: PaymentMethodsTableViewSection.addNewCard.rawValue
      )
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      self.goToAddStripeCardIntent.assertDidNotEmitValue()

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewCard_FixPaymentMethodContext_Failure() async {
    let project = Project.template
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .fixPaymentMethod,
          .discovery
        ))

      let addNewCardIndexPath = IndexPath(
        row: 0,
        section: PaymentMethodsTableViewSection.addNewCard.rawValue
      )
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 0)

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCard_NoStoredCards_Success() async {
    let project = Project.template
    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([])
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue, [])
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.id,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCard_NoStoredCards_NewCardIsUnavailable_AddsButIsNotSelected() async {
    let project = Project.template
      |> \.availableCardTypes .~ []

    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([])
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue, [])
      let paymentSheetCard = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last

      XCTAssertNotNil(paymentSheetCard?.card)
      XCTAssertEqual(
        paymentSheetCard?.card.id,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )
      XCTAssertFalse(paymentSheetCard!.isEnabled)
      XCTAssertFalse(paymentSheetCard!.isSelected)

      self.reloadPaymentMethodsSelectedCardId
        .assertValues([nil, nil, nil])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCard_WithStoredCards_NewCardIsUnavailable_AddsButIsNotSelected() async {
    let project = Project.template
      |> \.availableCardTypes .~ [CreditCardType.amex.rawValue]

    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.amex])
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }
      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue?.last?.id, UserCreditCards.amex.id)

      let paymentSheetCard = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last

      XCTAssertNotNil(paymentSheetCard?.card)
      XCTAssertEqual(
        paymentSheetCard?.card.id,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )
      XCTAssertFalse(paymentSheetCard?.isEnabled ?? false)
      XCTAssertFalse(paymentSheetCard?.isSelected ?? false)

      self.reloadPaymentMethodsSelectedCardId
        .assertValues([nil, UserCreditCards.amex.id, UserCreditCards.amex.id])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCard_WithStoredCards_Sucess() async {
    let project = Project.template
    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      guard let paymentMethod = STPPaymentMethod.amexStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }

      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue, [UserCreditCards.visa])
      XCTAssertNotNil(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.lastFour)
      XCTAssertEqual(
        self.reloadPaymentSheetPaymentMethodsCards.lastValue?.last?.card.id,
        addPaymentSheetResponse.createPaymentSource.paymentSource.id
      )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testAddNewStripeCard_SavingCardReturnsError_NotifiesDelegateOfError() async {
    let project = Project.template
    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("999")
    let error = ErrorEnvelope.couldNotParseErrorEnvelopeJSON
    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .failure(error),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      guard let paymentMethod = STPPaymentMethod.amexStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }

      await self.advancePayments(by: .seconds(1))

      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.notifyDelegateLoadPaymentMethodsError.lastValue, error.localizedDescription)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testAddNewStripeCard_MultipleCards_StoresAllCards_WithMostRecentCardFirst() async {
    let project = Project.template
    let graphUser = GraphUser.template |> \.storedCards .~ UserCreditCards.withCards([UserCreditCards.visa])
    let response = UserEnvelope<GraphUser>(me: graphUser)

    let addPaymentSheetResponse1 = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("1")
    let addPaymentSheetResponse2 = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("2")
    let addPaymentSheetResponse3 = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplateWithId("3")

    let mockServiceInitial = MockService(
      fetchGraphUserResult: .success(response)
    )

    let mockService1 = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse1)
    )
    let mockService2 = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse2)
    )
    let mockService3 = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse3)
    )

    await withEnvironment(
      apiService: mockServiceInitial,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))

      await self.advancePayments(by: .seconds(1))
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 0)
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }

    await withEnvironment(
      apiService: mockService1,
      currentUser: User.template
    ) {
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_fake",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 1)
      let firstCardInList = self.reloadPaymentSheetPaymentMethodsCards.lastValue?[0]
      XCTAssertEqual(firstCardInList?.card.id, "1")
      XCTAssertTrue(firstCardInList?.isSelected ?? false)
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }

    await withEnvironment(
      apiService: mockService2,
      currentUser: User.template
    ) {
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_fake",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 2)
      let firstCardInList = self.reloadPaymentSheetPaymentMethodsCards.lastValue?[0]
      XCTAssertEqual(firstCardInList?.card.id, "2")
      XCTAssertTrue(firstCardInList?.isSelected ?? false)
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }

    await withEnvironment(
      apiService: mockService3,
      currentUser: User.template
    ) {
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "seti_fake",
          paymentMethod: "pm_fake"
        )

      await self.advancePayments(by: .seconds(1))

      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 3)
      let firstCardInList = self.reloadPaymentSheetPaymentMethodsCards.lastValue?[0]
      XCTAssertEqual(firstCardInList?.card.id, "3")
      XCTAssertTrue(firstCardInList?.isSelected ?? false)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testLoadingStateAddNewCard_ShowAndHide_Success() async {
    let project = Project.template
    let addNewCardIndexPath = IndexPath(
      row: 0,
      section: PaymentMethodsTableViewSection.addNewCard.rawValue
    )

    let mockService = MockService(createStripeSetupIntentResult: .failure(.couldNotParseErrorEnvelopeJSON))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      await self.runPayments()

      self.addNewCardLoadingState.assertValues([true, false])

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testLoadingStateAddNewCard_ShowAndHide_NonCardSelectionNonAddNewCardContext_Success() async {
    let project = Project.template

    let mockService = MockService(createStripeSetupIntentResult: .failure(.couldNotParseErrorEnvelopeJSON))

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.shouldCancelPaymentSheetAppearance(state: true)
      self.vm.shouldCancelPaymentSheetAppearance(state: false)
      self.vm.shouldCancelPaymentSheetAppearance(state: false)
      self.vm.shouldCancelPaymentSheetAppearance(state: false)

      await self.runPayments()

      self.addNewCardLoadingState.assertValues([false, true, true, true])

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 0)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testLoadingStateAddNewCard_ShowAndHide_CardSelectionContext_Success() async {
    let cards = UserCreditCards.withCards([
      UserCreditCards.visa,
      UserCreditCards.masterCard,
      UserCreditCards.amex
    ])
    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let response = UserEnvelope<GraphUser>(me: graphUser)
    let mockService = MockService(fetchGraphUserResult: .success(response))
    let project = Project.template
      |> \.availableCardTypes .~ ["AMEX", "VISA", "MASTERCARD"]
    let paymentMethodSelectionIndexPath = IndexPath(
      row: 1,
      section: PaymentMethodsTableViewSection.paymentMethods.rawValue
    )

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.shouldCancelPaymentSheetAppearance(state: false)

      await self.advancePayments(by: .seconds(1))
      self.vm.didSelectRowAtIndexPath(paymentMethodSelectionIndexPath)

      await self.runPayments()

      self.addNewCardLoadingState.assertValues([true, false])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCardScreen_PledgeContext_Success() async {
    let project = Project.template
    let addNewCardIndexPath = IndexPath(
      row: 0,
      section: PaymentMethodsTableViewSection.addNewCard.rawValue
    )
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))
    var configuration = PaymentSheet.Configuration()
    configuration.merchantDisplayName = Strings.general_accessibility_kickstarter()
    configuration.allowsDelayedPaymentMethods = true

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.goToAddStripeCardIntent.lastValue?.clientSecret, "test")
      XCTAssertEqual(
        self.goToAddStripeCardIntent.lastValue?.configuration.merchantDisplayName,
        Strings.general_accessibility_kickstarter()
      )

      guard let allowedDelayedPaymentMethods = self.goToAddStripeCardIntent.lastValue?.configuration
        .allowsDelayedPaymentMethods else {
        XCTFail()

        return
      }

      XCTAssertTrue(allowedDelayedPaymentMethods)
      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToAddNewStripeCardScreen_LatePledgeContext_Success() async {
    let project = Project.template
    let addNewCardIndexPath = IndexPath(
      row: 0,
      section: PaymentMethodsTableViewSection.addNewCard.rawValue
    )
    let envelope = ClientSecretEnvelope(clientSecret: "test")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))
    var configuration = PaymentSheet.Configuration()
    configuration.merchantDisplayName = Strings.general_accessibility_kickstarter()
    configuration.allowsDelayedPaymentMethods = true

    await withEnvironment(
      apiService: mockService,
      currentUser: User.template
    ) {
      self.vm.viewDidLoad()
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .latePledge,
          .discovery
        ))
      self.vm.didSelectRowAtIndexPath(addNewCardIndexPath)

      await self.runPayments()

      XCTAssertEqual(self.goToAddStripeCardIntent.values.count, 1)
      XCTAssertEqual(self.goToAddStripeCardIntent.lastValue?.clientSecret, "test")
      XCTAssertEqual(
        self.goToAddStripeCardIntent.lastValue?.configuration.merchantDisplayName,
        Strings.general_accessibility_kickstarter()
      )

      guard let allowedDelayedPaymentMethods = self.goToAddStripeCardIntent.lastValue?.configuration
        .allowsDelayedPaymentMethods else {
        XCTFail()

        return
      }

      XCTAssertTrue(allowedDelayedPaymentMethods)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  // A test for MBL-1550
  func testAddNewUnavailablePaymentMethod_userAlreadyHasCard_selectsValidPaymentMethod() async {
    let cards = UserCreditCards.withCards([
      UserCreditCards.visa
    ])

    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let graphUserResponse = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplate

    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(graphUserResponse)
    )
    let project = Project.template
      |> \.availableCardTypes .~ ["VISA"]

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      // There is one card, it's enabled, and it's selected
      XCTAssertEqual(self.reloadPaymentMethodsIsSelected.lastValue, [true])
      XCTAssertEqual(self.reloadPaymentMethodsAvailableCardTypes.lastValue, [true])
      XCTAssertEqual(self.reloadPaymentMethodsSelectedCardId.lastValue, UserCreditCards.visa.id)

      // Add a new card
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "si_fake",
          paymentMethod: "pm_fake"
        )

      await self.runPayments()

      // There are now two cards, one in each section
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 1)
      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue?.count, 1)

      // The newly added card is disabled and not selected
      let newCardData = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.first
      XCTAssertEqual(newCardData?.isEnabled, false)
      XCTAssertEqual(newCardData?.isSelected, false)

      // The previously added and available card is still selected
      XCTAssertEqual(self.reloadPaymentMethodsSelectedCardId.lastValue, UserCreditCards.visa.id)
      XCTAssertEqual(self.reloadPaymentMethodsIsSelected.lastValue, [true])
      XCTAssertEqual(self.reloadPaymentMethodsAvailableCardTypes.lastValue, [true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testAddNewUnavailablePaymentMethod_userHasNoCards_noCardSelected() async {
    let cards = UserCreditCards.withCards([])

    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let graphUserResponse = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponse = CreatePaymentSourceEnvelope.paymentSourceSuccessTemplate

    let mockService = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponse),
      fetchGraphUserResult: .success(graphUserResponse)
    )
    let project = Project.template
      |> \.availableCardTypes .~ ["VISA"]

    await withEnvironment(apiService: mockService, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      // There are no cards
      XCTAssertEqual(self.reloadPaymentMethodsIsSelected.lastValue, [])
      XCTAssertEqual(self.reloadPaymentMethodsAvailableCardTypes.lastValue, [])
      XCTAssertNil(self.reloadPaymentMethodsSelectedCardId.lastValue ?? nil)

      // Add a new card
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "si_fake",
          paymentMethod: "pm_fake"
        )

      await self.runPayments()

      // There is now one card, in the new section
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 1)
      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue?.count, 0)

      // The newly added card is disabled and not selected
      let newCardData = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.first
      XCTAssertEqual(newCardData?.isEnabled, false)
      XCTAssertEqual(newCardData?.isSelected, false)
      XCTAssertNil(self.reloadPaymentMethodsSelectedCardId.lastValue ?? nil)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testAddNewUnavailablePaymentMethod_afterAddingAvailableCard_onlyAvailableCardSelected() async {
    let cards = UserCreditCards.withCards([])

    let graphUser = GraphUser.template |> \.storedCards .~ cards
    let graphUserResponse = UserEnvelope<GraphUser>(me: graphUser)
    let addPaymentSheetResponseVisa = CreatePaymentSourceEnvelope(
      createPaymentSource: .init(isSuccessful: true, paymentSource: UserCreditCards.visa)
    )
    let addPaymentSheetResponseDiscover = CreatePaymentSourceEnvelope(
      createPaymentSource: .init(isSuccessful: true, paymentSource: UserCreditCards.discover)
    )

    let mockService1 = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponseVisa),
      fetchGraphUserResult: .success(graphUserResponse)
    )

    let mockService2 = MockService(
      addPaymentSheetPaymentSourceResult: .success(addPaymentSheetResponseDiscover)
    )

    let project = Project.template
      |> \.availableCardTypes .~ ["VISA"]

    await withEnvironment(apiService: mockService1, currentUser: User.template) {
      self.vm
        .configure(with: (
          User.template,
          project,
          "checkoutID",
          Reward.template,
          .pledge,
          .discovery
        ))
      self.vm.viewDidLoad()

      await self.runPayments()

      // There are no cards
      XCTAssertEqual(self.reloadPaymentMethodsIsSelected.lastValue, [])
      XCTAssertEqual(self.reloadPaymentMethodsAvailableCardTypes.lastValue, [])
      XCTAssertNil(self.reloadPaymentMethodsSelectedCardId.lastValue ?? nil)

      // Add a new card (the visa)
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "si_fake",
          paymentMethod: "pm_fake"
        )

      await self.runPayments()

      // There is now one card, in the new section
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 1)
      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue?.count, 0)

      // The newly added card is enabled and selected
      let newCardData = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.first
      XCTAssertEqual(newCardData?.isEnabled, true)
      XCTAssertEqual(newCardData?.isSelected, true)
      XCTAssertEqual(self.reloadPaymentMethodsSelectedCardId.lastValue, UserCreditCards.visa.id)
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }

    await withEnvironment(apiService: mockService2, currentUser: User.template) {
      // Add another new card (the discover)
      self.vm
        .paymentSheetDidAdd(
          clientSecret: "si_fake",
          paymentMethod: "pm_fake"
        )

      await self.runPayments()

      // There are now two cards, in the new section
      XCTAssertEqual(self.reloadPaymentSheetPaymentMethodsCards.lastValue?.count, 2)
      XCTAssertEqual(self.reloadPaymentMethodsCards.lastValue?.count, 0)

      // The discover is disabled and not selected.
      let discoverCardData = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.first(where: { (
        card: UserCreditCards.CreditCard,
        _: Bool,
        _: Bool,
        _: String,
        _: Bool
      ) in
        card.id == UserCreditCards.discover.id
      })
      XCTAssertNotNil(discoverCardData)
      XCTAssertEqual(discoverCardData?.card.id, UserCreditCards.discover.id)
      XCTAssertEqual(discoverCardData?.isEnabled, false)
      XCTAssertEqual(discoverCardData?.isSelected, false)

      // The visa is enabled and selected.
      let visaCardData = self.reloadPaymentSheetPaymentMethodsCards.lastValue?.first(where: { (
        card: UserCreditCards.CreditCard,
        _: Bool,
        _: Bool,
        _: String,
        _: Bool
      ) in
        card.id == UserCreditCards.visa.id
      })
      XCTAssertNotNil(visaCardData)
      XCTAssertEqual(visaCardData?.card.id, UserCreditCards.visa.id)
      XCTAssertEqual(visaCardData?.isEnabled, true)
      XCTAssertEqual(visaCardData?.isSelected, true)

      // The visa is still selected
      XCTAssertEqual(self.reloadPaymentMethodsSelectedCardId.lastValue, UserCreditCards.visa.id)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }
}

private final class PledgePaymentRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    self.assertValueCount(0, message, file: file, line: line)
  }
}
private extension PledgePaymentRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}

@MainActor
private final class PledgePaymentDelayGate {
  private var continuation: CheckedContinuation<Void, Error>?
  func wait() async throws { try await withCheckedThrowingContinuation { self.continuation = $0 } }
  func waitUntilBlocked() async { while self.continuation == nil { await Task.yield() } }
  func resume() { self.continuation?.resume(); self.continuation = nil }
}
