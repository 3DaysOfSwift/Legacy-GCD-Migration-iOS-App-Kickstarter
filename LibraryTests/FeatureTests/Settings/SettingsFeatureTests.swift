@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class SettingsFeatureTests: XCTestCase {
  func testSignedOutCommandDoesNotReachProvider() async throws {
    let fixture = PreferencesFixture()
    fixture.user = nil
    let subscription = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: .template).start()
    defer { subscription.dispose(); fixture.provider.gate.releaseAll() }
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 0)
    XCTAssertEqual(fixture.commits, 0)
  }

  func testDemoPreferencesCannotPretendToSave() async {
    let provider = AsyncAccountPreferencesProvider(service: MockService.publicDemo())
    do { _ = try await provider.save(.template); XCTFail("Demo unexpectedly saved account data") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  func testQueuedEditsMergeConfirmedPreferencesInsteadOfStaleCellSnapshots() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let original = try XCTUnwrap(fixture.user)
    let first = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: original).start()
    let second = fixture.feature.saveResult([.init(.notification(.messages), true)], from: original).start()
    defer { first.dispose(); second.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.sent.count, 1)
    try fixture.provider.succeed(0)
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, true)
    XCTAssertEqual(fixture.provider.sent[1].notifications.messages, true)
    try fixture.provider.succeed(1)
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.notifications.messages, true)
    XCTAssertEqual(fixture.commits, 2)
  }

  func testEquivalentTailSharesButOnOffOnRemainsOrdered() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    var completions = 0
    let changes: [SettingsFeature.Change] = [.init(.newsletter(.arts), true)]
    let a = fixture.feature.saveResult(changes, from: user).start { if case .value = $0 { completions += 1 } }
    let duplicate = fixture.feature.saveResult(changes, from: user)
      .start { if case .value = $0 { completions += 1 } }
    let b = fixture.feature.saveResult([.init(.newsletter(.arts), false)], from: user).start()
    let c = fixture.feature.saveResult(changes, from: user).start()
    defer { a.dispose(); duplicate.dispose(); b.dispose(); c.dispose() }
    for index in 0..<3 {
      await fixture.provider.gate.waitFor(index + 1)
      XCTAssertEqual(fixture.provider.sent[index].newsletters.arts, index != 1)
      try fixture.provider.succeed(index)
    }
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 3)
    XCTAssertEqual(completions, 2)
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
  }

  func testFailureDoesNotPoisonNextWriteAndRetryIsPossible() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    var failures = 0
    let a = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: user)
      .startWithFailed { _ in failures += 1 }
    let b = fixture.feature.saveResult([.init(.notification(.messages), true)], from: user).start()
    defer { a.dispose(); b.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, user.newsletters.arts)
    XCTAssertEqual(failures, 1)
    XCTAssertNotNil(fixture.feature.lastError)
    try fixture.provider.succeed(1)
    await fixture.feature.waitForOperations()
    let retry = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: user).start()
    defer { retry.dispose() }
    await fixture.provider.gate.waitFor(3)
    try fixture.provider.succeed(2)
    await fixture.feature.waitForOperations()
    XCTAssertNil(fixture.feature.lastError)
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.notifications.messages, true)
  }

  func testDisposedPresentationDoesNotAbandonAdmittedWrite() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    var delivered = false
    let subscription = fixture.feature.saveResult(
      [.init(.privacy(.following), false)],
      from: try XCTUnwrap(fixture.user)
    ).start { if case .value = $0 { delivered = true } }
    await fixture.provider.gate.waitFor(1)
    subscription.dispose()
    try fixture.provider.succeed(0)
    await fixture.feature.waitForOperations()
    XCTAssertFalse(delivered)
    XCTAssertEqual(fixture.commits, 1)
    XCTAssertEqual(fixture.user?.social, false)
  }

  func testCancelledAsyncWaiterDoesNotCancelAdmittedMutation() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let task = Task { try await fixture.feature.save([.init(.privacy(.following), false)], from: user) }
    await fixture.provider.gate.waitFor(1)
    task.cancel()
    try fixture.provider.succeed(0)
    do { _ = try await task.value; XCTFail("Cancelled waiter returned success") }
    catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.commits, 1)
  }

  func testLogoutRejectsOldSuccessAndDoesNotDispatchQueuedAccountWrite() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    var values = 0
    let a = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: user)
      .start { if case .value = $0 { values += 1 } }
    let b = fixture.feature.saveResult([.init(.notification(.messages), true)], from: user)
      .start { if case .value = $0 { values += 1 } }
    defer { a.dispose(); b.dispose() }
    await fixture.provider.gate.waitFor(1)
    fixture.user = nil
    fixture.session.sessionChanged()
    try fixture.provider.succeed(0)
    await fixture.feature.waitForOperations()
    XCTAssertEqual(values, 0)
    XCTAssertEqual(fixture.provider.sent.count, 1)
    XCTAssertEqual(fixture.commits, 0)
    XCTAssertNil(fixture.user)
  }

  func testSameAccountNewSessionRejectsOldErrorAndCanSaveIndependently() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    var failures = 0
    let old = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: user)
      .startWithFailed { _ in failures += 1 }
    defer { old.dispose() }
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged()
    let new = fixture.feature.saveResult([.init(.notification(.messages), true)], from: user).start()
    defer { new.dispose() }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.succeed(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(failures, 0)
    XCTAssertEqual(fixture.commits, 1)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testAllNewslettersCommandPreservesOtherPreferences() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let subscription = fixture.feature.saveResult(SettingsFeature.Change.allNewsletters(true), from: user)
      .start()
    defer { subscription.dispose() }
    await fixture.provider.gate.waitFor(1)
    let sent = try XCTUnwrap(fixture.provider.sent.first)
    for newsletter in Newsletter.allCases {
      XCTAssertEqual(sent[keyPath: UserAttribute.newsletter(newsletter).keyPath], true)
    }
    XCTAssertEqual(sent.notifications.messages, user.notifications.messages)
    XCTAssertEqual(sent.social, user.social)
    try fixture.provider.succeed(0)
    await fixture.feature.waitForOperations()
  }

  func testOlderReadCannotOverwriteCompletedPreferenceWrite() async throws {
    let fixture = PreferencesFixture()
    let users = ControlledPreferencesReadProvider()
    let session = SessionFeature(
      makeProvider: { users },
      currentUser: { fixture.user },
      updateUser: { fixture.user = $0 }
    )
    let feature = SettingsFeature(sessionFeature: session, makeProvider: { fixture.provider })
    defer { fixture.provider.gate.releaseAll(); users.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    var refreshValues: [User] = []
    let read = feature.userResult().start { if case let .value(user) = $0 { refreshValues.append(user) } }
    await users.gate.waitFor(1)
    let write = feature.saveResult([.init(.newsletter(.arts), true)], from: user).start()
    defer { read.dispose(); write.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.succeed(0)
    try users.gate.finish(0, .success(user))
    await feature.waitForOperations()
    XCTAssertEqual(refreshValues.count, 1, "Only the synchronous cached prefix is delivered")
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
  }

  func testWrongAccountSnapshotCannotWrite() async throws {
    let fixture = PreferencesFixture()
    var source = try XCTUnwrap(fixture.user)
    source.id += 1
    let subscription = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: source).start()
    defer { subscription.dispose(); fixture.provider.gate.releaseAll() }
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 0)
    XCTAssertEqual(fixture.commits, 0)
  }

  func testWrongAccountSnapshotCannotResetAnExistingQueue() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let first = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: user).start()
    await fixture.provider.gate.waitFor(1)
    var wrong = user
    wrong.id += 1
    let rejected = fixture.feature.saveResult([.init(.newsletter(.weekly), true)], from: wrong).start()
    let next = fixture.feature.saveResult([.init(.notification(.messages), true)], from: user).start()
    defer { first.dispose(); rejected.dispose(); next.dispose() }
    try fixture.provider.succeed(0)
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, true)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.weekly, user.newsletters.weekly)
    try fixture.provider.succeed(1)
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 2)
    XCTAssertEqual(fixture.commits, 2)
  }
}

