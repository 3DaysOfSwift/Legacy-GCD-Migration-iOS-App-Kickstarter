@testable import Kickstarter_Framework
import PassKit
import XCTest

@MainActor
final class ApplePayTokenOperationTests: XCTestCase {
  func testPledgeImplementsPassKitAuthorizationSelector() {
    XCTAssertTrue(PledgeViewController.instancesRespond(to: #selector(
      PKPaymentAuthorizationViewControllerDelegate.paymentAuthorizationViewController(_:didAuthorizePayment:handler:)
    )))
  }

  func testBackgroundCallbackAndDuplicatesReplyOnce() async {
    let operation = ApplePayTokenOperation()
    var callback: (@Sendable (ApplePayTokenOutcome) -> Void)?
    var replies: [PKPaymentAuthorizationStatus] = []
    var applies = 0
    operation.start(isCurrent: { true }, begin: { callback = $0 }, apply: {
      MainActor.assertIsolated()
      XCTAssertEqual($0.tokenID, "token")
      applies += 1
      return .success
    }, reply: { replies.append($0.status) })
    let task = operation.task
    let deliver = callback
    await Task.detached {
      deliver?(.init(tokenID: "token", error: nil))
      deliver?(.init(tokenID: "duplicate", error: nil))
    }.value
    await task?.value
    XCTAssertEqual(applies, 1)
    XCTAssertEqual(replies, [.success])
  }

  func testCancellationRepliesFailureWithoutWaitingForSDK() async {
    let operation = ApplePayTokenOperation()
    var callback: (@Sendable (ApplePayTokenOutcome) -> Void)?
    var replies: [PKPaymentAuthorizationStatus] = []
    operation.start(isCurrent: { true }, begin: { callback = $0 }, apply: { _ in
      XCTFail("Cancelled token"); return .success
    }, reply: { replies.append($0.status) })
    let task = operation.task
    operation.cancelObservation()
    await task?.value
    callback?(.init(tokenID: "late", error: nil))
    XCTAssertEqual(replies, [.failure])
  }

  func testReleaseStillRepliesToPassKit() async {
    var operation: ApplePayTokenOperation? = ApplePayTokenOperation()
    weak var weakOperation = operation
    var replies: [PKPaymentAuthorizationStatus] = []
    operation?.start(isCurrent: { true }, begin: { _ in }, apply: { _ in
      XCTFail("Released owner"); return .success
    }, reply: { replies.append($0.status) })
    let task = operation?.task
    operation = nil
    await task?.value
    XCTAssertNil(weakOperation)
    XCTAssertEqual(replies, [.failure])
  }

  func testSessionReplacementSuppressesBackingButRepliesFailure() async {
    let operation = ApplePayTokenOperation()
    var callback: (@Sendable (ApplePayTokenOutcome) -> Void)?
    var current = true
    var replies: [PKPaymentAuthorizationStatus] = []
    operation.start(isCurrent: { current }, begin: { callback = $0 }, apply: { _ in
      XCTFail("Obsolete session"); return .success
    }, reply: { replies.append($0.status) })
    let task = operation.task
    current = false
    callback?(.init(tokenID: "late", error: nil))
    await task?.value
    XCTAssertEqual(replies, [.failure])
  }

  func testOverlappingAuthorizationGetsExplicitFailureAndDoesNotDuplicateTokenization() async {
    let operation = ApplePayTokenOperation()
    var starts = 0
    var replies: [PKPaymentAuthorizationStatus] = []
    operation.start(isCurrent: { true }, begin: { _ in starts += 1 }, apply: { _ in .success },
                    reply: { replies.append($0.status) })
    let task = operation.task
    operation.start(isCurrent: { true }, begin: { _ in starts += 1 }, apply: { _ in .success },
                    reply: { replies.append($0.status) })
    XCTAssertEqual(starts, 1)
    XCTAssertEqual(replies, [.failure])
    operation.cancelObservation()
    await task?.value
    XCTAssertEqual(replies, [.failure, .failure])
  }

  func testTokenFailurePreservesErrorAndAllowsLaterAttempt() async {
    let operation = ApplePayTokenOperation()
    for _ in 0..<2 {
      var replies: [PKPaymentAuthorizationStatus] = []
      operation.start(isCurrent: { true }, begin: { $0(.init(tokenID: nil, error: NSError(domain: "stripe", code: 4))) },
                      apply: { outcome in
        XCTAssertNil(outcome.tokenID)
        XCTAssertEqual((outcome.error as NSError?)?.code, 4)
        return .failure
      }, reply: { replies.append($0.status) })
      await operation.task?.value
      XCTAssertEqual(replies, [.failure])
      XCTAssertNil(operation.task)
    }
  }
}
