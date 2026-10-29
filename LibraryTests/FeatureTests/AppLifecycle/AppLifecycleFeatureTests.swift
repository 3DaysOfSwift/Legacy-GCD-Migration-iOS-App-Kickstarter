import UserNotifications
import AppTrackingTransparency
import Prelude
import ReactiveSwift
import XCTest
import SystemConfiguration

@testable import KsApi
@testable import Library

@MainActor
final class AppLifecycleFeatureTests: XCTestCase {
  private var provider: ControlledLifecycleProvider!
  private var feature: AppLifecycleFeature!
  private let route = UUID()
  private var connectivityMonitor: ControlledReachabilityMonitor!
  private var monitorStarts = 0

  override func setUp() async throws {
    try await super.setUp()
    let provider = ControlledLifecycleProvider()
    self.provider = provider
    let session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let settings = SettingsFeature(
      sessionFeature: session,
      makeProvider: { AsyncAccountPreferencesProvider(service: MockService()) })
    let messaging = MessagingFeature(
      sessionFeature: session, makeProvider: { AsyncMessagingProvider(service: MockService()) })
    self.connectivityMonitor = ControlledReachabilityMonitor()
    self.monitorStarts = 0
    self.feature = AppLifecycleFeature(
      sessionFeature: session, settingsFeature: settings, messagingFeature: messaging,
      makeProvider: { provider },
      makeReachabilityMonitor: { [weak self] in
        self?.monitorStarts += 1
        return self?.connectivityMonitor
      },
      authorizeNotifications: { options in
        provider.permissionOptions.append(options.rawValue)
        return (try? await provider.permissions.request()) ?? false
      }, registerNotifications: { provider.registrationCount += 1 },
      authorizeTracking: { (try? await provider.tracking.request()) ?? 0 },
      resolveRedirect: { _ in try await provider.redirects.request() }, sleep: { _ in try Task.checkCancellation() })
  }
  override func tearDown() async throws {
    self.feature?.reset()
    self.provider.releaseAll()
    await self.feature?.waitForOperations()
    try await super.tearDown()
  }
  private func link(_ id: Int = 1, _ subpage: Navigation.Project = .root) -> Navigation {
    .project(.id(id), subpage, refInfo: nil)
  }
  private func assertCancelled<T>(
    _ task: Task<T, Error>, file: StaticString = #filePath, line: UInt = #line
  ) async {
    if case .failure(is CancellationError) = await task.result {
    } else {
      XCTFail("Obsolete result escaped its owner", file: file, line: line)
    }
  }

  func testConnectivitySharesNativeMonitorAndSurvivesSessionReset() async {
    XCTAssertEqual(self.monitorStarts, 0)
    XCTAssertEqual(self.feature.connectivity, .wifi)
    var first: [Reachability] = []
    var second: [Reachability] = []
    let delivered = expectation(description: "both observers received offline")
    delivered.expectedFulfillmentCount = 2
    let a = self.feature.connectivityProducer.startWithValues {
      first.append($0)
      if $0 == .none { delivered.fulfill() }
    }
    let b = self.feature.connectivityProducer.startWithValues {
      second.append($0)
      if $0 == .none { delivered.fulfill() }
    }
    XCTAssertEqual(first, [.wifi])
    XCTAssertEqual(second, [.wifi])
    self.feature.reset()
    self.connectivityMonitor.continuation.yield(.wwan)
    self.connectivityMonitor.continuation.yield(.none)
    await fulfillment(of: [delivered], timeout: 2)
    XCTAssertEqual(first, [.wifi, .wwan, .none])
    XCTAssertEqual(second, first)
    XCTAssertEqual(self.monitorStarts, 1)
    a.dispose(); b.dispose()
  }

  func testConnectivityDisposalDoesNotStopOtherObserverAndFeatureReleaseStopsStream() async {
    let monitor = self.connectivityMonitor!
    let stopped = expectation(description: "stream cancelled")
    monitor.continuation.onTermination = { _ in stopped.fulfill() }
    let a = self.feature.connectivityProducer.startWithValues { _ in }
    a.dispose()
    let delivered = expectation(description: "remaining observer")
    let b = self.feature.connectivityProducer.startWithValues { if $0 == .wwan { delivered.fulfill() } }
    monitor.continuation.yield(.wwan)
    await fulfillment(of: [delivered], timeout: 2)
    b.dispose()
    weak var released = self.feature
    self.feature = nil
    XCTAssertNil(released)
    await fulfillment(of: [stopped], timeout: 2)
  }

