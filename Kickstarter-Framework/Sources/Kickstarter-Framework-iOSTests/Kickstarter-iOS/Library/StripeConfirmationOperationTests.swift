@testable import Kickstarter_Framework
import Library
import Stripe
import XCTest

@MainActor
final class StripeConfirmationOperationTests: XCTestCase {
  private let identity = StripeConfirmationOperation.Identity(kind: .payment, clientSecret: "test-secret")

  func testSynchronousCompletionAndDuplicateDeliverOnce() async {
    let operation = StripeConfirmationOperation()
    var statuses: [StripePaymentHandlerActionStatus] = []
    operation.start(identity: self.identity, begin: { callback in
      callback(.init(status: .succeeded, error: nil))
      callback(.init(status: .failed, error: nil))
    }, completed: { statuses.append($0.status) })
    await operation.task?.value
    XCTAssertEqual(statuses, [.succeeded])
    XCTAssertNil(operation.task)
  }

  func testEquivalentPendingStartSharesOneNativeOperation() async {
    let operation = StripeConfirmationOperation()
    var callback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    var starts = 0
    var completions = 0
    operation.start(identity: self.identity, begin: { callback = $0; starts += 1 }, completed: { _ in completions += 1 })
    operation.start(identity: self.identity, begin: { _ in starts += 1 }, completed: { _ in XCTFail("Duplicate delivery") })
    callback?(.init(status: .succeeded, error: nil))
    await operation.task?.value
    XCTAssertEqual(starts, 1)
    XCTAssertEqual(completions, 1)
  }

  func testDifferentPendingStartFailsWithoutReplacingActiveConfirmation() async {
    let operation = StripeConfirmationOperation()
    var callback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    var first: StripePaymentHandlerActionStatus?
    var second: StripeConfirmationOutcome?
    operation.start(identity: self.identity, begin: { callback = $0 }, completed: { first = $0.status })
    operation.start(identity: .init(kind: .setup, clientSecret: "other-secret"), begin: { _ in XCTFail("Started concurrent confirmation") }, completed: { second = $0 })
    XCTAssertEqual(second?.status, .failed)
    XCTAssertNotNil(second?.error)
    callback?(.init(status: .succeeded, error: nil))
    await operation.task?.value
    XCTAssertEqual(first, .succeeded)
  }

  func testCancellationAndReplacementRejectOldCompletion() async {
    let operation = StripeConfirmationOperation()
    var oldCallback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    var currentCallback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    var current: StripePaymentHandlerActionStatus?
    operation.start(identity: self.identity, begin: { oldCallback = $0 }, completed: { _ in XCTFail("Cancelled observation delivered") })
    let oldTask = operation.task
    operation.cancelObservation()
    operation.start(identity: self.identity, begin: { currentCallback = $0 }, completed: { current = $0.status })
    oldCallback?(.init(status: .succeeded, error: nil))
    currentCallback?(.init(status: .canceled, error: nil))
    await oldTask?.value
    await operation.task?.value
    XCTAssertEqual(current, .canceled)
  }

  func testReleaseFinishesWaitingWithoutRequiringSDKCompletion() async {
    var operation: StripeConfirmationOperation? = StripeConfirmationOperation()
    weak var released = operation
    var callback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    operation?.start(identity: self.identity, begin: { callback = $0 }, completed: { _ in XCTFail("Released observer delivered") })
    let task = operation?.task
    operation = nil
    XCTAssertNil(released)
    await task?.value
    callback?(.init(status: .succeeded, error: nil))
  }

  func testBackgroundCompletionDeliversOnMainActorAndPreservesError() async {
    let operation = StripeConfirmationOperation()
    let error = NSError(domain: "ConfirmationFixture", code: 17)
    var callback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    var received: NSError?
    operation.start(identity: self.identity, begin: { callback = $0 }, completed: { outcome in
      MainActor.assertIsolated()
      XCTAssertEqual(outcome.status, .failed)
      received = outcome.error as NSError?
    })
    let completion = callback
    await Task.detached { completion?(.init(status: .failed, error: error)) }.value
    await operation.task?.value
    XCTAssertEqual(received?.domain, error.domain)
    XCTAssertEqual(received?.code, error.code)
  }

  func testSessionChangeSuppressesResultAndReleasesPendingOperation() async {
    let operation = StripeConfirmationOperation()
    var session = 1
    var callback: (@Sendable (StripeConfirmationOutcome) -> Void)?
    operation.start(identity: self.identity, isCurrent: { session == 1 }, begin: { callback = $0 }, completed: { _ in
      XCTFail("A previous session must not commit checkout work")
    })
    session = 2
    callback?(.init(status: .succeeded, error: nil))
    await operation.task?.value
    XCTAssertNil(operation.task)
    var received = false
    operation.start(identity: self.identity, begin: { $0(.init(status: .succeeded, error: nil)) }, completed: { _ in received = true })
    await operation.task?.value
    XCTAssertTrue(received)
  }

}