@MainActor
private final class PreferencesFixture {
  var user: User? = {
    var user = User.template
    user.newsletters.arts = false
    user.notifications.messages = false
    return user
  }()

  var commits = 0
  let provider = ControlledPreferencesProvider()
  lazy var session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) },
    currentUser: { [weak self] in self?.user },
    updateUser: { [weak self] in self?.user = $0; self?.commits += 1 }
  )
  lazy var feature = SettingsFeature(sessionFeature: self.session, makeProvider: { self.provider })
}

@MainActor
private final class ControlledPreferencesProvider: AccountPreferencesProvider {
  let gate = AccountRequestGate<User>()
  var sent: [User] = []
  func save(_ user: User) async throws -> User {
    self.sent.append(user)
    return try await self.gate.request()
  }

  func succeed(_ index: Int) throws {
    guard self.sent.indices.contains(index) else { XCTFail("Missing save"); return }
    try self.gate.finish(index, .success(self.sent[index]))
  }
}

@MainActor
private final class ControlledPreferencesReadProvider: SessionProvider {
  let gate = AccountRequestGate<User>()
  func user() async throws -> User { try await self.gate.request() }
  func graphUser() async throws -> User { throw CancellationError() }
  func clearActivityIndicator() async throws -> Int { throw CancellationError() }
}