  func testReachabilityPreservesNativeFlagClassification() {
    XCTAssertEqual(Reachability.from(flags: []), .none)
    XCTAssertEqual(Reachability.from(flags: [.reachable]), .wifi)
    XCTAssertEqual(Reachability.from(flags: [.isWWAN]), .wwan)
    XCTAssertEqual(Reachability.from(flags: [.isWWAN, .reachable]), .wwan)
    XCTAssertEqual(Reachability.from(flags: [.connectionRequired]), .none)
  }

  func testNativeReachabilityMonitorReleaseFinishesItsStream() async throws {
    var monitor: SystemReachabilityMonitor? = try XCTUnwrap(SystemReachabilityMonitor())
    let stream = try XCTUnwrap(monitor).updates
    weak var released = monitor
    monitor = nil
    XCTAssertNil(released)
    let ended = expectation(description: "native stream ended")
    let consumer = Task {
      for await _ in stream {}
      ended.fulfill()
    }
    await fulfillment(of: [ended], timeout: 2)
    consumer.cancel()
  }

  func testNotificationPromptSharesPendingRequestAndSurvivesObserverCancellation() async throws {
    let first = Task { await self.feature.notificationAuthorization(options: [.alert]) }
    await self.provider.permissions.waitFor(1)
    let second = Task { await self.feature.notificationAuthorization(options: [.alert]) }
    await Task.yield()
    first.cancel()
    self.feature.reset()
    try self.provider.permissions.finish(0, .success(true))
    let firstValue = await first.value
    let secondValue = await second.value
    XCTAssertTrue(firstValue)
    XCTAssertTrue(secondValue)
    XCTAssertEqual(self.provider.permissions.count, 1)
    XCTAssertEqual(self.provider.registrationCount, 1)
  }

  func testDistinctNotificationOptionsSerializeAndDeniedRequestDoesNotRegister() async throws {
    let first = Task { await self.feature.notificationAuthorization(options: [.alert]) }
    await self.provider.permissions.waitFor(1)
    let second = Task { await self.feature.notificationAuthorization(options: [.sound]) }
    await Task.yield()
    XCTAssertEqual(self.provider.permissions.count, 1)
    try self.provider.permissions.finish(0, .success(false))
    await self.provider.permissions.waitFor(2)
    try self.provider.permissions.finish(1, .success(true))
    _ = await first.value
    _ = await second.value
    XCTAssertEqual(self.provider.permissionOptions, [UNAuthorizationOptions.alert.rawValue, UNAuthorizationOptions.sound.rawValue])
    XCTAssertEqual(self.provider.registrationCount, 1)
  }

  func testTrackingPromptSharesAndAllowsLaterRequest() async throws {
    let first = Task { await self.feature.trackingAuthorization() }
    await self.provider.tracking.waitFor(1)
    let second = Task { await self.feature.trackingAuthorization() }
    await Task.yield()
    first.cancel()
    try self.provider.tracking.finish(0, .success(ATTrackingManager.AuthorizationStatus.authorized.rawValue))
    _ = await first.value
    let status = await second.value
    XCTAssertEqual(status, .authorized)
    XCTAssertEqual(self.provider.tracking.count, 1)
    let next = Task { await self.feature.trackingAuthorization() }
    await self.provider.tracking.waitFor(2)
    try self.provider.tracking.finish(1, .success(ATTrackingManager.AuthorizationStatus.denied.rawValue))
    let nextStatus = await next.value
    XCTAssertEqual(nextStatus, .denied)
  }

  func testRemoteConfigurationSharesClientAndRetriesAfterFailure() async throws {
    let client = NSObject()
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let first = self.feature.requestRemoteConfiguration(client: client) { try await gate.request() }
    let second = self.feature.requestRemoteConfiguration(client: client) { XCTFail("Duplicate activation") }
    await gate.waitFor(1)
    try gate.finish(0, .failure(URLError(.notConnectedToInternet)))
    for request in [first, second] {
      if case .success = await request.result { XCTFail("Failure was swallowed") }
    }
    let retry = self.feature.requestRemoteConfiguration(client: client) { try await gate.request() }
    await gate.waitFor(2)
    try gate.finish(1, .success(()))
    try await retry.value
    XCTAssertEqual(gate.count, 2)
  }

