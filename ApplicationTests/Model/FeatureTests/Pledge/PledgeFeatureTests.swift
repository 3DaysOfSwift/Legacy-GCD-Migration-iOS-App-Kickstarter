@testable import Kickstarter_iOS
import Foundation
import GraphAPI
import ReactiveSwift
import XCTest

@testable import KsApi


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
    let input = self.createInput()
    let first = Task { try await self.feature.create(input) }
    await self.provider.creates.waitFor(1)
    let duplicate = Task { try await self.feature.create(input) }
    await Task.yield()
    XCTAssertEqual(self.provider.createInputs, [input])
    try self.provider.creates.finish(0, .success(self.created()))
    let values = try await [first.value, duplicate.value]
    XCTAssertEqual(self.provider.creates.count, 1)
    XCTAssertEqual(values.map { $0.createBacking.checkout.backing.clientSecret }, ["fixture-secret", "fixture-secret"])
  }

  func testDistinctCreateInputsQueueRatherThanShare() async throws {
    let firstInput = self.createInput(amount: "10.00")
    let secondInput = self.createInput(amount: "20.00")
    let first = Task { try await self.feature.create(firstInput) }
    await self.provider.creates.waitFor(1)
    let second = Task { try await self.feature.create(secondInput) }
    await Task.yield()
    try self.provider.creates.finish(0, .success(self.created()))
    await self.provider.creates.waitFor(2)
    XCTAssertEqual(self.provider.createInputs, [firstInput, secondInput])
    try self.provider.creates.finish(1, .success(self.created()))
    _ = try await first.value
    _ = try await second.value
  }

  func testUpdateThenCancelKeepsOrderEvenWhenUpdateFails() async throws {
    let updateInput = self.updateInput()
    let cancelInput = KsApi.CancelBackingInput(
      backingId: "backing", cancellationReason: "fixture note")
    let update = Task { try await self.feature.update(updateInput) }
    await self.provider.updates.waitFor(1)
    let cancel = Task { try await self.feature.cancel(cancelInput) }
    await Task.yield()
    XCTAssertEqual(self.provider.cancellations.count, 0)
    try self.provider.updates.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do {
      _ = try await update.value
      XCTFail("Expected update failure")
    } catch {}
    await self.provider.cancellations.waitFor(1)
    XCTAssertEqual(self.provider.updateInputs, [updateInput])
    XCTAssertEqual(self.provider.cancelInputs, [cancelInput])
    try self.provider.cancellations.finish(0, .success(()))
    try await cancel.value
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
    let input = KsApi.CancelBackingInput(backingId: "backing", cancellationReason: nil)
    let first = Task { try await self.feature.cancel(input) }
    await self.provider.cancellations.waitFor(1)
    let duplicate = Task { try await self.feature.cancel(input) }
    await Task.yield()
    try self.provider.cancellations.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    for task in [first, duplicate] {
      do { try await task.value; XCTFail("Expected failure") } catch {}
    }
    XCTAssertEqual(self.provider.cancellations.count, 1)
    let retry = Task { try await self.feature.cancel(input) }
    await self.provider.cancellations.waitFor(2)
    try self.provider.cancellations.finish(1, .success(()))
    try await retry.value
  }

  func testRewardToggleTrueFalseTrueRetainsEveryDistinctCommand() async throws {
    let first = self.feature.startReceived(projectID: 1, userID: 2, received: true)
    let duplicate = self.feature.startReceived(projectID: 1, userID: 2, received: true)
    let second = self.feature.startReceived(projectID: 1, userID: 2, received: false)
    let third = self.feature.startReceived(projectID: 1, userID: 2, received: true)
    for i in 0..<3 {
      await self.provider.receipts.waitFor(i + 1)
      try self.provider.receipts.finish(i, .success(.template))
    }
    _ = try await first.value
    _ = try await duplicate.value
    _ = try await second.value
    _ = try await third.value
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
      let second = Task { try await self.feature.cancelWithPresentationDelay(
        .init(backingId: "backing", cancellationReason: nil)) }
      defer { first.dispose() }
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
      do { try await second.value; XCTFail("Old session must not receive a result") }
      catch { XCTAssertTrue(error is CancellationError) }
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

  func testNativeCheckoutAdmissionSurvivesCancelledWaiterAndSharesRequest() async throws {
    let input = KsApi.CreateCheckoutInput(
      projectId: "p", amount: "10.00", locationId: nil, rewardIds: [], refParam: nil)
    let first = self.feature.startOpenCheckout(input)
    let second = self.feature.startOpenCheckout(input)
    first.cancel()
    await self.provider.checkouts.waitFor(1)
    XCTAssertEqual(self.provider.checkoutInputs, [input])
    try self.provider.checkouts.finish(
      0, .success(.init(checkout: .init(id: "checkout", paymentUrl: "fixture", backingId: "b"))))
    let checkout = try await second.value
    XCTAssertEqual(checkout.checkout.id, "checkout")
    do {
      _ = try await first.value
      XCTFail("The cancelled waiter should not deliver a result")
    } catch is CancellationError {} catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(self.provider.checkouts.count, 1)
  }

  func testCheckoutSharesEquivalentPendingInputsAndQueuesChangedAmount() async throws {
    let input = KsApi.CreateCheckoutInput(
      projectId: "p", amount: "10.00", locationId: "l", rewardIds: ["r", "r"], refParam: "ref")
    let changed = KsApi.CreateCheckoutInput(
      projectId: "p", amount: "20.00", locationId: "l", rewardIds: ["r", "r"], refParam: "ref")
    let first = self.feature.startOpenCheckout(input)
    let duplicate = self.feature.startOpenCheckout(input)
    let changedRequest = self.feature.startOpenCheckout(changed)
    await self.provider.checkouts.waitFor(1)
    XCTAssertEqual(self.provider.checkoutInputs, [input])
    try self.provider.checkouts.finish(
      0, .success(.init(checkout: .init(id: "checkout", paymentUrl: "fixture", backingId: "b"))))
    await self.provider.checkouts.waitFor(2)
    XCTAssertEqual(self.provider.checkoutInputs, [input, changed])
    try self.provider.checkouts.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    let values = try await [first.value, duplicate.value]
    XCTAssertEqual(values.map { $0.checkout.id }, ["checkout", "checkout"])
    do {
      _ = try await changedRequest.value
      XCTFail("Expected changed checkout to fail")
    } catch {}
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
    try self.provider.completions.finish(0, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(delivered, 1)
    XCTAssertEqual(self.provider.completions.count, 1)
  }

  func testSessionChangeSuppressesCheckoutAndRejectsQueuedCompletion() async throws {
    var completionDelivered = false
    let checkout = self.feature.startOpenCheckout(
      .init(projectId: "p", amount: "10", locationId: nil, rewardIds: [], refParam: nil))
    let completion = self.feature.completeCheckoutResult(
      .init(checkoutId: "c", paymentIntentClientSecret: "fixture")
    ).startWithResult { _ in completionDelivered = true }
    defer { completion.dispose() }
    await self.provider.checkouts.waitFor(1)
    self.session.sessionChanged()
    self.feature.reset()
    try self.provider.checkouts.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do {
      _ = try await checkout.value
      XCTFail("A replaced session must not receive a checkout")
    } catch is CancellationError {} catch {
      XCTFail("Expected cancellation after session change: \(error)")
    }
    await self.feature.waitForOperations()
    XCTAssertFalse(completionDelivered)
    XCTAssertEqual(self.provider.completions.count, 0)
  }

  func testBackingReadSharesPendingRequestButRefreshesAfterCompletion() async throws {
    let route = UUID()
    let a = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let secondStarted = expectation(description: "Second backing caller started")
    let b = Task {
      secondStarted.fulfill()
      return try await self.feature.backing(route: route, id: 1)
    }
    await fulfillment(of: [secondStarted], timeout: 2)
    try self.provider.backings.finish(0, .success(.template))
    _ = try await a.value
    _ = try await b.value
    let refresh = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(2)
    try self.provider.backings.finish(1, .success(.template))
    _ = try await refresh.value
    XCTAssertEqual(self.provider.backingInputs, [1, 1])
  }

  func testCanceledReadCallerCannotConsumeSharedSuccess() async throws {
    let route = UUID()
    let canceled = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let started = expectation(description: "Shared backing caller started")
    let observer = Task {
      started.fulfill()
      return try await self.feature.backing(route: route, id: 1)
    }
    await fulfillment(of: [started], timeout: 2)
    canceled.cancel()
    try self.provider.backings.finish(0, .success(.template))
    do {
      _ = try await canceled.value
      XCTFail("Canceled caller received a result")
    } catch { XCTAssertTrue(error is CancellationError) }
    _ = try await observer.value
    XCTAssertEqual(self.provider.backings.count, 1)
  }

  func testSharedReadFailureReachesBothWaitersWithoutRetry() async throws {
    let route = UUID()
    let failure = ErrorEnvelope(errorMessages: ["Unavailable"], ksrCode: nil, httpCode: 503, exception: nil)
    let first = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let started = expectation(description: "Second failing read started")
    let second = Task {
      started.fulfill()
      return try await self.feature.backing(route: route, id: 1)
    }
    await fulfillment(of: [started], timeout: 2)
    try self.provider.backings.finish(0, .failure(failure))
    for task in [first, second] {
      do {
        _ = try await task.value
        XCTFail("Expected shared read failure")
      } catch let error as ErrorEnvelope {
        XCTAssertEqual(error.errorMessages, ["Unavailable"])
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(self.provider.backings.count, 1)
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
    let write = Task { try await self.feature.cancel(.init(backingId: "b", cancellationReason: nil)) }
    await self.provider.cancellations.waitFor(1)
    let readStarted = expectation(description: "Backing refresh started")
    let read = Task {
      readStarted.fulfill()
      return try await self.feature.backing(route: UUID(), id: 1)
    }
    defer { read.cancel() }
    await fulfillment(of: [readStarted], timeout: 2)
    XCTAssertEqual(self.provider.backings.count, 0)
    try self.provider.cancellations.finish(0, .success(()))
    try await write.value
    await self.provider.backings.waitFor(1)
    try self.provider.backings.finish(0, .success(.template))
    _ = try await read.value
  }

  func testRefreshAfterMutationDoesNotJoinAnOlderPendingBackingRead() async throws {
    let route = UUID()
    let old = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.backings.waitFor(1)
    let write = Task { try await self.feature.cancel(.init(backingId: "b", cancellationReason: nil)) }
    await self.provider.cancellations.waitFor(1)
    let refresh = Task { try await self.feature.backing(route: route, id: 1) }
    await self.provider.cancellations.waitFor(1)
    try self.provider.cancellations.finish(0, .success(()))
    try await write.value
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

  func testOverviewReceiptChangesAreOrderedAndDuplicatesShare() async throws {
    let first = Task { try await self.feature.receipt(backingID: "B", received: true) }
    await self.provider.overviewReceipts.waitFor(1)
    let duplicate = Task { try await self.feature.receipt(backingID: "B", received: true) }
    await Task.yield()
    let next = Task { try await self.feature.receipt(backingID: "B", received: false) }
    await Task.yield()
    XCTAssertEqual(self.provider.receiptInputs.map { $0.1 }, [true])
    try self.provider.overviewReceipts.finish(0, .success(true))
    await self.provider.overviewReceipts.waitFor(2)
    XCTAssertEqual(self.provider.receiptInputs.map { $0.1 }, [true, false])
    try self.provider.overviewReceipts.finish(1, .success(true))
    let values = try await [first.value, duplicate.value, next.value]
    XCTAssertEqual(values, [true, true, true])
  }
  func testAddressWriteSettlesAfterCallerCancellationAndDoesNotRetry() async throws {
    let task = Task { try await self.feature.confirmAddress(backingID: "B", addressID: "A") }
    await self.provider.addresses.waitFor(1)
    task.cancel()
    try self.provider.addresses.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do {
      _ = try await task.value
      XCTFail("Cancelled caller must not receive a result")
    } catch { XCTAssertTrue(error is CancellationError) }
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.addressInputs.count, 1)
    XCTAssertEqual(self.provider.addressInputs.first?.1, "A")
  }
  func testPaymentPlanAmountChangeRejectsOldResult() async throws {
    let route = UUID()
    let old = Task { try await self.feature.paymentPlan(route: route, slug: "project", amount: "10.00") }
    await self.provider.plans.waitFor(1)
    let latest = Task { try await self.feature.paymentPlan(route: route, slug: "project", amount: "20.00") }
    await self.provider.plans.waitFor(2)
    try self.provider.plans.finish(1, .success(PledgePaymentPlan(amountIsPledgeOverTimeEligible: true, paymentIncrements: [])))
    try self.provider.plans.finish(0, .success(PledgePaymentPlan(amountIsPledgeOverTimeEligible: false, paymentIncrements: [])))
    do { _ = try await old.value; XCTFail("Old request must not deliver") }
    catch { XCTAssertTrue(error is CancellationError) }
    let plan = try await latest.value
    XCTAssertEqual(plan?.amountIsPledgeOverTimeEligible, true)
    XCTAssertEqual(self.provider.planInputs.map { $0.1 }, ["10.00", "20.00"])
  }

  func testPaymentPlanEquivalentPendingSharesAndReleaseSuppressesBothObservers() async throws {
    let route = UUID()
    let first = self.feature.requestPaymentPlan(route: route, slug: "project", amount: "10.00")
    let duplicate = self.feature.requestPaymentPlan(route: route, slug: "project", amount: "10.00")
    await self.provider.plans.waitFor(1)
    self.feature.releaseRead(route: route)
    try self.provider.plans.finish(0, .success(PledgePaymentPlan(amountIsPledgeOverTimeEligible: true, paymentIncrements: [])))
    for task in [first, duplicate] {
      do { _ = try await task.value; XCTFail("Released request must not deliver") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
    XCTAssertEqual(self.provider.planInputs.count, 1)
  }

  func testAbsentPaymentPlanIsDeliveredAsSuccessfulAbsence() async throws {
    let task = Task { try await self.feature.paymentPlan(route: UUID(), slug: "project", amount: "10.00") }
    await self.provider.plans.waitFor(1)
    try self.provider.plans.finish(0, .success(nil))
    let plan = try await task.value
    XCTAssertNil(plan)
  }

  func testCheckoutCompletionFailureIsDeliveredWithoutAutomaticRetry() async throws {
    let failure = ErrorEnvelope(errorMessages: ["Declined"], ksrCode: nil, httpCode: 400, exception: nil)
    var errors: [[String]] = []
    let observer = self.feature.completeCheckoutResult(
      .init(checkoutId: "c", paymentIntentClientSecret: "fixture")
    ).startWithResult {
      if case let .failure(error) = $0 { errors.append(error.errorMessages) }
      else { XCTFail("Failed completion acknowledged") }
    }
    defer { observer.dispose() }
    await self.provider.completions.waitFor(1)
    try self.provider.completions.finish(0, .failure(failure))
    await self.feature.waitForOperations()
    XCTAssertEqual(errors, [["Declined"]])
    XCTAssertEqual(self.provider.completions.count, 1)
  }

  func testPublicDemoRejectsAddressAndReceiptWrites() async {
    let provider = AsyncPledgeProvider(service: MockService.publicDemo())
    do {
      _ = try await provider.confirmAddress(backingID: "B", addressID: "A")
      XCTFail("Demo write accepted")
    } catch { XCTAssertNotNil(error as? ErrorEnvelope) }
    do {
      _ = try await provider.receipt(backingID: "B", received: true)
      XCTFail("Demo write accepted")
    } catch { XCTAssertNotNil(error as? ErrorEnvelope) }
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
  let updateProjects = AccountRequestGate<Project>()
  let projectUpdates = AccountRequestGate<Update>()
  var updateProjectInputs: [Param] = []
  var projectUpdateInputs: [(Int, Param)] = []
  func projectForUpdate(_ param: Param) async throws -> Project {
    self.updateProjectInputs.append(param)
    return try await self.updateProjects.request()
  }
  func projectUpdate(_ id: Int, param: Param) async throws -> Update {
    self.projectUpdateInputs.append((id, param))
    return try await self.projectUpdates.request()
  }
  let addresses = AccountRequestGate<Bool>()
  let overviewReceipts = AccountRequestGate<Bool>()
  let plans = AccountRequestGate<PledgePaymentPlan?>()
  var addressInputs: [(String, String)] = []
  var receiptInputs: [(String, Bool)] = []
  var planInputs: [(String, String)] = []
  func confirmAddress(backingID: String, addressID: String) async throws -> Bool {
    self.addressInputs.append((backingID, addressID))
    return try await self.addresses.request()
  }
  func receipt(backingID: String, received: Bool) async throws -> Bool {
    self.receiptInputs.append((backingID, received))
    return try await self.overviewReceipts.request()
  }
  func paymentPlan(slug: String, amount: String) async throws -> PledgePaymentPlan?
  {
    self.planInputs.append((slug, amount))
    return try await self.plans.request()
  }
  let checkouts = AccountRequestGate<CreateCheckoutEnvelope>()
  let validations = AccountRequestGate<ValidateCheckoutEnvelope>()
  let completions = AccountRequestGate<Void>()
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
    self.updateProjects.releaseAll()
    self.projectUpdates.releaseAll()
    self.addresses.releaseAll()
    self.overviewReceipts.releaseAll()
    self.plans.releaseAll()
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

extension PledgeFeatureTests {
  func testUpdateNavigationSharesPairAndPreservesIdentity() async throws {
    let route = UUID()
    let first = Task { try await self.feature.updateContext(route: route, param: .slug("first"), updateID: 42) }
    let second = Task { try await self.feature.updateContext(route: route, param: .slug("first"), updateID: 42) }
    await self.provider.updateProjects.waitFor(1)
    XCTAssertEqual(self.provider.projectUpdates.count, 0)
    try self.provider.updateProjects.finish(0, .success(.template))
    await self.provider.projectUpdates.waitFor(1)
    XCTAssertEqual(self.provider.projectUpdateInputs.map { $0.0 }, [42])
    XCTAssertEqual(self.provider.projectUpdateInputs.map { $0.1 }, [.slug("first")])
    try self.provider.projectUpdates.finish(0, .success(.template))
    await self.feature.waitForOperations()
    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue.0.id, Project.template.id)
    XCTAssertEqual(firstValue.1.id, Update.template.id)
    XCTAssertEqual(secondValue.0.id, Project.template.id)
    XCTAssertEqual(secondValue.1.id, Update.template.id)
  }

  func testChangedUpdateDestinationSuppressesLateProjectBeforeSecondStage() async throws {
    let route = UUID()
    let first = Task { try await self.feature.updateContext(route: route, param: .slug("old"), updateID: 1) }
    await self.provider.updateProjects.waitFor(1)
    let second = Task { try await self.feature.updateContext(route: route, param: .slug("new"), updateID: 2) }
    await self.provider.updateProjects.waitFor(2)
    try self.provider.updateProjects.finish(0, .success(.template))
    try self.provider.updateProjects.finish(1, .success(.template))
    await self.provider.projectUpdates.waitFor(1)
    XCTAssertEqual(self.provider.projectUpdateInputs.map { $0.0 }, [2])
    try self.provider.projectUpdates.finish(0, .success(.template))
    await self.feature.waitForOperations()
    do { _ = try await first.value; XCTFail("Obsolete update reached the screen") }
    catch { XCTAssertTrue(error is CancellationError) }
    _ = try await second.value
  }

  func testClosingWebScreenSuppressesLateUpdate() async throws {
    let vm = PledgeManagerWebViewModel(feature: self.feature)
    var navigation = 0
    vm.onEvent = { event in
      if case .presentUpdateVC = event { navigation += 1 }
    }
    vm.fetchUpdateVCData(param: .id(1), updateId: 2)
    await self.provider.updateProjects.waitFor(1)
    try self.provider.updateProjects.finish(0, .success(.template))
    await self.provider.projectUpdates.waitFor(1)
    vm.closeButtonTapped()
    try self.provider.projectUpdates.finish(0, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertEqual(navigation, 0)
  }

  func testUpdateNavigationRejectsReplacedSessionAndCanRetryAfterFailure() async throws {
    let route = UUID()
    let first = Task { try await self.feature.updateContext(route: route, param: .id(1), updateID: 2) }
    await self.provider.updateProjects.waitFor(1)
    self.session.sessionChanged()
    try self.provider.updateProjects.finish(0, .success(.template))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.projectUpdates.count, 0)
    do { _ = try await first.value; XCTFail("Stale session update succeeded") }
    catch { XCTAssertTrue(error is CancellationError) }
    let retry = Task { try await self.feature.updateContext(route: route, param: .id(1), updateID: 2) }
    await self.provider.updateProjects.waitFor(2)
    try self.provider.updateProjects.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    do { _ = try await retry.value; XCTFail("Expected update lookup failure") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    XCTAssertEqual(self.provider.projectUpdates.count, 0)
  }
}
