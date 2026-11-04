@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class SettingsProjectNotificationsTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledProjectNotificationsProvider()
  private let session = SessionFeature(makeProvider: {
    AsyncSessionProvider(service: AppEnvironment.current.apiService)
  })
  private lazy var feature = SettingsFeature(sessionFeature: self.session, makeProvider: { self.provider })

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
    }
  }

  override func tearDown() async throws {
    self.provider.reads.releaseAll()
    self.provider.writes.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testEquivalentTailSharesAndOnOffOnRemainsOrdered() async throws {
    let off = ProjectNotification.template
      |> ProjectNotification.lens.email .~ false |> ProjectNotification.lens.mobile .~ false
    let on = off |> ProjectNotification.lens.email .~ true |> ProjectNotification.lens.mobile .~ true
    let first = try self.feature.requestProjectNotificationSave(on)
    let duplicate = try self.feature.requestProjectNotificationSave(on)
    let second = try self.feature.requestProjectNotificationSave(off)
    let third = try self.feature.requestProjectNotificationSave(on)
    let observer = Task { _ = await first.result }
    observer.cancel()
    await self.provider.writes.waitFor(1)
    XCTAssertEqual(self.provider.sent.map(\.email), [true])
    try self.provider.writes.finish(0, .success(on))
    await self.provider.writes.waitFor(2)
    XCTAssertEqual(self.provider.sent.map(\.email), [true, false])
    try self.provider.writes.finish(1, .success(off))
    await self.provider.writes.waitFor(3)
    XCTAssertEqual(self.provider.sent.map(\.email), [true, false, true])
    try self.provider.writes.finish(2, .success(on))
    for command in [first, duplicate, second, third] { _ = try await command.value }
    await self.feature.waitForOperations()
    XCTAssertTrue(self.feature.cachedProjectNotification(off).email)
    XCTAssertTrue(self.feature.cachedProjectNotification(off).mobile)
  }

  func testFailureDoesNotCacheAndExplicitRetrySucceeds() async throws {
    let source = ProjectNotification.template
    let edited = source |> ProjectNotification.lens.email .~ true |> ProjectNotification.lens.mobile .~ true
    let failed = Task { try await self.feature.saveProjectNotification(edited) }
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await failed.value; XCTFail("Expected failure") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    XCTAssertFalse(self.feature.cachedProjectNotification(source).email)
    let retry = Task { try await self.feature.saveProjectNotification(edited) }
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(edited))
    _ = try await retry.value
    XCTAssertTrue(self.feature.cachedProjectNotification(source).email)
  }

  func testOldSessionWriteCannotCommitEvenWhenTransportIgnoresCancellation() async throws {
    let source = ProjectNotification.template
    let edited = source |> ProjectNotification.lens.email .~ true |> ProjectNotification.lens.mobile .~ true
    let pending = Task { try await self.feature.saveProjectNotification(edited) }
    await self.provider.writes.waitFor(1)
    self.session.sessionChanged()
    try self.provider.writes.finish(0, .success(edited))
    do { _ = try await pending.value; XCTFail("Old session committed") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertFalse(self.feature.cachedProjectNotification(source).email)
  }

  func testReadOvertakenByWriteCannotPublishAndFreshReadWorks() async throws {
    let source = ProjectNotification.template
    let read = Task { try await self.feature.projectNotifications() }
    await self.provider.reads.waitFor(1)
    let edit = Task { try await self.feature.saveProjectNotification(source) }
    await self.provider.writes.waitFor(1)
    try self.provider.reads.finish(0, .success([source]))
    do { _ = try await read.value; XCTFail("Stale list escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
    try self.provider.writes.finish(0, .success(source))
    _ = try await edit.value
    let fresh = Task { try await self.feature.projectNotifications() }
    await self.provider.reads.waitFor(2)
    try self.provider.reads.finish(1, .success([source]))
    let values = try await fresh.value
    XCTAssertEqual(values.map(\.id), [source.id])
  }

  func testOldSessionReadFailureIsSuppressed() async throws {
    let read = Task { try await self.feature.projectNotifications() }
    await self.provider.reads.waitFor(1)
    self.session.sessionChanged()
    try self.provider.reads.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await read.value; XCTFail("Old error escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
  }

  func testPublicDemoRejectsNotificationOperations() async {
    let provider = AsyncAccountPreferencesProvider(service: MockService.publicDemo())
    do { _ = try await provider.projectNotifications(); XCTFail("Demo account read succeeded") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    do { _ = try await provider.saveProjectNotification(.template); XCTFail("Demo write succeeded") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  func testReusedCellIgnoresPreviousProjectsSaveFailure() async throws {
    let vm = ProjectNotificationCellViewModel(feature: self.feature)
    var errors: [String] = []
    var switches: [Bool] = []
    vm.onError = { errors.append($0) }
    vm.onSwitch = { switches.append($0) }
    vm.configureWith(notification: .template)
    vm.notificationTapped(on: true)
    await self.provider.writes.waitFor(1)
    let other = ProjectNotification.template |> ProjectNotification.lens.id .~ 222
    vm.configureWith(notification: other)
    try self.provider.writes.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.feature.waitForOperations()
    await vm.waitForPresentation()
    XCTAssertEqual(errors, [])
    XCTAssertEqual(switches, [false, true, false])
  }

  func testDelayedErrorCannotReachReplacementSession() async throws {
    let delay = AccountRequestGate<Void>()
    defer { delay.releaseAll() }
    let vm = ProjectNotificationCellViewModel(feature: self.feature, sleep: { _ in try await delay.request() })
    var errors: [String] = []
    vm.onError = { errors.append($0) }
    vm.configureWith(notification: .template)
    vm.notificationTapped(on: true)
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await delay.waitFor(1)
    self.session.sessionChanged()
    try delay.finish(0, .success(()))
    await vm.waitForPresentation()
    XCTAssertEqual(errors, [])
  }

}

@MainActor
private final class ControlledProjectNotificationsProvider: AccountPreferencesProvider {
  let reads = AccountRequestGate<[ProjectNotification]>()
  let writes = AccountRequestGate<ProjectNotification>()
  var sent: [ProjectNotification] = []
  func projectNotifications() async throws -> [ProjectNotification] { try await self.reads.request() }
  func saveProjectNotification(_ notification: ProjectNotification) async throws -> ProjectNotification {
    self.sent.append(notification)
    return try await self.writes.request()
  }
  func save(_: User) async throws -> User { throw CancellationError() }
  func update(_: SettingsFeature.AccountChange) async throws -> User? { throw CancellationError() }
  func emailUser() async throws -> GraphUser { throw CancellationError() }
  func verifyEmail(token _: String) async throws -> EmailVerificationResponseEnvelope { throw CancellationError() }
}