  func testRemoteConfigurationReplacementRejectsLateOldClientCompletion() async throws {
    let oldClient = NSObject(), newClient = NSObject()
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let old = self.feature.requestRemoteConfiguration(client: oldClient) { try await gate.request() }
    await gate.waitFor(1)
    let new = self.feature.requestRemoteConfiguration(client: newClient) { try await gate.request() }
    await gate.waitFor(2)
    try gate.finish(1, .success(()))
    try await new.value
    try gate.finish(0, .success(()))
    await self.assertCancelled(old)
  }

  func testRedirectSharesPendingURL() async throws {
    let url = try XCTUnwrap(URL(string: "https://example.test/click"))
    let first = Task { try await self.feature.firstRedirect(url, route: self.route) }
    await self.provider.redirects.waitFor(1)
    let second = Task { try await self.feature.firstRedirect(url, route: self.route) }
    await Task.yield()
    try self.provider.redirects.finish(0, .success(url))
    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue, url)
    XCTAssertEqual(secondValue, url)
    XCTAssertEqual(self.provider.redirects.count, 1)
  }
  func testNewNavigationRejectsNonCooperativeRedirect() async throws {
    let url = try XCTUnwrap(URL(string: "https://example.test/click"))
    let old = Task { try await self.feature.firstRedirect(url, route: self.route) }
    await self.provider.redirects.waitFor(1)
    _ = try await self.feature.requestDestination(.tab(.discovery(nil)), route: self.route).value
    try self.provider.redirects.finish(0, .success(url))
    await self.assertCancelled(old)
  }
  func testResetRejectsRedirectAndNextAttemptCanRetry() async throws {
    let url = try XCTUnwrap(URL(string: "https://example.test/click"))
    let old = Task { try await self.feature.firstRedirect(url, route: self.route) }
    await self.provider.redirects.waitFor(1)
    self.feature.reset()
    try self.provider.redirects.finish(0, .success(url))
    await self.assertCancelled(old)
    let next = Task { try await self.feature.firstRedirect(url, route: self.route) }
    await self.provider.redirects.waitFor(2)
    try self.provider.redirects.finish(1, .success(nil))
    let result = try await next.value
    XCTAssertNil(result)
  }
  func testRedirectResponsePreservesRelativeLocationAndIgnoresNonRedirect() throws {
    let url = try XCTUnwrap(URL(string: "https://example.test/click/original"))
    let redirect = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "../target"]))
    XCTAssertEqual(FirstRedirectResolver.destination(in: redirect)?.absoluteString, "https://example.test/target")
    let success = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Location": "/ignored"]))
    XCTAssertNil(FirstRedirectResolver.destination(in: success))
  }

  func testEquivalentConfigRefreshesShareAndNextRefreshLoadsAgain() async throws {
    let first = self.feature.requestConfiguration()
    let second = self.feature.requestConfiguration()
    await self.provider.config.waitFor(1)
    try self.provider.config.finish(0, .success(.template))
    _ = try await first.value
    _ = try await second.value
    let next = self.feature.requestConfiguration()
    await self.provider.config.waitFor(2)
    try self.provider.config.finish(1, .success(.template))
    _ = try await next.value
    XCTAssertEqual(self.provider.config.count, 2)
  }

  func testSameAccountReauthenticationRejectsOldConfiguration() async throws {
    let first = self.feature.requestConfiguration()
    await self.provider.config.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    let second = self.feature.requestConfiguration()
    await self.provider.config.waitFor(2)
    try self.provider.config.finish(0, .success(.template))
    try self.provider.config.finish(1, .success(.template))
    await self.assertCancelled(first)
    _ = try await second.value
  }

  func testEquivalentDestinationSharesCompleteChain() async throws {
    let first = self.feature.requestDestination(
      self.link(1, .update(42, .commentThread("comment", "reply"))), route: self.route)
    let second = self.feature.requestDestination(
      self.link(1, .update(42, .commentThread("comment", "reply"))), route: self.route)
    await self.provider.projects.waitFor(1)
    try self.provider.projects.finish(0, .success(.template |> Project.lens.id .~ 77))
    await self.provider.updates.waitFor(1)
    XCTAssertEqual(self.provider.updateInputs.first?.0, 42)
    XCTAssertEqual(self.provider.updateInputs.first?.1, .id(77))
    try self.provider.updates.finish(0, .success(.template))
    await self.provider.repliesGate.waitFor(1)
    try self.provider.repliesGate.finish(
      0,
      .success(
        CommentRepliesEnvelope(
          comment: .template, cursor: nil, hasPreviousPage: false, replies: [], totalCount: 0)))
    guard case .project(let value)? = try await first.value else {
      return XCTFail("Missing destination")
    }
    _ = try await second.value
    XCTAssertEqual(value.project.id, 77)
    XCTAssertEqual(value.update?.id, Update.template.id)
    XCTAssertEqual(value.replies?.comment.id, Comment.template.id)
    XCTAssertEqual(self.provider.projects.count, 1)
    XCTAssertEqual(self.provider.repliesGate.count, 1)
  }

  func testNewTabInvalidatesLateProjectAndDoesNotStartItsUpdate() async throws {
    let old = self.feature.requestDestination(self.link(1, .update(42, .root)), route: self.route)
    await self.provider.projects.waitFor(1)
    _ = try await self.feature.resolve(.tab(.search), route: self.route)
    try self.provider.projects.finish(0, .success(.template))
    await self.assertCancelled(old)
    XCTAssertEqual(self.provider.updates.count, 0)
  }

  func testNewProjectSuppressesOldRepliesEvenIfTransportIgnoresCancellation() async throws {
    let old = self.feature.requestDestination(
      self.link(1, .commentThread("old", nil)), route: self.route)
    await self.provider.projects.waitFor(1)
    try self.provider.projects.finish(0, .success(.template))
    await self.provider.repliesGate.waitFor(1)
    let new = self.feature.requestDestination(self.link(2), route: self.route)
    await self.provider.projects.waitFor(2)
    try self.provider.projects.finish(1, .success(.template |> Project.lens.id .~ 2))
    try self.provider.repliesGate.finish(
      0,
      .success(
        CommentRepliesEnvelope(
          comment: .template, cursor: nil, hasPreviousPage: false, replies: [], totalCount: 0)))
    await self.assertCancelled(old)
    guard case .project(let value)? = try await new.value else {
      return XCTFail("Missing destination")
    }
    XCTAssertEqual(value.project.id, 2)
    XCTAssertNil(value.replies)
  }

  func testReleasingRouteSuppressesLateFailure() async throws {
    let old = self.feature.requestDestination(self.link(), route: self.route)
    await self.provider.projects.waitFor(1)
    self.feature.release(route: self.route)
    try self.provider.projects.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    // Cancellation takes priority over transport failure for removed routes.
    await self.assertCancelled(old)
  }

  func testSameAccountReauthenticationRejectsOldUpdateAndSkipsReplies() async throws {
    let old = self.feature.requestDestination(
      self.link(1, .update(42, .commentThread("old", nil))), route: self.route)
    await self.provider.projects.waitFor(1)
    try self.provider.projects.finish(0, .success(.template))
    await self.provider.updates.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    try self.provider.updates.finish(0, .success(.template))
    await self.assertCancelled(old)
    XCTAssertEqual(self.provider.repliesGate.count, 0)
  }

  func testCategoryLookupClearedByNonCategoryDiscoveryLink() async throws {
    let old = self.feature.requestDestination(
      .tab(.discovery(["category_id": "art"])), route: self.route)
    await self.provider.categoriesGate.waitFor(1)
    guard
      case .discovery(nil)? = try await self.feature.resolve(
        .tab(.discovery(nil)), route: self.route)
    else {
      return XCTFail("Cleared discovery must still navigate")
    }
    try self.provider.categoriesGate.finish(0, .success(.template))
    await self.assertCancelled(old)
  }

  func testPrelaunchDoesNotLoadPrivateSubpages() async throws {
    let task = self.feature.requestDestination(self.link(1, .update(42, .root)), route: self.route)
    await self.provider.projects.waitFor(1)
    try self.provider.projects.finish(
      0, .success(.template |> Project.lens.displayPrelaunch .~ true))
    let value = try await task.value
    XCTAssertNil(value)
    XCTAssertEqual(self.provider.updates.count, 0)
  }

  func testRecommendationFailureKeepsFallbackShortcuts() async throws {
    let task = Task { try await self.feature.hasRecommendations(for: .template) }
    await self.provider.recommendationsGate.waitFor(1)
    try self.provider.recommendationsGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    let hasRecommendations = try await task.value
    XCTAssertFalse(hasRecommendations)
  }

  func testLoggedOutShortcutDoesNotFetchRecommendations() async throws {
    let value = try await self.feature.hasRecommendations(for: nil)
    XCTAssertFalse(value)
    XCTAssertEqual(self.provider.recommendationsGate.count, 0)
  }

  func testPushDuplicatesShareAndChangedTokensExecuteInOrderAfterFailure() async throws {
    let first = self.feature.requestPushRegistration(token: "synthetic-a")
    let duplicate = self.feature.requestPushRegistration(token: "synthetic-a")
    let second = self.feature.requestPushRegistration(token: "synthetic-b")
    await self.provider.registrations.waitFor(1)
    XCTAssertEqual(self.provider.tokens, ["synthetic-a"])
    try self.provider.registrations.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.registrations.waitFor(2)
    try self.provider.registrations.finish(1, .success(()))
    if case .success = await first.result { XCTFail("Expected registration failure") }
    if case .success = await duplicate.result { XCTFail("Expected shared failure") }
    let token = try await second.value
    XCTAssertEqual(token, "synthetic-b")
    XCTAssertEqual(self.provider.tokens, ["synthetic-a", "synthetic-b"])
  }

  func testSessionChangePreventsQueuedRegistrationAndOldSuccess() async throws {
    let first = self.feature.requestPushRegistration(token: "synthetic-a")
    let next = self.feature.requestPushRegistration(token: "synthetic-b")
    await self.provider.registrations.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    self.feature.reset()
    try self.provider.registrations.finish(0, .success(()))
    await self.assertCancelled(first)
    await self.assertCancelled(next)
    XCTAssertEqual(self.provider.tokens, ["synthetic-a"])
  }

  func testDisposingObserverDoesNotCancelAdmittedRegistration() async throws {
    let request = self.feature.requestPushRegistration(token: "synthetic-a")
    var values: [String] = []
    let observer = self.feature.result { try await request.value }.startWithResult {
      if case .success(let value) = $0 { values.append(value) }
    }
    await self.provider.registrations.waitFor(1)
    observer.dispose()
    try self.provider.registrations.finish(0, .success(()))
    _ = try await request.value
    await self.feature.waitForOperations()
    XCTAssertTrue(values.isEmpty)
    XCTAssertEqual(self.provider.tokens, ["synthetic-a"])
  }
}

