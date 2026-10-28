import Foundation
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class PaymentsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledPaymentsProvider()
  private let session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) },
                                       currentUser: { .template }, updateUser: { _ in })
  private lazy var feature = PaymentsFeature(sessionFeature: self.session, makeProvider: { self.provider })
  override func tearDown() async throws {
    self.session.sessionChanged()
    self.feature.reset()
    self.provider.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testDuplicateSetupSharesRequestAndDisposedObserverDoesNotCancelWrite() async throws {
    var first: [String] = [], second: [String] = []
    let subscription = self.feature.setupResult(projectID: nil, context: .profileSettings)
      .startWithResult { result in
        switch result { case let .success(value): first.append(value.clientSecret); case .failure: XCTFail("Unexpected payment error") }
      }
    let duplicate = self.feature.setupResult(projectID: nil, context: .profileSettings)
      .startWithResult { result in
        switch result { case let .success(value): second.append(value.clientSecret); case .failure: XCTFail("Unexpected payment error") }
      }
    defer { duplicate.dispose() }
    await self.provider.setups.waitFor(1)
    subscription.dispose()
    try self.provider.setups.finish(0, .success(ClientSecretEnvelope(clientSecret: "fixture")))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.setups.count, 1)
    XCTAssertEqual(first, [])
    XCTAssertEqual(second, ["fixture"])
  }

  func testDistinctSetupContextsRemainIndependent() async throws {
    let first = self.feature.setupResult(projectID: "project", context: .crowdfundingCheckout).start()
    let second = self.feature.setupResult(projectID: "project", context: .postCampaignCheckout).start()
    defer { first.dispose(); second.dispose() }
    await self.provider.setups.waitFor(2)
    XCTAssertEqual(self.provider.setupInputs.map { $0.setupIntentContext }, [.crowdfundingCheckout, .postCampaignCheckout])
    XCTAssertEqual(self.provider.setupInputs.map { $0.projectId }, ["project", "project"])
    try self.provider.setups.finish(1, .success(ClientSecretEnvelope(clientSecret: "second")))
    try self.provider.setups.finish(0, .success(ClientSecretEnvelope(clientSecret: "first")))
    await self.feature.waitForOperations()
  }

  func testIntentPreservesAmountCheckoutEncodingAndSharesPendingRequest() async throws {
    var secrets: [String] = []
    let a = self.feature.intentResult(projectID: "project", backingID: "backing", checkoutID: "19", total: 12.5)
      .startWithResult { result in
        switch result { case let .success(value): secrets.append(value.clientSecret); case .failure: XCTFail("Unexpected payment error") }
      }
    let b = self.feature.intentResult(projectID: "project", backingID: "backing", checkoutID: "19", total: 12.5)
      .startWithResult { result in
        switch result { case let .success(value): secrets.append(value.clientSecret); case .failure: XCTFail("Unexpected payment error") }
      }
    defer { a.dispose(); b.dispose() }
    await self.provider.intents.waitFor(1)
    let input = try XCTUnwrap(self.provider.intentInputs.first)
    XCTAssertEqual(input.projectId, "project")
    XCTAssertEqual(input.backingId, "backing")
    XCTAssertEqual(input.amountDollars, "12.50")
    XCTAssertEqual(input.checkoutId, Data("Checkout-19".utf8).base64EncodedString())
    XCTAssertEqual(input.paymentIntentContext, .postCampaignCheckout)
    XCTAssertNil(input.digitalMarketingAttributed)
    try self.provider.intents.finish(0, .success(PaymentIntentEnvelope(clientSecret: "fixture")))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.intents.count, 1)
    XCTAssertEqual(secrets, ["fixture", "fixture"])
  }

  func testCardWritesStayOrderedAndFailureDoesNotBlockNextCommand() async throws {
    var errors = 0, cards = 0
    let a = self.feature.removeResult(id: "old").startWithFailed { _ in errors += 1 }
    let b = self.feature.storeResult(secret: "fixture").startWithResult { result in
      if case .success = result { cards += 1 } else { XCTFail("Unexpected storage failure") }
    }
    defer { a.dispose(); b.dispose() }
    await self.provider.removals.waitFor(1)
    XCTAssertEqual(self.provider.stores.count, 0)
    try self.provider.removals.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.stores.waitFor(1)
    XCTAssertEqual(self.provider.removedIDs, ["old"])
    XCTAssertEqual(self.provider.storedSecrets, ["fixture"])
    try self.provider.stores.finish(0, .success(self.storedCard()))
    await self.feature.waitForOperations()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(cards, 1)
    XCTAssertEqual(self.provider.removals.count, 1)
  }

  func testDuplicatePendingCardTailSharesButInterveningWriteDoesNot() async throws {
    let a = self.feature.removeResult(id: "card").start()
    let duplicate = self.feature.removeResult(id: "card").start()
    let store = self.feature.storeResult(secret: "fixture").start()
    let again = self.feature.removeResult(id: "card").start()
    defer { a.dispose(); duplicate.dispose(); store.dispose(); again.dispose() }
    await self.provider.removals.waitFor(1)
    try self.provider.removals.finish(0, .success(DeletePaymentMethodEnvelope(storedCards: [])))
    await self.provider.stores.waitFor(1)
    try self.provider.stores.finish(0, .success(self.storedCard()))
    await self.provider.removals.waitFor(2)
    try self.provider.removals.finish(1, .success(DeletePaymentMethodEnvelope(storedCards: [])))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.removals.count, 2)
  }

  func testReadOvertakenByWriteReloadsBeforePublishing() async throws {
    let read = Task { try await self.feature.cards() }
    await self.provider.cardReads.waitFor(1)
    let write = self.feature.removeResult(id: "card").start()
    defer { write.dispose() }
    await self.provider.removals.waitFor(1)
    try self.provider.cardReads.finish(0, .success(UserEnvelope(me: .template)))
    try self.provider.removals.finish(0, .success(DeletePaymentMethodEnvelope(storedCards: [])))
    await self.provider.cardReads.waitFor(2)
    try self.provider.cardReads.finish(1, .success(UserEnvelope(me: .template)))
    _ = try await read.value
    XCTAssertEqual(self.provider.cardReads.count, 2)
  }

  func testSessionChangeSuppressesOldIntentValueAndQueuedCardWrite() async throws {
    var values = 0, errors = 0
    let intent = self.feature.intentResult(projectID: "p", backingID: "b", checkoutID: "c", total: 1)
      .startWithResult { _ in values += 1 }
    let removal = self.feature.removeResult(id: "old").startWithFailed { _ in errors += 1 }
    let queued = self.feature.storeResult(secret: "fixture").startWithResult { _ in values += 1 }
    defer { intent.dispose(); removal.dispose(); queued.dispose() }
    await self.provider.intents.waitFor(1)
    await self.provider.removals.waitFor(1)
    self.session.sessionChanged()
    try self.provider.intents.finish(0, .success(PaymentIntentEnvelope(clientSecret: "old")))
    try self.provider.removals.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertEqual(values, 0)
    XCTAssertEqual(errors, 0)
    XCTAssertEqual(self.provider.stores.count, 0)
  }

  func testSessionChangeDuringPresentationDelaySuppressesClientSecret() async throws {
    var delivered = false
    let subscription = self.feature.currentResult {
      self.feature.setupResult(projectID: nil, context: .profileSettings)
        .delay(1, on: self.scheduler)
    }.startWithResult { _ in delivered = true }
    defer { subscription.dispose() }
    await self.provider.setups.waitFor(1)
    try self.provider.setups.finish(0, .success(ClientSecretEnvelope(clientSecret: "fixture")))
    await self.feature.waitForOperations()
    self.session.sessionChanged()
    await self.scheduler.advance(by: 1)
    XCTAssertFalse(delivered)
  }

  func testAwaitableCommandRejectsCanceledCallerWithoutRetryingWrite() async throws {
    let caller = Task { try await self.feature.setup(projectID: nil, context: .profileSettings) }
    await self.provider.setups.waitFor(1)
    caller.cancel()
    try self.provider.setups.finish(0, .success(ClientSecretEnvelope(clientSecret: "fixture")))
    do { _ = try await caller.value; XCTFail("Canceled caller must not receive a secret") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.setups.count, 1)
  }

  func testPublicDemoRejectsEveryPaymentEntryPoint() async {
    let provider = AsyncPaymentsProvider(service: MockService.publicDemo())
    do { _ = try await provider.cards(); XCTFail("Demo must reject payment reads") } catch {}
    do { _ = try await provider.remove(id: "card"); XCTFail("Demo must reject deletion") } catch {}
    do { _ = try await provider.store(secret: "fixture"); XCTFail("Demo must reject card storage") } catch {}
    do { _ = try await provider.setup(input: .init(projectId: nil, context: .profileSettings)); XCTFail("Demo must reject setup") } catch {}
    do { _ = try await provider.intent(input: .init(projectId: "p", backingId: "b", amountDollars: "1.00", checkoutId: "c", digitalMarketingAttributed: nil)); XCTFail("Demo must reject intent") } catch {}
  }

  private func storedCard() -> CreatePaymentSourceEnvelope {
    CreatePaymentSourceEnvelope(createPaymentSource: .init(isSuccessful: true, paymentSource: UserCreditCards.template.storedCards[0]))
  }
}

