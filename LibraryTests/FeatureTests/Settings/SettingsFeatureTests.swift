@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class SettingsFeatureTests: XCTestCase {
  func testEveryNotificationURLFieldChangesOnlyItsOwnPreference() async throws {
    let parameters = [
      "notify_of_backings", "notify_of_comment_replies", "notify_of_comments",
      "notify_of_creator_digest", "notify_of_creator_edu", "notify_of_follower",
      "notify_of_friend_activity", "notify_of_messages", "notify_mobile_of_backings",
      "notify_mobile_of_comments", "notify_mobile_of_follower", "notify_mobile_of_friend_activity",
      "notify_mobile_of_marketing_update", "notify_mobile_of_messages", "notify_mobile_of_post_likes",
      "notify_mobile_of_updates", "notify_of_post_likes", "notify_of_updates"
    ]
    for parameter in parameters {
      let fixture = PreferencesFixture()
      defer { fixture.provider.gate.releaseAll() }
      for (index, enabled) in [true, false].enumerated() {
        let before = try XCTUnwrap(fixture.user)
        var expected = try XCTUnwrap(before.notifications.encode() as? [String: Bool])
        expected[parameter] = enabled
        let observation = fixture.feature.notificationResult(named: parameter, enabled: enabled).start()
        defer { observation.dispose() }
        await fixture.provider.gate.waitFor(index + 1)
        let sent = try XCTUnwrap(fixture.provider.sent.last)
        XCTAssertEqual(sent.notifications.encode() as? [String: Bool], expected, parameter)
        XCTAssertEqual(sent.newsletters.games, before.newsletters.games, parameter)
        try fixture.provider.succeed(index)
        await fixture.feature.waitForOperations()
        XCTAssertEqual(fixture.user?.notifications.encode() as? [String: Bool], expected, parameter)
      }
    }
  }

  func testNewsletterAndDeepLinkCommandsShareOrderedWrites() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let newsletter = fixture.feature.saveResult([.init(.newsletter(.games), true)], from: user).start()
    let notification = fixture.feature.notificationResult(named: "notify_mobile_of_messages", enabled: true)
      .start()
    let laterNewsletter = fixture.feature.saveResult([.init(.newsletter(.games), false)], from: user).start()
    defer { newsletter.dispose(); notification.dispose(); laterNewsletter.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.succeed(0)
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.games, true)
    XCTAssertEqual(fixture.provider.sent[1].notifications.mobileMessages, true)
    try fixture.provider.succeed(1)
    await fixture.provider.gate.waitFor(3)
    XCTAssertEqual(fixture.provider.sent[2].newsletters.games, false)
    XCTAssertEqual(fixture.provider.sent[2].notifications.mobileMessages, true)
    try fixture.provider.succeed(2)
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.commits, 3)
  }

  func testUnknownNotificationKeepsLegacyNoOpAndSignedOutLinkDoesNotSave() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let original = try XCTUnwrap(fixture.user)
    let observation = fixture.feature.notificationResult(named: "unrecognized", enabled: true).start()
    defer { observation.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.sent[0].notifications, original.notifications)
    try fixture.provider.succeed(0)
    await fixture.feature.waitForOperations()
    fixture.user = nil
    let signedOut = fixture.feature.notificationResult(named: "notify_of_messages", enabled: true).start()
    defer { signedOut.dispose() }
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 1)
  }

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
extension SettingsFeatureTests {
  func testDeferredEmailObservationCannotStartUnderReplacementSession() async {
    let fixture = AccountWritesFixture()
    let producer = fixture.feature.emailUserResult()
    fixture.session.sessionChanged()
    var received = false
    let observation = producer.startWithResult { _ in received = true }
    defer { observation.dispose(); fixture.provider.emails.releaseAll() }
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.emails.count, 0)
    XCTAssertFalse(received)
  }

  func testDisposedAccountFieldsReadCannotPublishLateValue() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.emails.releaseAll() }
    var received = false
    let observation = fixture.feature.accountFieldsResult().startWithResult { _ in received = true }
    await fixture.provider.emails.waitFor(1)
    observation.dispose()
    try fixture.provider.emails.finish(0, .success(.template))
    await fixture.feature.waitForOperations()
    XCTAssertFalse(received)
  }

  func testEmailLookupSharesAndAccountEditRejectsLateResult() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.emails.releaseAll(); fixture.provider.gate.releaseAll() }
    let first = Task { try await fixture.feature.emailUser() }
    let second = Task { try await fixture.feature.emailUser() }
    await fixture.provider.emails.waitFor(1)
    let write = fixture.feature.accountResult(.email(.init(
      email: "new@example.invalid",
      currentPassword: "fixture"
    ))).start()
    defer { write.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success(nil))
    try fixture.provider.emails.finish(0, .success(.template))
    for task in [first, second] {
      do { _ = try await task.value; XCTFail("Stale email appeared") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
    XCTAssertEqual(fixture.provider.emails.count, 1)
  }

  func testEmailVerificationSharesAndDistinctLinksQueueWithoutLoggingIn() async throws {
    let fixture = AccountWritesFixture()
    fixture.user = nil // A deep link carries its own token.
    defer { fixture.provider.verifications.releaseAll() }
    let first = Task { try await fixture.feature.verifyEmail(token: "first-fixture") }
    let duplicate = Task { try await fixture.feature.verifyEmail(token: "first-fixture") }
    await fixture.provider.verifications.waitFor(1)
    let next = Task { try await fixture.feature.verifyEmail(token: "next-fixture") }
    try fixture.provider.verifications.finish(0, .success(.init(message: "Confirmed")))
    let firstResult = try await first.value
    let duplicateResult = try await duplicate.value
    XCTAssertEqual(firstResult.message, "Confirmed")
    XCTAssertEqual(duplicateResult.message, "Confirmed")
    await fixture.provider.verifications.waitFor(2)
    try fixture.provider.verifications.finish(1, .success(.init(message: "Next confirmed")))
    let nextResult = try await next.value
    XCTAssertEqual(nextResult.message, "Next confirmed")
    XCTAssertNil(fixture.user)
    XCTAssertEqual(fixture.commits, 0)
  }

  func testVerificationFailureAllowsRetryAndSessionChangeSuppressesLateSuccess() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.verifications.releaseAll() }
    let first = Task { try await fixture.feature.verifyEmail(token: "fixture") }
    await fixture.provider.verifications.waitFor(1)
    try fixture.provider.verifications.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await first.value; XCTFail("Expected failure") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    let retry = Task { try await fixture.feature.verifyEmail(token: "fixture") }
    await fixture.provider.verifications.waitFor(2)
    fixture.session.sessionChanged()
    try fixture.provider.verifications.finish(1, .success(.init(message: "Confirmed")))
    do { _ = try await retry.value; XCTFail("Old session completion escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
  }

  func testEquivalentAccountWritesShareAndDistinctCommandsRemainOrdered() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let first = fixture.feature.accountResult(.currency("GBP")).start()
    let duplicate = fixture.feature.accountResult(.currency("GBP")).start()
    let next = fixture.feature.accountResult(.currency("EUR")).start()
    defer { first.dispose(); duplicate.dispose(); next.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.commands, [.currency("GBP")])
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    try fixture.provider.gate.finish(1, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "EUR")
    XCTAssertEqual(fixture.commits, 2)
  }

  func testAccountAndPreferenceWritesUseOneQueue() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let source = try XCTUnwrap(fixture.user)
    let currency = fixture.feature.accountResult(.currency("GBP")).start()
    let preference = fixture.feature.saveResult([.init(.newsletter(.arts), true)], from: source).start()
    defer { currency.dispose(); preference.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.preferences.count, 0)
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.preferences.first?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
  }

  func testFailedAccountWriteDoesNotStrandNextCommandAndRetryIsExplicit() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let original = fixture.user?.chosenCurrency
    let failure = fixture.feature.accountResult(.currency("GBP")).start()
    let next = fixture.feature.accountResult(.currency("EUR")).start()
    defer { failure.dispose(); next.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.user?.chosenCurrency, original)
    try fixture.provider.gate.finish(1, .success(nil))
    await fixture.feature.waitForOperations()
    let retry = Task { try await fixture.feature.updateAccount(.currency("GBP")) }
    await fixture.provider.gate.waitFor(3)
    try fixture.provider.gate.finish(2, .success(nil))
    _ = try await retry.value
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.commits, 2)
  }

  func testDisposedObserverDoesNotAbandonAdmittedAccountWrite() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    var delivered = false
    let observation = fixture.feature.accountResult(.currency("GBP"))
      .startWithResult { _ in delivered = true }
    await fixture.provider.gate.waitFor(1)
    observation.dispose()
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    XCTAssertFalse(delivered)
  }

  func testReplacedSessionSuppressesAcceptedWriteAndDoesNotDispatchQueuedWrite() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let first = fixture.feature.accountResult(.currency("GBP")).start()
    let queued = fixture.feature.accountResult(.currency("EUR")).start()
    defer { first.dispose(); queued.dispose() }
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged() // Even re-login as the same account is a new identity.
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.commands.count, 1)
    XCTAssertEqual(fixture.commits, 0)
  }

  func testSignedOutAccountWriteNeverReachesTransport() async {
    let fixture = AccountWritesFixture()
    fixture.user = nil
    do {
      _ = try await fixture.feature.updateAccount(.sendVerification)
      XCTFail("Signed-out command succeeded")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(fixture.provider.commands.count, 0)
  }

  func testFacebookConnectMergesOnlyAccountFieldsIntoLatestUser() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let request = Task { try await fixture.feature.updateAccount(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    var response = try XCTUnwrap(fixture.user)
    response.facebookConnected = true
    response.needsFreshFacebookToken = false
    response.newsletters.arts = false
    fixture.user?.newsletters.arts = true
    try fixture.provider.gate.finish(0, .success(response))
    _ = try await request.value
    XCTAssertEqual(fixture.user?.facebookConnected, true)
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
  }

  func testRefreshWaitsForAccountWriteBeforeFetchingAndCommitting() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll(); fixture.readProvider.gate.releaseAll() }
    let write = fixture.feature.accountResult(.currency("GBP")).start()
    let refresh = fixture.feature.refreshResult().start()
    defer { write.dispose(); refresh.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.readProvider.gate.count, 0)
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.readProvider.gate.waitFor(1)
    var response = try XCTUnwrap(fixture.user)
    response.name = "Fresh account"
    try fixture.readProvider.gate.finish(0, .success(response))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.user?.name, "Fresh account")
  }

  func testRefreshStartedBeforeAccountEditCannotOverwriteConfirmedWrite() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll(); fixture.readProvider.gate.releaseAll() }
    let stale = try XCTUnwrap(fixture.user)
    let refresh = fixture.feature.refreshResult().start()
    await fixture.readProvider.gate.waitFor(1)
    let write = fixture.feature.accountResult(.currency("GBP")).start()
    defer { refresh.dispose(); write.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success(nil))
    try fixture.readProvider.gate.finish(0, .success(stale)) // Transport ignores cancellation.
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.commits, 1)
  }
}