@MainActor
private final class ControlledLifecycleProvider: AppLifecycleProvider {
  let permissions = AccountRequestGate<Bool>()
  let tracking = AccountRequestGate<UInt>()
  var permissionOptions: [UInt] = []
  var registrationCount = 0
  let redirects = AccountRequestGate<URL?>()
  let config = AccountRequestGate<Config>()
  let registrations = AccountRequestGate<Void>()
  let recommendationsGate = AccountRequestGate<Int>()
  let categoriesGate = AccountRequestGate<RootCategoriesEnvelope>()
  let surveys = AccountRequestGate<SurveyResponse>()
  let projects = AccountRequestGate<Project>()
  let updates = AccountRequestGate<Update>()
  let repliesGate = AccountRequestGate<CommentRepliesEnvelope>()
  var tokens: [String] = []
  var updateInputs: [(Int, Param)] = []
  func configuration() async throws -> Config { try await self.config.request() }
  func register(token: String) async throws {
    self.tokens.append(token)
    try await self.registrations.request()
  }
  func recommendations() async throws -> Int { try await self.recommendationsGate.request() }
  func categories() async throws -> RootCategoriesEnvelope {
    try await self.categoriesGate.request()
  }
  func survey(id: Int) async throws -> SurveyResponse { try await self.surveys.request() }
  func project(param: Param) async throws -> Project { try await self.projects.request() }
  func update(id: Int, project: Param) async throws -> Update {
    self.updateInputs.append((id, project))
    return try await self.updates.request()
  }
  func replies(id: String) async throws -> CommentRepliesEnvelope {
    try await self.repliesGate.request()
  }
  func releaseAll() {
    self.permissions.releaseAll()
    self.tracking.releaseAll()
    self.redirects.releaseAll()
    self.config.releaseAll()
    self.registrations.releaseAll()
    self.recommendationsGate.releaseAll()
    self.categoriesGate.releaseAll()
    self.surveys.releaseAll()
    self.projects.releaseAll()
    self.updates.releaseAll()
    self.repliesGate.releaseAll()
  }
}

private final class ControlledReachabilityMonitor: ReachabilityMonitoring {
  let initial: Reachability = .wifi
  let updates: AsyncStream<Reachability>
  let continuation: AsyncStream<Reachability>.Continuation
  init() { (self.updates, self.continuation) = AsyncStream<Reachability>.makeStream() }
}
