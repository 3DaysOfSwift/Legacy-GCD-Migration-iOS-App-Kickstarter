import Foundation
import GraphAPI
import ReactiveSwift
import XCTest

@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

@MainActor
final class PledgeFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledPledgeProvider()
  private let session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) },
    currentUser: { .template }, updateUser: { _ in })
  private lazy var feature = PledgeFeature(
    sessionFeature: self.session, makeProvider: { self.provider })
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
      if case .success(let value) = $0 {
        values.append(value.createBacking.checkout.backing.clientSecret)
      } else {
        XCTFail("Unexpected create error")
      }
    }
    let duplicate = self.feature.createResult(input).startWithResult {
      if case .success(let value) = $0 {
        values.append(value.createBacking.checkout.backing.clientSecret)
      } else {
        XCTFail("Unexpected create error")
      }
    }
    defer {
      first.dispose()
      duplicate.dispose()
    }
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
    defer {
      first.dispose()
      second.dispose()
    }
    await self.provider.creates.waitFor(1)
    try self.provider.creates.finish(0, .success(self.created()))
    await self.provider.creates.waitFor(2)
    XCTAssertEqual(self.provider.createInputs, [firstInput, secondInput])
    try self.provider.creates.finish(1, .success(self.created()))
    await self.feature.waitForOperations()
  }

  func testUpdateThenCancelKeepsOrderEvenWhenUpdateFails() async throws {
    var errors = 0
    var canceled = 0
    let updateInput = self.updateInput()
    let cancelInput = KsApi.CancelBackingInput(
      backingId: "backing", cancellationReason: "fixture note")
    let update = self.feature.updateResult(updateInput).startWithFailed { _ in errors += 1 }
    let cancel = self.feature.cancelResult(cancelInput).startWithResult {
      if case .success = $0 { canceled += 1 } else { XCTFail("Unexpected cancellation failure") }
    }
    defer {
      update.dispose()
      cancel.dispose()
    }
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
    let subscription = self.feature.createResult(self.createInput()).startWithResult { _ in
      delivered = true
    }
    await self.provider.creates.waitFor(1)
    subscription.dispose()
    try self.provider.creates.finish(0, .success(self.created()))
    await self.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(self.provider.creates.count, 1)
  }

  func testDuplicateCancellationSharesAndLaterExplicitRetryStartsNewRequest() async throws {
    var failures = 0
    let input = KsApi.CancelBackingInput(backingId: "backing", cancellationReason: nil)
    let first = self.feature.cancelResult(input).startWithFailed { _ in failures += 1 }
    let duplicate = self.feature.cancelResult(input).startWithFailed { _ in failures += 1 }
    defer {
      first.dispose()
      duplicate.dispose()
    }
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
    defer {
      first.dispose()
      duplicate.dispose()
      second.dispose()
      third.dispose()
    }
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
    let old = self.feature.createResult(self.createInput()).startWithResult { _ in delivered = true
    }
    let queued = self.feature.updateResult(self.updateInput()).startWithResult { _ in
      delivered = true
    }
    defer {
      old.dispose()
      queued.dispose()
    }
    await self.provider.creates.waitFor(1)
    self.session.sessionChanged()
    try self.provider.creates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(self.provider.updates.count, 0)
  }

  func testNewSessionCanProceedBeforeOldRequestSettles() async throws {
    var oldDelivered = false
    var newDelivered = false
    let old = self.feature.createResult(self.createInput()).startWithResult { _ in
      oldDelivered = true
    }
    await self.provider.creates.waitFor(1)
    self.session.sessionChanged()
    let current = self.feature.createResult(self.createInput()).startWithResult {
      if case .success = $0 { newDelivered = true } else { XCTFail("Unexpected new-session error") }
    }
    defer {
      old.dispose()
      current.dispose()
    }
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
    try self.provider.updates.finish(
      0, .success(UpdateBackingEnvelope(updateBacking: .init(checkout: self.checkout()))))
    do {
      _ = try await caller.value
      XCTFail("Canceled caller must not receive completion")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.updates.count, 1)
  }

  func testCanceledAsyncCallerDoesNotReceiveLateFailure() async throws {
    let caller = Task { try await self.feature.update(self.updateInput()) }
    await self.provider.updates.waitFor(1)
    caller.cancel()
    try self.provider.updates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do {
      _ = try await caller.value
      XCTFail("Canceled caller must not receive an obsolete failure")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.updates.count, 1)
  }

  func testSessionChangeSuppressesDelayedSuccessAndFailure() async throws {
    await withEnvironment(apiDelayInterval: .seconds(1)) {
      var delivered = false
      let first = self.feature.delayedResult(self.feature.createResult(self.createInput()))
        .startWithResult { _ in delivered = true }
      let second = self.feature.delayedResult(
        self.feature.cancelResult(.init(backingId: "backing", cancellationReason: nil))
      )
      .startWithResult { _ in delivered = true }
      defer {
        first.dispose()
        second.dispose()
      }
      await self.provider.creates.waitFor(1)
      do { try self.provider.creates.finish(0, .success(self.created())) } catch {
        XCTFail("Missing fixture")
      }
      await self.provider.cancellations.waitFor(1)
      do {
        try self.provider.cancellations.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
      } catch { XCTFail("Missing fixture") }
      await self.feature.waitForOperations()
      self.session.sessionChanged()
      await self.scheduler.advance(by: 1)
      XCTAssertFalse(delivered)
    }
  }

  func testPublicDemoRejectsAllPledgeMutations() async {
    let provider = AsyncPledgeProvider(service: MockService.publicDemo())
    do {
      _ = try await provider.create(self.createInput())
      XCTFail("Demo create")
    } catch {}
    do {
      _ = try await provider.update(self.updateInput())
      XCTFail("Demo update")
    } catch {}
    do {
      try await provider.cancel(.init(backingId: "b", cancellationReason: nil))
      XCTFail("Demo cancel")
    } catch {}
    do {
      _ = try await provider.received(projectID: 1, userID: 2, received: true)
      XCTFail("Demo received")
    } catch {}
  }

  func testCheckoutSharesEquivalentPendingInputsAndQueuesChangedAmount() async throws {
    let input = KsApi.CreateCheckoutInput(
      projectId: "p", amount: "10.00", locationId: "l", rewardIds: ["r", "r"], refParam: "ref")
    let changed = KsApi.CreateCheckoutInput(
      projectId: "p", amount: "20.00", locationId: "l", rewardIds: ["r", "r"], refParam: "ref")
    var ids: [String] = []
    let a = self.feature.openCheckoutResult(input).startWithResult {
      if case .success(let value) = $0 {
        ids.append(value.checkout.id)
      } else {
        XCTFail("Expected checkout")
      }
    }
    let b = self.feature.openCheckoutResult(input).startWithResult {
      if case .success(let value) = $0 {
        ids.append(value.checkout.id)
      } else {
        XCTFail("Expected checkout")
      }
    }
    let c = self.feature.openCheckoutResult(changed).start()
    defer {
      a.dispose()
      b.dispose()
      c.dispose()
    }
    await self.provider.checkouts.waitFor(1)
    XCTAssertEqual(self.provider.checkoutInputs, [input])
    try self.provider.checkouts.finish(
      0, .success(.init(checkout: .init(id: "checkout", paymentUrl: "fixture", backingId: "b"))))
    await self.provider.checkouts.waitFor(2)
    XCTAssertEqual(self.provider.checkoutInputs, [input, changed])
    try self.provider.checkouts.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertEqual(ids, ["checkout", "checkout"])
  }

  func testValidationIdentityIncludesCardAndIntentAndPreservesFailure() async throws {
    var errors = 0
    let a = self.feature.validateCheckoutResult(
      checkoutID: "c", sourceID: "card-a", secret: "intent-a"
    ).startWithFailed { _ in errors += 1 }
    let duplicate = self.feature.validateCheckoutResult(
      checkoutID: "c", sourceID: "card-a", secret: "intent-a"
    ).start()
    let b = self.feature.validateCheckoutResult(
      checkoutID: "c", sourceID: "card-b", secret: "intent-b"
    ).start()
    defer {
      a.dispose()
      duplicate.dispose()
      b.dispose()
    }
    await self.provider.validations.waitFor(1)
    try self.provider.validations.finish(
      0, .failure(ErrorEnvelope.validateCheckoutError(["declined"])))
    await self.provider.validations.waitFor(2)
    XCTAssertEqual(self.provider.validationInputs.map { $0.1 }, ["card-a", "card-b"])
    XCTAssertEqual(self.provider.validationInputs.map { $0.2 }, ["intent-a", "intent-b"])
    try self.provider.validations.finish(1, .success(.init(messages: [])))
    await self.feature.waitForOperations()
    XCTAssertEqual(errors, 1)
  }

  func testCheckoutCompletionSurvivesDisposedObserverAndSharesPendingSubmission() async throws {
    let input = GraphAPI.CompleteOnSessionCheckoutInput(
      checkoutId: "c", paymentIntentClientSecret: "fixture",
      paymentSourceId: .some("card"), paymentSourceReusable: .some(true))
    var delivered = 0
    let first = self.feature.completeCheckoutResult(input).startWithResult { _ in
      XCTFail("Disposed observer")
    }
    let second = self.feature.completeCheckoutResult(input).startWithResult {
      if case .success = $0 { delivered += 1 } else { XCTFail("Expected completion") }
    }
    first.dispose()
    defer { second.dispose() }
    await self.provider.completions.waitFor(1)
    XCTAssertEqual(self.provider.completionInputs, [input])
    try self.provider.completions.finish(0, .success(.init()))
    await self.feature.waitForOperations()
    XCTAssertEqual(delivered, 1)
    XCTAssertEqual(self.provider.completions.count, 1)
  }

  func testSessionChangeSuppressesCheckoutAndRejectsQueuedCompletion() async throws {
    var delivered = false
    let a = self.feature.openCheckoutResult(
      .init(projectId: "p", amount: "10", locationId: nil, rewardIds: [], refParam: nil)
    )
    .startWithResult { _ in delivered = true }
    let b = self.feature.completeCheckoutResult(
      .init(checkoutId: "c", paymentIntentClientSecret: "fixture")
    )
    .startWithResult { _ in delivered = true }
    defer {
      a.dispose()
      b.dispose()
    }
    await self.provider.checkouts.waitFor(1)
    self.session.sessionChanged()
    self.feature.reset()
    try self.provider.checkouts.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(self.provider.completions.count, 0)
  }

  func testBackingReadSharesPendingRequestButRefreshesAfterCompletion() async throws {
    let route = UUID()
    var count = 0
    let a = self.feature.backingResult(route: route, id: 1).startWithResult {
      if case .success = $0 { count += 1 } else { XCTFail("Expected backing") }
    }
    let b = self.feature.backingResult(route: route, id: 1).startWithResult {
      if case .success = $0 { count += 1 } else { XCTFail("Expected backing") }
    }
    defer {
      a.dispose()
      b.dispose()
    }
    await self.provider.backings.waitFor(1)
    try self.provider.backings.finish(0, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertEqual(count, 2)
    let refresh = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(2)
    try self.provider.backings.finish(1, .success(.template))
    _ = try await refresh.value
    XCTAssertEqual(self.provider.backingInputs, [1, 1])
  }

  func testChangedBackingRejectsOldResponseAndRoutesStayIndependent() async throws {
    let route = UUID()
    let old = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let current = Task { try await self.feature.backing(route: route, id: 2) }
    await self.provider.backings.waitFor(2)
    let other = Task { try await self.feature.backing(route: UUID(), id: 3) }
    await self.provider.backings.waitFor(3)
    try self.provider.backings.finish(0, .success(.template))
    try self.provider.backings.finish(1, .success(.template))
    try self.provider.backings.finish(2, .success(.template))
    do {
      _ = try await old.value
      XCTFail("Obsolete backing")
    } catch { XCTAssertTrue(error is CancellationError) }
    _ = try await current.value
    _ = try await other.value
    XCTAssertEqual(self.provider.backingInputs, [1, 2, 3])
  }

  func testProjectReleaseAndAccountChangeSuppressLateReadErrors() async throws {
    let route = UUID()
    let old = Task { try await self.feature.project(route: route, param: .id(1)) }
    await self.provider.projects.waitFor(1)
    self.feature.releaseRead(route: route)
    try self.provider.projects.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do {
      _ = try await old.value
      XCTFail("Released route")
    } catch { XCTAssertTrue(error is CancellationError) }
    let next = Task { try await self.feature.project(route: route, param: .id(2)) }
    await self.provider.projects.waitFor(2)
    self.session.sessionChanged()
    self.feature.reset()
    try self.provider.projects.finish(1, .success(.template))
    do {
      _ = try await next.value
      XCTFail("Obsolete account")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testBackingRefreshWaitsForAdmittedMutation() async throws {
    let write = self.feature.cancelResult(.init(backingId: "b", cancellationReason: nil)).start()
    defer { write.dispose() }
    let read = self.feature.backingResult(route: UUID(), id: 1).start()
    defer { read.dispose() }
    await self.provider.cancellations.waitFor(1)
    XCTAssertEqual(self.provider.backings.count, 0)
    try self.provider.cancellations.finish(0, .success(()))
    await self.provider.backings.waitFor(1)
    try self.provider.backings.finish(0, .success(.template))
    await self.feature.waitForOperations()
  }

  func testRefreshAfterMutationDoesNotJoinAnOlderPendingBackingRead() async throws {
    let route = UUID()
    let old = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let write = self.feature.cancelResult(.init(backingId: "b", cancellationReason: nil)).start()
    defer { write.dispose() }
    let refresh = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.cancellations.waitFor(1)
    try self.provider.cancellations.finish(0, .success(()))
    await self.provider.backings.waitFor(2)
    try self.provider.backings.finish(1, .success(.template))
    try self.provider.backings.finish(0, .success(.template))
    _ = try await refresh.value
    do {
      _ = try await old.value
      XCTFail("Refresh must supersede pre-write backing data")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(self.provider.backingInputs, [1, 1])
  }

  func testPublicDemoRejectsCheckoutCommands() async {
    let provider = AsyncPledgeProvider(service: MockService.publicDemo())
    do {
      _ = try await provider.openCheckout(
        .init(projectId: "p", amount: "1", locationId: nil, rewardIds: [], refParam: nil))
      XCTFail("Demo checkout")
    } catch {}
    do {
      _ = try await provider.validateCheckout(checkoutID: "c", sourceID: "s", secret: "fixture")
      XCTFail("Demo validation")
    } catch {}
    do {
      _ = try await provider.completeCheckout(
        .init(checkoutId: "c", paymentIntentClientSecret: "fixture"))
      XCTFail("Demo completion")
    } catch {}
  }

  private func createInput(amount: String = "10.00") -> KsApi.CreateBackingInput {
    KsApi.CreateBackingInput(
      amount: amount, applePay: nil, incremental: true, locationId: "location",
      paymentSourceId: "card", projectId: "project", refParam: "ref",
      rewardIds: ["reward", "addon"], setupIntentClientSecret: nil)
  }
  private func updateInput() -> KsApi.UpdateBackingInput {
    KsApi.UpdateBackingInput(
      amount: "20.00", applePay: nil, id: "backing", incremental: false,
      locationId: "location", paymentSourceId: "card", rewardIds: ["reward"],
      setupIntentClientSecret: nil)
  }
  private func checkout() -> Checkout {
    Checkout(
      id: "checkout", state: .successful,
      backing: .init(clientSecret: "fixture-secret", requiresAction: true))
  }
  private func created() -> CreateBackingEnvelope {
    CreateBackingEnvelope(createBacking: .init(checkout: self.checkout()))
  }
}

@MainActor
private final class ControlledPledgeProvider: PledgeProvider {
  let checkouts = AccountRequestGate<CreateCheckoutEnvelope>()
  let validations = AccountRequestGate<ValidateCheckoutEnvelope>()
  let completions = AccountRequestGate<GraphAPI.CompleteOnSessionCheckoutMutation.Data>()
  let projects = AccountRequestGate<Project>()
  let backings = AccountRequestGate<Backing>()
  var checkoutInputs: [KsApi.CreateCheckoutInput] = []
  var validationInputs: [(String, String, String)] = []
  var completionInputs: [GraphAPI.CompleteOnSessionCheckoutInput] = []
  var projectInputs: [Param] = []
  var backingInputs: [Int] = []
  func openCheckout(_ input: KsApi.CreateCheckoutInput) async throws -> CreateCheckoutEnvelope {
    self.checkoutInputs.append(input)
    return try await self.checkouts.request()
  }
  func validateCheckout(checkoutID: String, sourceID: String, secret: String) async throws
    -> ValidateCheckoutEnvelope
  {
    self.validationInputs.append((checkoutID, sourceID, secret))
    return try await self.validations.request()
  }
  func completeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws
    -> GraphAPI.CompleteOnSessionCheckoutMutation.Data
  {
    self.completionInputs.append(input)
    return try await self.completions.request()
  }
  func project(_ param: Param) async throws -> Project {
    self.projectInputs.append(param)
    return try await self.projects.request()
  }
  func backing(_ id: Int) async throws -> Backing {
    self.backingInputs.append(id)
    return try await self.backings.request()
  }
  let creates = AccountRequestGate<CreateBackingEnvelope>()
  let updates = AccountRequestGate<UpdateBackingEnvelope>()
  let cancellations = AccountRequestGate<Void>()
  let receipts = AccountRequestGate<Backing>()
  var createInputs: [KsApi.CreateBackingInput] = []
  var updateInputs: [KsApi.UpdateBackingInput] = []
  var cancelInputs: [KsApi.CancelBackingInput] = []
  var receivedValues: [Bool] = []
  var receivedProjects: [Int] = []
  var receivedUsers: [Int] = []
  func create(_ input: KsApi.CreateBackingInput) async throws -> CreateBackingEnvelope {
    self.createInputs.append(input)
    return try await self.creates.request()
  }
  func update(_ input: KsApi.UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    self.updateInputs.append(input)
    return try await self.updates.request()
  }
  func cancel(_ input: KsApi.CancelBackingInput) async throws {
    self.cancelInputs.append(input)
    try await self.cancellations.request()
  }
  func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    self.receivedProjects.append(projectID)
    self.receivedUsers.append(userID)
    self.receivedValues.append(received)
    return try await self.receipts.request()
  }
  func releaseAll() {
    self.checkouts.releaseAll()
    self.validations.releaseAll()
    self.completions.releaseAll()
    self.projects.releaseAll()
    self.backings.releaseAll()
    self.creates.releaseAll()
    self.updates.releaseAll()
    self.cancellations.releaseAll()
    self.receipts.releaseAll()
  }
}
