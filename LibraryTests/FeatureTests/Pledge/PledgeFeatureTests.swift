import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class PledgeFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledPledgeProvider()
  private let session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) },
                                       currentUser: { .template }, updateUser: { _ in })
  private lazy var feature = PledgeFeature(sessionFeature: self.session, makeProvider: { self.provider })
  override func tearDown() async throws {
    self.session.sessionChanged()
    self.feature.reset()
    self.provider.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testEquivalentCreateSharesPendingWriteAndPreservesSCACheckout() async throws {
    var values: [String?] = []
    let input = self.createInput()
    let first = self.feature.createResult(input).startWithResult {
      if case let .success(value) = $0 { values.append(value.createBacking.checkout.backing.clientSecret) }
      else { XCTFail("Unexpected create error") }
    }
    let duplicate = self.feature.createResult(input).startWithResult {
      if case let .success(value) = $0 { values.append(value.createBacking.checkout.backing.clientSecret) }
      else { XCTFail("Unexpected create error") }
    }
    defer { first.dispose(); duplicate.dispose() }
    await self.provider.creates.waitFor(1)
    XCTAssertEqual(self.provider.createInputs, [input])
    try self.provider.creates.finish(0, .success(self.created()))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.creates.count, 1)
    XCTAssertEqual(values, ["fixture-secret", "fixture-secret"])
  }

  func testDistinctCreateInputsQueueRatherThanShare() async throws {
    let firstInput = self.createInput(amount: "10.00")
    let secondInput = self.createInput(amount: "20.00")
    let first = self.feature.createResult(firstInput).start()
    let second = self.feature.createResult(secondInput).start()
    defer { first.dispose(); second.dispose() }
    await self.provider.creates.waitFor(1)
    try self.provider.creates.finish(0, .success(self.created()))
    await self.provider.creates.waitFor(2)
    XCTAssertEqual(self.provider.createInputs, [firstInput, secondInput])
    try self.provider.creates.finish(1, .success(self.created()))
    await self.feature.waitForOperations()
  }

  func testUpdateThenCancelKeepsOrderEvenWhenUpdateFails() async throws {
    var errors = 0, canceled = 0
    let updateInput = self.updateInput()
    let cancelInput = CancelBackingInput(backingId: "backing", cancellationReason: "fixture note")
    let update = self.feature.updateResult(updateInput).startWithFailed { _ in errors += 1 }
    let cancel = self.feature.cancelResult(cancelInput).startWithResult {
      if case .success = $0 { canceled += 1 } else { XCTFail("Unexpected cancellation failure") }
    }
    defer { update.dispose(); cancel.dispose() }
    await self.provider.updates.waitFor(1)
    XCTAssertEqual(self.provider.cancellations.count, 0)
    try self.provider.updates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.cancellations.waitFor(1)
    XCTAssertEqual(self.provider.updateInputs, [updateInput])
    XCTAssertEqual(self.provider.cancelInputs, [cancelInput])
    try self.provider.cancellations.finish(0, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(canceled, 1)
    XCTAssertEqual(self.provider.updates.count, 1)
  }

  func testDisposedObserverDoesNotAbandonAdmittedCreate() async throws {
    var delivered = false
    let subscription = self.feature.createResult(self.createInput()).startWithResult { _ in delivered = true }
    await self.provider.creates.waitFor(1)
    subscription.dispose()
    try self.provider.creates.finish(0, .success(self.created()))
    await self.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(self.provider.creates.count, 1)
  }

  func testDuplicateCancellationSharesAndLaterExplicitRetryStartsNewRequest() async throws {
    var failures = 0
    let input = CancelBackingInput(backingId: "backing", cancellationReason: nil)
    let first = self.feature.cancelResult(input).startWithFailed { _ in failures += 1 }
    let duplicate = self.feature.cancelResult(input).startWithFailed { _ in failures += 1 }
    defer { first.dispose(); duplicate.dispose() }
    await self.provider.cancellations.waitFor(1)
    try self.provider.cancellations.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertEqual(failures, 2)
    XCTAssertEqual(self.provider.cancellations.count, 1)
    let retry = Task { try await self.feature.cancel(input) }
    await self.provider.cancellations.waitFor(2)
    try self.provider.cancellations.finish(1, .success(()))
    try await retry.value
  }

  func testRewardToggleTrueFalseTrueRetainsEveryDistinctCommand() async throws {
    let first = self.feature.receivedResult(projectID: 1, userID: 2, received: true).start()
    let duplicate = self.feature.receivedResult(projectID: 1, userID: 2, received: true).start()
    let second = self.feature.receivedResult(projectID: 1, userID: 2, received: false).start()
    let third = self.feature.receivedResult(projectID: 1, userID: 2, received: true).start()
    defer { first.dispose(); duplicate.dispose(); second.dispose(); third.dispose() }
    for i in 0..<3 {
      await self.provider.receipts.waitFor(i + 1)
      try self.provider.receipts.finish(i, .success(.template))
    }
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.receivedValues, [true, false, true])
    XCTAssertEqual(self.provider.receivedProjects, [1, 1, 1])
    XCTAssertEqual(self.provider.receivedUsers, [2, 2, 2])
  }

  func testSessionChangeRejectsOldSuccessErrorAndQueuedWrite() async throws {
    var delivered = false
    let old = self.feature.createResult(self.createInput()).startWithResult { _ in delivered = true }
    let queued = self.feature.updateResult(self.updateInput()).startWithResult { _ in delivered = true }
    defer { old.dispose(); queued.dispose() }
    await self.provider.creates.waitFor(1)
    self.session.sessionChanged()
    try self.provider.creates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(self.provider.updates.count, 0)
  }

  func testNewSessionCanProceedBeforeOldRequestSettles() async throws {
    var oldDelivered = false, newDelivered = false
    let old = self.feature.createResult(self.createInput()).startWithResult { _ in oldDelivered = true }
    await self.provider.creates.waitFor(1)
    self.session.sessionChanged()
    let current = self.feature.createResult(self.createInput()).startWithResult {
      if case .success = $0 { newDelivered = true } else { XCTFail("Unexpected new-session error") }
    }
    defer { old.dispose(); current.dispose() }
    await self.provider.creates.waitFor(2)
    try self.provider.creates.finish(1, .success(self.created()))
    try self.provider.creates.finish(0, .success(self.created()))
    await self.feature.waitForOperations()
    XCTAssertFalse(oldDelivered)
    XCTAssertTrue(newDelivered)
  }

  func testCanceledAsyncCallerCannotReceiveSuccessfulUpdate() async throws {
    let caller = Task { try await self.feature.update(self.updateInput()) }
    await self.provider.updates.waitFor(1)
    caller.cancel()
    try self.provider.updates.finish(0, .success(UpdateBackingEnvelope(updateBacking: .init(checkout: self.checkout()))))
    do { _ = try await caller.value; XCTFail("Canceled caller must not receive completion") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.updates.count, 1)
  }

  func testCanceledAsyncCallerDoesNotReceiveLateFailure() async throws {
    let caller = Task { try await self.feature.update(self.updateInput()) }
    await self.provider.updates.waitFor(1)
    caller.cancel()
    try self.provider.updates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await caller.value; XCTFail("Canceled caller must not receive an obsolete failure") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.updates.count, 1)
  }

  func testSessionChangeSuppressesDelayedSuccessAndFailure() async throws {
    await withEnvironment(apiDelayInterval: .seconds(1)) {
      var delivered = false
      let first = self.feature.delayedResult(self.feature.createResult(self.createInput()))
        .startWithResult { _ in delivered = true }
      let second = self.feature.delayedResult(self.feature.cancelResult(.init(backingId: "backing", cancellationReason: nil)))
        .startWithResult { _ in delivered = true }
      defer { first.dispose(); second.dispose() }
      await self.provider.creates.waitFor(1)
      do { try self.provider.creates.finish(0, .success(self.created())) } catch { XCTFail("Missing fixture") }
      await self.provider.cancellations.waitFor(1)
      do { try self.provider.cancellations.finish(0, .failure(ErrorEnvelope.couldNotParseJSON)) } catch { XCTFail("Missing fixture") }
      await self.feature.waitForOperations()
      self.session.sessionChanged()
      await self.scheduler.advance(by: 1)
      XCTAssertFalse(delivered)
    }
  }

  func testPublicDemoRejectsAllPledgeMutations() async {
    let provider = AsyncPledgeProvider(service: MockService.publicDemo())
    do { _ = try await provider.create(self.createInput()); XCTFail("Demo create") } catch {}
    do { _ = try await provider.update(self.updateInput()); XCTFail("Demo update") } catch {}
    do { try await provider.cancel(.init(backingId: "b", cancellationReason: nil)); XCTFail("Demo cancel") } catch {}
    do { _ = try await provider.received(projectID: 1, userID: 2, received: true); XCTFail("Demo received") } catch {}
  }

  private func createInput(amount: String = "10.00") -> CreateBackingInput {
    CreateBackingInput(amount: amount, applePay: nil, incremental: true, locationId: "location",
                       paymentSourceId: "card", projectId: "project", refParam: "ref",
                       rewardIds: ["reward", "addon"], setupIntentClientSecret: nil)
  }
  private func updateInput() -> UpdateBackingInput {
    UpdateBackingInput(amount: "20.00", applePay: nil, id: "backing", incremental: false,
                       locationId: "location", paymentSourceId: "card", rewardIds: ["reward"],
                       setupIntentClientSecret: nil)
  }
  private func checkout() -> Checkout {
    Checkout(id: "checkout", state: .successful, backing: .init(clientSecret: "fixture-secret", requiresAction: true))
  }
  private func created() -> CreateBackingEnvelope {
    CreateBackingEnvelope(createBacking: .init(checkout: self.checkout()))
  }
}

@MainActor
private final class ControlledPledgeProvider: PledgeProvider {
  let creates = AccountRequestGate<CreateBackingEnvelope>()
  let updates = AccountRequestGate<UpdateBackingEnvelope>()
  let cancellations = AccountRequestGate<Void>()
  let receipts = AccountRequestGate<Backing>()
  var createInputs: [CreateBackingInput] = []
  var updateInputs: [UpdateBackingInput] = []
  var cancelInputs: [CancelBackingInput] = []
  var receivedValues: [Bool] = []
  var receivedProjects: [Int] = []
  var receivedUsers: [Int] = []
  func create(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope {
    self.createInputs.append(input)
    return try await self.creates.request()
  }
  func update(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    self.updateInputs.append(input)
    return try await self.updates.request()
  }
  func cancel(_ input: CancelBackingInput) async throws {
    self.cancelInputs.append(input)
    try await self.cancellations.request()
  }
  func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    self.receivedProjects.append(projectID); self.receivedUsers.append(userID)
    self.receivedValues.append(received)
    return try await self.receipts.request()
  }
  func releaseAll() {
    self.creates.releaseAll(); self.updates.releaseAll()
    self.cancellations.releaseAll(); self.receipts.releaseAll()
  }
}
