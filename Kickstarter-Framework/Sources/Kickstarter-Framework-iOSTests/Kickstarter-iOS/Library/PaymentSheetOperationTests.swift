@testable import Kickstarter_Framework
import UIKit
import XCTest

@MainActor
final class PaymentSheetOperationTests: XCTestCase {
  func testSuccessAndDuplicateCallbacksOnlyConfirmAndCompleteOnce() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    var methods: [String?] = []
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: true,
                    isCurrent: { true }, completed: {
      if case let .completed(method) = $0 { methods.append(method) }
    })
    let task = operation.task
    client.loaded?(nil)
    client.loaded?(nil)
    await task?.value
    XCTAssertEqual(client.presentations, 1)
    XCTAssertEqual(client.confirmations, 1)
    XCTAssertEqual(client.lookups, 1)
    XCTAssertEqual(methods, ["pm_test"])
    XCTAssertNil(operation.task)
  }

  func testSettingsCompletionDoesNotRetrieveMethod() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    var completed = false
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { if case .completed = $0 { completed = true } })
    let task = operation.task
    client.loaded?(nil)
    await task?.value
    XCTAssertTrue(completed)
    XCTAssertEqual(client.lookups, 0)
  }

  func testEquivalentPendingStartSharesAndDistinctStartFails() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let other = SheetClient()
    let presenter = UIViewController()
    var completions = 0
    operation.start(clientSecret: "first", client: client, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { _ in completions += 1 })
    operation.start(clientSecret: "first", client: other, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { _ in XCTFail("Duplicate observer") })
    var rejected = false
    operation.start(clientSecret: "different", client: other, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { if case .failed = $0 { rejected = true } })
    XCTAssertTrue(rejected)
    XCTAssertEqual(other.loads, 0)
    let task = operation.task
    client.loaded?(nil)
    await task?.value
    XCTAssertEqual(completions, 1)
  }

  func testCanceledLoadCannotPresentAfterReplacement() async {
    let operation = PaymentSheetOperation()
    let old = SheetClient()
    let next = SheetClient()
    let presenter = UIViewController()
    operation.start(clientSecret: "old", client: old, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { _ in XCTFail("Obsolete result") })
    let oldTask = operation.task
    operation.cancelObservation()
    operation.start(clientSecret: "next", client: next, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { _ in })
    let nextTask = operation.task
    old.loaded?(nil)
    next.loaded?(nil)
    await oldTask?.value
    await nextTask?.value
    XCTAssertEqual(old.presentations, 0)
    XCTAssertEqual(next.presentations, 1)
  }

  func testSessionChangeBeforeLoadDoesNotPresent() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    var current = true
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { current }, completed: { _ in XCTFail("Obsolete session") })
    let task = operation.task
    current = false
    client.loaded?(nil)
    await task?.value
    XCTAssertEqual(client.presentations, 0)
    XCTAssertNil(operation.task)
  }

  func testSessionChangeDuringConfirmationDoesNotStartLookup() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    var current = true
    client.onConfirm = { current = false }
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: true,
                    isCurrent: { current }, completed: { _ in XCTFail("Obsolete session") })
    let task = operation.task
    client.loaded?(nil)
    await task?.value
    XCTAssertEqual(client.lookups, 0)
  }

  func testOwnerReleaseFinishesWithoutSDKCallback() async {
    var operation: PaymentSheetOperation? = PaymentSheetOperation()
    weak var weakOperation = operation
    let client = SheetClient()
    let presenter = UIViewController()
    operation?.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: false,
                     isCurrent: { true }, completed: { _ in XCTFail("Released owner") })
    let task = operation?.task
    operation = nil
    await task?.value
    XCTAssertNil(weakOperation)
    client.loaded?(nil)
    XCTAssertEqual(client.presentations, 0)
  }

  func testLoadFailureSelectionCancelAndConfirmationFailureStayDistinct() async {
    let presenter = UIViewController()
    for scenario in 0..<4 {
      let operation = PaymentSheetOperation()
      let client = SheetClient()
      client.hasPaymentOption = scenario != 1
      client.result = scenario == 2 ? .canceled : .failed(NSError(domain: "test", code: 3))
      var received = false
      operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: true,
                      isCurrent: { true }, completed: { result in
        switch (scenario, result) {
        case (0, .loadFailed), (1, .noSelection), (2, .canceled), (3, .failed): received = true
        default: XCTFail("Wrong outcome")
        }
      })
      let task = operation.task
      client.loaded?(scenario == 0 ? NSError(domain: "load", code: 1) : nil)
      await task?.value
      XCTAssertTrue(received)
      XCTAssertEqual(client.lookups, 0)
    }
  }

  func testReleaseWhileConfirmationIsPendingFinishesWithoutRetainingOwner() async {
    var operation: PaymentSheetOperation? = PaymentSheetOperation()
    weak var weakOperation = operation
    let client = SheetClient()
    let presenter = UIViewController()
    let confirming = expectation(description: "Native confirmation started")
    client.completesConfirmation = false
    client.onConfirm = { confirming.fulfill() }
    operation?.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: true,
                     isCurrent: { true }, completed: { _ in XCTFail("Released owner") })
    let task = operation?.task
    client.loaded?(nil)
    await fulfillment(of: [confirming], timeout: 2)
    operation = nil
    await task?.value
    XCTAssertNil(weakOperation)
    client.confirmed?(.completed(paymentMethodID: nil))
    XCTAssertEqual(client.lookups, 0)
  }

  func testCancelPreparationDoesNotCancelPresentedConfirmation() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    client.onConfirm = { operation.cancelBeforePresentation() }
    var completed = false
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { if case .completed = $0 { completed = true } })
    let task = operation.task
    client.loaded?(nil)
    await task?.value
    XCTAssertTrue(completed)
  }

  func testCancelPreparationPreventsLatePresentation() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    let presenter = UIViewController()
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: false,
                    isCurrent: { true }, completed: { _ in XCTFail("Cancelled preparation") })
    let task = operation.task
    operation.cancelBeforePresentation()
    client.loaded?(nil)
    await task?.value
    XCTAssertEqual(client.presentations, 0)
  }

  func testMissingOptionalMethodStillCompletesCardAddition() async {
    let operation = PaymentSheetOperation()
    let client = SheetClient()
    client.method = nil
    let presenter = UIViewController()
    var completed = false
    operation.start(clientSecret: "test", client: client, presenter: presenter, retrievePaymentMethod: true,
                    isCurrent: { true }, completed: {
      if case let .completed(method) = $0 { completed = true; XCTAssertNil(method) }
    })
    let task = operation.task
    client.loaded?(nil)
    await task?.value
    XCTAssertTrue(completed)
  }
}

@MainActor
private final class SheetClient: PaymentSheetClient {
  var hasPaymentOption = true
  var loaded: (@MainActor (Error?) -> Void)?
  var loads = 0
  var presentations = 0
  var confirmations = 0
  var lookups = 0
  var result = PaymentSheetOutcome.completed(paymentMethodID: nil)
  var method: String? = "pm_test"
  var onConfirm: () -> Void = {}
  var completesConfirmation = true
  var confirmed: (@Sendable (PaymentSheetOutcome) -> Void)?
  func load(completion: @escaping @MainActor (Error?) -> Void) { loads += 1; loaded = completion }
  func present(from presenter: UIViewController, completion: @escaping @MainActor () -> Void) {
    presentations += 1; completion(); completion()
  }
  func confirm(from presenter: UIViewController, completion: @escaping @Sendable (PaymentSheetOutcome) -> Void) {
    confirmations += 1; confirmed = completion; onConfirm()
    if completesConfirmation { completion(result); completion(result) }
  }
  func paymentMethod(completion: @escaping @Sendable (String?) -> Void) {
    lookups += 1; completion(method); completion(method)
  }
}