@MainActor
private final class ControlledPaymentsProvider: PaymentsProvider {
  let cardReads = AccountRequestGate<UserEnvelope<GraphUser>>()
  let removals = AccountRequestGate<DeletePaymentMethodEnvelope>()
  let stores = AccountRequestGate<CreatePaymentSourceEnvelope>()
  let setups = AccountRequestGate<ClientSecretEnvelope>()
  let intents = AccountRequestGate<PaymentIntentEnvelope>()
  var removedIDs: [String] = []
  var storedSecrets: [String] = []
  var setupInputs: [KsApi.CreateSetupIntentInput] = []
  var intentInputs: [KsApi.CreatePaymentIntentInput] = []
  func cards() async throws -> UserEnvelope<GraphUser> { try await self.cardReads.request() }
  func remove(id: String) async throws -> DeletePaymentMethodEnvelope {
    self.removedIDs.append(id)
    return try await self.removals.request()
  }
  func store(secret: String) async throws -> CreatePaymentSourceEnvelope {
    self.storedSecrets.append(secret)
    return try await self.stores.request()
  }
  func setup(input: KsApi.CreateSetupIntentInput) async throws -> ClientSecretEnvelope {
    self.setupInputs.append(input)
    return try await self.setups.request()
  }
  func intent(input: KsApi.CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope {
    self.intentInputs.append(input)
    return try await self.intents.request()
  }
  func releaseAll() {
    self.cardReads.releaseAll(); self.removals.releaseAll(); self.stores.releaseAll()
    self.setups.releaseAll(); self.intents.releaseAll()
  }
}