@MainActor
private final class AccountWritesFixture {
  var user: User? = .template
  var commits = 0
  let provider = ControlledAccountWritesProvider()
  let readProvider = ControlledPreferencesReadProvider()
  lazy var session = SessionFeature(
    makeProvider: { self.readProvider },
    currentUser: { [weak self] in self?.user },
    updateUser: { [weak self] in self?.user = $0; self?.commits += 1 }
  )
  lazy var feature = SettingsFeature(sessionFeature: self.session, makeProvider: { self.provider })
}

@MainActor
private final class ControlledAccountWritesProvider: AccountPreferencesProvider {
  func projectNotifications() async throws -> [ProjectNotification] { throw CancellationError() }
  func saveProjectNotification(_: ProjectNotification) async throws -> ProjectNotification { throw CancellationError() }
  let verifications = AccountRequestGate<EmailVerificationResponseEnvelope>()
  let emails = AccountRequestGate<GraphUser>()
  func verifyEmail(token _: String) async throws -> EmailVerificationResponseEnvelope {
    try await self.verifications.request()
  }

  let gate = AccountRequestGate<User?>()
  var commands: [SettingsFeature.AccountChange] = []
  var preferences: [User] = []
  func update(_ change: SettingsFeature.AccountChange) async throws -> User? {
    self.commands.append(change)
    return try await self.gate.request()
  }

  func save(_ user: User) async throws -> User { self.preferences.append(user); return user }
  func emailUser() async throws -> GraphUser { try await self.emails.request() }
}

@MainActor
private final class ControlledPreferencesProvider: AccountPreferencesProvider {
  func projectNotifications() async throws -> [ProjectNotification] { throw CancellationError() }
  func saveProjectNotification(_: ProjectNotification) async throws -> ProjectNotification { throw CancellationError() }
  func verifyEmail(token _: String) async throws
    -> EmailVerificationResponseEnvelope { throw CancellationError() }
  func update(_: SettingsFeature.AccountChange) async throws -> User? { throw CancellationError() }
  func emailUser() async throws -> GraphUser { throw CancellationError() }
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
  func setup() async throws -> GraphUserSetup { throw CancellationError() }
  let gate = AccountRequestGate<User>()
  func user() async throws -> User { try await self.gate.request() }
  func graphUser() async throws -> User { throw CancellationError() }
  func clearActivityIndicator() async throws -> Int { throw CancellationError() }
}
