@testable import Kickstarter_Framework
import Library
import UIKit
import XCTest

@MainActor
final class ContextualPermissionAlertPresenterTests: XCTestCase {
  func testEquivalentRequestSharesDelayAndPreservesAlertContent() async throws {
    let gate = PermissionAlertGate()
    defer { gate.releaseAll() }
    let owner = ContextualPermissionAlertPresenter(sleep: gate.wait)
    let screen = PermissionAlertScreen()
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = screen
    window.isHidden = false
    defer { window.isHidden = true }
    let started = expectation(description: "settling delay")
    gate.started = { started.fulfill() }
    owner.schedule(context: .login, presenter: screen, accepted: {})
    owner.schedule(context: .login, presenter: screen, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    XCTAssertEqual(gate.durations, [.milliseconds(500)])
    let task = owner.task
    gate.releaseAll()
    await task?.value
    let alert = try XCTUnwrap(screen.alerts.first)
    XCTAssertEqual(screen.alerts.count, 1)
    XCTAssertEqual(alert.title, PushNotificationDialog.Context.login.title)
    XCTAssertEqual(alert.message, PushNotificationDialog.Context.login.message)
    XCTAssertEqual(alert.actions.map(\.style), [.default, .cancel])
    XCTAssertEqual(alert.actions.map(\.title), [Strings.project_star_ok(), PushNotificationDialog.titleForDismissal])
  }

  func testReplacementRejectsLatePreviousDelay() async {
    let gate = PermissionAlertGate()
    defer { gate.releaseAll() }
    let owner = ContextualPermissionAlertPresenter(sleep: gate.wait)
    let screen = PermissionAlertScreen()
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = screen; window.isHidden = false
    defer { window.isHidden = true }
    var started = expectation(description: "first")
    gate.started = { started.fulfill() }
    owner.schedule(context: .login, presenter: screen, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    let old = owner.task
    started = expectation(description: "replacement")
    owner.schedule(context: .save, presenter: screen, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    let current = owner.task
    gate.releaseAll() // Intentionally ignores cancellation, including the old timer.
    await old?.value; await current?.value
    XCTAssertEqual(screen.alerts.count, 1)
    XCTAssertEqual(screen.alerts.first?.title, PushNotificationDialog.Context.save.title)
  }

  func testBackgroundCancellationAndDetachedScreenSuppressPresentation() async {
    let gate = PermissionAlertGate()
    defer { gate.releaseAll() }
    let owner = ContextualPermissionAlertPresenter(sleep: gate.wait)
    let screen = PermissionAlertScreen()
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = screen; window.isHidden = false
    defer { window.isHidden = true }
    var started = expectation(description: "pending")
    gate.started = { started.fulfill() }
    owner.schedule(context: .login, presenter: screen, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    let old = owner.task
    owner.cancel()
    gate.releaseAll(); await old?.value
    XCTAssertTrue(screen.alerts.isEmpty)
    started = expectation(description: "detached")
    owner.schedule(context: .save, presenter: screen, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    let pending = owner.task
    window.rootViewController = nil
    gate.releaseAll(); await pending?.value
    XCTAssertTrue(screen.alerts.isEmpty)
  }

  func testPendingDelayRetainsNeitherPresenterNorOwner() async {
    let gate = PermissionAlertGate()
    defer { gate.releaseAll() }
    var owner: ContextualPermissionAlertPresenter? = ContextualPermissionAlertPresenter(sleep: gate.wait)
    var screen: PermissionAlertScreen? = PermissionAlertScreen()
    let started = expectation(description: "waiting")
    gate.started = { started.fulfill() }
    owner?.schedule(context: .login, presenter: screen!, accepted: {})
    await fulfillment(of: [started], timeout: 2)
    let pending = owner?.task
    weak var weakScreen = screen
    weak var weakOwner = owner
    screen = nil; owner = nil
    XCTAssertNil(weakScreen)
    XCTAssertNil(weakOwner)
    gate.releaseAll(); await pending?.value
  }
}

@MainActor
private final class PermissionAlertScreen: UIViewController {
  var alerts: [UIAlertController] = []
  override func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
    if let alert = viewController as? UIAlertController { self.alerts.append(alert) }
    completion?()
  }
}

@MainActor
private final class PermissionAlertGate {
  var durations: [Duration] = []
  var started: () -> Void = {}
  private var continuations: [CheckedContinuation<Void, Never>] = []
  func wait(_ duration: Duration) async throws {
    self.durations.append(duration)
    await withCheckedContinuation { continuation in
      self.continuations.append(continuation)
      self.started()
    }
  }
  func releaseAll() {
    let pending = self.continuations
    self.continuations.removeAll()
    pending.forEach { $0.resume() }
  }
}
