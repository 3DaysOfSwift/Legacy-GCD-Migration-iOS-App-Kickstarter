@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
@testable import Stripe
import XCTest

@MainActor
internal final class PaymentMethodSettingsViewModelTests: TestCase {

  private func advancePayments(by _: DispatchTimeInterval = .seconds(0)) async {
    await self.vm.waitForPending()
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
  }
  private func runPayments() async { await self.advancePayments() }

  override var requiresSnapshotReferenceSimulator: Bool { false }
  private var vm = PaymentMethodSettingsViewModel(stripeIntentService: MockStripeIntentService())
  private let mockStripeIntentService = MockStripeIntentService()

  private let userTemplate = GraphUser.template |> \.storedCards .~ UserCreditCards.template
  private let cancelLoadingState = PaymentRecorder<Void>()
  private let editButtonIsEnabled = PaymentRecorder<Bool>()
  private let editButtonTitle = PaymentRecorder<String>()
  private let errorLoadingPaymentMethodsOrSetupIntent = PaymentRecorder<String>()
  private let goToPaymentSheet = PaymentRecorder<PaymentSheetSetupData>()
  private let paymentMethods = PaymentRecorder<[UserCreditCards.CreditCard]>()
  private let presentBanner = PaymentRecorder<String>()
  private let reloadData = PaymentRecorder<Void>()
  private let setStripePublishableKey = PaymentRecorder<String>()
  private let showAlert = PaymentRecorder<String>()
  private let tableViewIsEditing = PaymentRecorder<Bool>()

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm = PaymentMethodSettingsViewModel(stripeIntentService: self.mockStripeIntentService, sleep: { _ in try Task.checkCancellation() })
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case .cancelAddNewCardLoadingState: self.cancelLoadingState.record(())
      case let .editButtonIsEnabled(value): self.editButtonIsEnabled.record(value)
      case let .editButtonTitle(value): self.editButtonTitle.record(value)
      case let .errorLoadingPaymentMethodsOrSetupIntent(value): self.errorLoadingPaymentMethodsOrSetupIntent.record(value)
      case let .goToPaymentSheet(value): self.goToPaymentSheet.record(value)
      case let .paymentMethods(value): self.paymentMethods.record(value)
      case let .presentBanner(value): self.presentBanner.record(value)
      case .reloadData: self.reloadData.record(())
      case let .setStripePublishableKey(value): self.setStripePublishableKey.record(value)
      case let .showAlert(value): self.showAlert.record(value)
      case let .tableViewIsEditing(value): self.tableViewIsEditing.record(value)
      }
    }
  }

  func testSessionChangeDuringPresentationDelaySuppressesOldCards() async {
    let gate = PaymentDelayGate()
    let vm = PaymentMethodSettingsViewModel(stripeIntentService: self.mockStripeIntentService, sleep: { _ in
      try await gate.wait()
    })
    var delivered = 0
    vm.onEvent = { event in if case .paymentMethods = event { delivered += 1 } }
    let response = UserEnvelope<GraphUser>(me: self.userTemplate)
    await withEnvironment(apiService: MockService(fetchGraphUserResult: .success(response))) {
      vm.viewDidLoad()
      await gate.waitUntilBlocked()
      self.mockStripeIntentService.paymentsFeature.sessionFeature.sessionChanged()
      gate.resume()
      await vm.waitForPending()
      XCTAssertEqual(delivered, 0)
    }
  }

  func testPaymentMethodsFetch_OnViewDidLoad() async {
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(fetchGraphUserResult: .success(response))

    await withEnvironment(apiService: apiService) {
      self.vm.viewDidLoad()

      self.reloadData.assertDidEmitValue()

      await self.advancePayments()

      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testSetStripePublishableKey_OnViewDidLoad_Success() async {
    await withEnvironment {
      self.setStripePublishableKey.assertDidNotEmitValue()

      self.vm.viewDidLoad()

      await self.advancePayments()

      self.setStripePublishableKey.assertDidEmitValue()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPaymentMethodsFetch_errorFetchingPaymentMethods() async {
    let apiService = MockService(fetchGraphUserResult: .failure(.couldNotParseJSON))

    await withEnvironment(apiService: apiService) {
      self.vm.viewDidLoad()

      self.reloadData.assertDidEmitValue()

      await self.advancePayments()

      self.errorLoadingPaymentMethodsOrSetupIntent
        .assertValue(ErrorEnvelope.couldNotParseJSON.localizedDescription)
      self.paymentMethods.assertDidNotEmitValue()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPaymentMethodsFetch_errorFetchingSetupIntent() async {
    let mockService = MockService(createStripeSetupIntentResult: .failure(.couldNotParseJSON))

    await withEnvironment(
      apiService: mockService
    ) {
      self.errorLoadingPaymentMethodsOrSetupIntent.assertDidNotEmitValue()

      self.vm.paymentMethodsFooterViewDidTapAddNewCardButton()

      await self.advancePayments()

      self.errorLoadingPaymentMethodsOrSetupIntent
        .assertValue(ErrorEnvelope.couldNotParseJSON.localizedDescription)

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPaymentSheetDidAdd_OnAddNewCardSucceeded() async {
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      addPaymentSheetPaymentSourceResult: .success(.paymentSourceSuccessTemplate),
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: apiService) {
      self.paymentMethods.assertValues([])

      guard let paymentMethod = STPPaymentMethod.visaStripePaymentMethod else {
        XCTFail("Should've created payment method.")

        return
      }

      let paymentOption = STPPaymentMethod.sampleStringPaymentOption(paymentMethod)
      let paymentOptionsDisplayData = STPPaymentMethod.samplePaymentOptionsDisplayData(paymentOption)

      self.vm
        .paymentSheetDidAdd(
          setupIntent: "seti_1LVlHO4VvJ2PtfhK43R6p7FI_secret_MEDiGbxfYVnHGsQy8v8TbZJTQhlNKLZ"
        )

      self.paymentMethods.assertValueCount(0)
      self.errorLoadingPaymentMethodsOrSetupIntent.assertDidNotEmitValue()

      await self.advancePayments()

      self.paymentMethods.assertValueCount(1)
      self.errorLoadingPaymentMethodsOrSetupIntent.assertDidNotEmitValue()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testCancelLoadingState_Success() async {
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      fetchGraphUserResult: .success(response)
    )

    await withEnvironment(apiService: apiService) {
      self.cancelLoadingState.assertDidNotEmitValue()

      self.vm
        .shouldCancelPaymentSheetAppearance(state: false)

      await self.advancePayments()

      self.cancelLoadingState.assertDidNotEmitValue()

      self.vm
        .shouldCancelPaymentSheetAppearance(state: true)

      await self.advancePayments()

      self.cancelLoadingState.assertDidEmitValue()
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testEditButtonIsNotEnabled_OnViewDidLoad() async {
    self.editButtonIsEnabled.assertDidNotEmitValue()
    self.vm.viewDidLoad()
    self.editButtonIsEnabled.assertValue(false)
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
  }

  func testEditButtonIsEnabledAndTitle_HasPaymentMethods() async {
    let response = UserEnvelope<GraphUser>(me: GraphUser.template)
    let apiService = MockService(fetchGraphUserResult: .success(response))
    await withEnvironment(apiService: apiService) {
      self.editButtonIsEnabled.assertDidNotEmitValue()
      self.editButtonTitle.assertDidNotEmitValue()

      self.vm.viewDidLoad()
      self.editButtonIsEnabled.assertValues([false])
      self.editButtonTitle.assertValues(["Edit"])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false, true])
      self.editButtonTitle.assertValues(["Edit"])

      self.vm.editButtonTapped()
      self.editButtonIsEnabled.assertValues([false, true])
      self.editButtonTitle.assertValues(["Edit", "Done"])

      self.vm.editButtonTapped()
      self.editButtonIsEnabled.assertValues([false, true])
      self.editButtonTitle.assertValues(["Edit", "Done", "Edit"])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testEditButtonIsNotEnabled_NoPaymentMethods() async {
    let emptyTemplate = GraphUser.template |> \.storedCards .~ .emptyTemplate
    let response = UserEnvelope<GraphUser>(me: emptyTemplate)
    let apiService = MockService(fetchGraphUserResult: .success(response))
    await withEnvironment(apiService: apiService) {
      self.editButtonIsEnabled.assertDidNotEmitValue()
      self.vm.viewDidLoad()

      self.editButtonIsEnabled.assertValues([false])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testEditButtonEnabled_AfterDeletePaymentMethod() async {
    guard let card = UserCreditCards.template.storedCards.first else {
      XCTFail("Card should exist")
      return
    }

    let result = DeletePaymentMethodEnvelope(storedCards: [card])
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      deletePaymentMethodResult: .success(result),
      fetchGraphUserResult: .success(response)
    )
    await withEnvironment(apiService: apiService) {
      self.editButtonIsEnabled.assertDidNotEmitValue()

      self.vm.viewDidLoad()

      self.editButtonIsEnabled.assertValues([false])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false, true])

      self.vm.didDelete(card, visibleCellCount: 1)

      self.editButtonIsEnabled.assertValues([false, true])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false, true])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testEditButtonNotEnabled_AfterDeleteLastPaymentMethod() async {
    guard let card = UserCreditCards.template.storedCards.first else {
      XCTFail("Card should exist")
      return
    }

    let result = DeletePaymentMethodEnvelope(storedCards: [])
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      deletePaymentMethodResult: .success(result),
      fetchGraphUserResult: .success(response)
    )
    await withEnvironment(apiService: apiService) {
      self.editButtonIsEnabled.assertDidNotEmitValue()

      self.vm.viewDidLoad()

      self.editButtonIsEnabled.assertValues([false])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false, true])

      self.vm.didDelete(card, visibleCellCount: 0)

      self.editButtonIsEnabled.assertValues([false, true, false])

      await self.advancePayments()

      self.editButtonIsEnabled.assertValues([false, true, false])
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testGoToPaymentSheet_WhenAddNewCardIsTapped_Success() async {
    let envelope = ClientSecretEnvelope(clientSecret: "UHJvamVjdC0yMzEyODc5ODc")
    let mockService = MockService(createStripeSetupIntentResult: .success(envelope))

    await withEnvironment(
      apiService: mockService
    ) {
      self.goToPaymentSheet.assertValueCount(0)

      self.vm.paymentMethodsFooterViewDidTapAddNewCardButton()

      await self.advancePayments(by: .seconds(1))

      self.goToPaymentSheet.assertValueCount(1)

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testTableViewIsEditing_isFalse_WhenAddNewCardIsPresented() async {
    let envelope = ClientSecretEnvelope(clientSecret: "UHJvamVjdC0yMzEyODc5ODc")
    let mockService = MockService(
      createStripeSetupIntentResult: .success(envelope),
      fetchGraphUserResult: .success(UserEnvelope(me: self.userTemplate))
    )

    await withEnvironment(
      apiService: mockService
    ) {
      self.tableViewIsEditing.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.editButtonTapped()

      self.tableViewIsEditing.assertValues([false, true])

      self.vm.paymentMethodsFooterViewDidTapAddNewCardButton()

      await self.advancePayments(by: .seconds(1))

      self.tableViewIsEditing.assertValues([false, true, false])

      XCTAssertEqual(self.mockStripeIntentService.setupIntentRequests, 1)
      XCTAssertEqual(self.mockStripeIntentService.paymentIntentRequests, 0)
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testPresentMessageBanner() async {
    self.presentBanner.assertValues([])

    self.vm.addNewCardSucceeded(with: Strings.Got_it_your_changes_have_been_saved())

    self.presentBanner.assertValues([Strings.Got_it_your_changes_have_been_saved()])
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
  }

  func testDeletePaymentMethod() async {
    guard let card = UserCreditCards.template.storedCards.first else {
      XCTFail("Card should exist")
      return
    }

    let result = DeletePaymentMethodEnvelope(storedCards: UserCreditCards.template.storedCards)
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      deletePaymentMethodResult: .success(result),
      fetchGraphUserResult: .success(response)
    )
    await withEnvironment(apiService: apiService) {
      self.vm.viewDidLoad()

      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false])
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])

      self.vm.editButtonTapped()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode enabled")
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])

      self.vm.didDelete(card, visibleCellCount: 1)
      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode remains enabled")
      self.showAlert.assertValues([], "No errors emitted")
      self.paymentMethods.assertValues(
        [UserCreditCards.template.storedCards],
        "Emits once"
      )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testDeletePaymentMethod_Error() async {
    guard let card = UserCreditCards.template.storedCards.first else {
      XCTFail("Card should exist")
      return
    }

    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService = MockService(
      deletePaymentMethodResult: .failure(.couldNotParseJSON),
      fetchGraphUserResult: .success(response)
    )
    await withEnvironment(apiService: apiService) {
      self.vm.viewDidLoad()

      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false])
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])

      self.vm.editButtonTapped()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode enabled")
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])

      self.vm.didDelete(card, visibleCellCount: 1)
      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode remains enabled")
      self.showAlert.assertValues([
        "Something went wrong and we were unable to remove your payment method, please try again."
      ])
      self.paymentMethods.assertValues(
        [UserCreditCards.template.storedCards, UserCreditCards.template.storedCards],
        "Emits again to reload the tableview after an error occurred"
      )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }

  func testDeletePaymentMethod_SuccessThenError() async {
    guard let card = UserCreditCards.template.storedCards.first else {
      XCTFail("Card should exist")
      return
    }

    let result1 = DeletePaymentMethodEnvelope(storedCards: [card, card])
    let response = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService1 = MockService(
      deletePaymentMethodResult: .success(result1),
      fetchGraphUserResult: .success(response)
    )
    await withEnvironment(apiService: apiService1) {
      self.vm.viewDidLoad()

      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false])
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])
      self.editButtonIsEnabled.assertValues([false, true], "Edit button enabled, we have cards")

      self.vm.editButtonTapped()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode enabled")
      self.showAlert.assertValues([])
      self.paymentMethods.assertValues([UserCreditCards.template.storedCards])

      self.vm.didDelete(card, visibleCellCount: 1)
      self.editButtonIsEnabled.assertValues([false, true], "Editing button remains enabled")

      await self.advancePayments()

      self.tableViewIsEditing.assertValues([false, true], "Editing mode remains enabled")
      self.showAlert.assertValues([])
    await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }

    let response2 = UserEnvelope<GraphUser>(me: userTemplate)
    let apiService2 = MockService(
      deletePaymentMethodResult: .failure(.couldNotParseJSON),
      fetchGraphUserResult: .success(response2)
    )

    await withEnvironment(apiService: apiService2) {
      self.vm.didDelete(card, visibleCellCount: 0)

      self.editButtonIsEnabled.assertValues(
        [false, true, false], "Editing button disabled as last card removed"
      )
      self.tableViewIsEditing.assertValues([false, true, false], "Editing mode disabled as last card removed")

      await self.advancePayments()
      self.showAlert.assertValues([
        "Something went wrong and we were unable to remove your payment method, please try again."
      ])
      self.paymentMethods.assertValues(
        [UserCreditCards.template.storedCards, result1.storedCards],
        "Emits again with the results from the last successful deletion to reload the tableview after an error occurred"
      )

      self.vm.failedToAddNewCard()
      await self.advancePayments()

      self.editButtonIsEnabled.assertValues(
        [false, true, false, true], "Editing mode disabled as last card removal failed"
      )
      self.tableViewIsEditing.assertValues(
        [false, true, false], "Editing mode reenabled as last card removal failed"
      )
      self.paymentMethods.assertValues(
        [
          UserCreditCards.template.storedCards,
          result1.storedCards,
          UserCreditCards.template.storedCards
        ],
        "Cards are refreshed normally"
      )
      await self.mockStripeIntentService.paymentsFeature.waitForOperations()
    }
  }
}

private final class PaymentRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) { self.assertValueCount(0, message, file: file, line: line) }
  func assertDidEmitValue(file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(self.values.isEmpty, file: file, line: line) }
}
private extension PaymentRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values, expected, message, file: file, line: line) }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { self.assertValues([expected], message, file: file, line: line) }
}

@MainActor
private final class PaymentDelayGate {
  private var continuation: CheckedContinuation<Void, Error>?
  func wait() async throws {
    try await withCheckedThrowingContinuation { self.continuation = $0 }
  }
  func waitUntilBlocked() async {
    while self.continuation == nil { await Task.yield() }
  }
  func resume() {
    self.continuation?.resume()
    self.continuation = nil
  }
}
