@testable import Kickstarter_iOS
@testable import KsApi

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
        let request = try XCTUnwrap(fixture.feature.requestNotification(named: parameter, enabled: enabled))
        await fixture.provider.gate.waitFor(index + 1)
        let sent = try XCTUnwrap(fixture.provider.sent.last)
        XCTAssertEqual(sent.notifications.encode() as? [String: Bool], expected, parameter)
        XCTAssertEqual(sent.newsletters.games, before.newsletters.games, parameter)
        try fixture.provider.succeed(index)
        _ = try await request.value
        XCTAssertEqual(fixture.user?.notifications.encode() as? [String: Bool], expected, parameter)
      }
    }
  }

  func testNewsletterAndDeepLinkCommandsShareOrderedWrites() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let newsletter = fixture.feature.requestPreferences([.init(.newsletter(.games), true)], from: user)
    let notification = try XCTUnwrap(fixture.feature.requestNotification(named: "notify_mobile_of_messages", enabled: true))
    let laterNewsletter = fixture.feature.requestPreferences([.init(.newsletter(.games), false)], from: user)
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
    _ = try await newsletter.value
    _ = try await notification.value
    _ = try await laterNewsletter.value
    XCTAssertEqual(fixture.commits, 3)
  }

  func testUnknownNotificationKeepsLegacyNoOpAndSignedOutLinkDoesNotSave() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let original = try XCTUnwrap(fixture.user)
    let request = try XCTUnwrap(fixture.feature.requestNotification(named: "unrecognized", enabled: true))
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.sent[0].notifications, original.notifications)
    try fixture.provider.succeed(0)
    _ = try await request.value
    fixture.user = nil
    let signedOut = fixture.feature.requestNotification(named: "notify_of_messages", enabled: true)
    XCTAssertNil(signedOut)
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.sent.count, 1)
  }

  func testSignedOutCommandDoesNotReachProvider() async throws {
    let fixture = PreferencesFixture()
    fixture.user = nil
    defer { fixture.provider.gate.releaseAll() }
    let request = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: .template)
    do { _ = try await request.value; XCTFail("Signed-out write must fail") }
    catch { XCTAssertTrue(error is CancellationError) }
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
    let first = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: original)
    let second = fixture.feature.requestPreferences([.init(.notification(.messages), true)], from: original)
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.sent.count, 1)
    try fixture.provider.succeed(0)
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, true)
    XCTAssertEqual(fixture.provider.sent[1].notifications.messages, true)
    try fixture.provider.succeed(1)
    _ = try await first.value
    _ = try await second.value
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.notifications.messages, true)
    XCTAssertEqual(fixture.commits, 2)
  }

  func testEquivalentTailSharesButOnOffOnRemainsOrdered() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let changes: [SettingsFeature.Change] = [.init(.newsletter(.arts), true)]
    let a = fixture.feature.requestPreferences(changes, from: user)
    let duplicate = fixture.feature.requestPreferences(changes, from: user)
    let b = fixture.feature.requestPreferences([.init(.newsletter(.arts), false)], from: user)
    let c = fixture.feature.requestPreferences(changes, from: user)
    for index in 0..<3 {
      await fixture.provider.gate.waitFor(index + 1)
      XCTAssertEqual(fixture.provider.sent[index].newsletters.arts, index != 1)
      try fixture.provider.succeed(index)
    }
    _ = try await a.value
    _ = try await duplicate.value
    _ = try await b.value
    _ = try await c.value
    XCTAssertEqual(fixture.provider.sent.count, 3)
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
  }

  func testFailureDoesNotPoisonNextWriteAndRetryIsPossible() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let a = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    let b = fixture.feature.requestPreferences([.init(.notification(.messages), true)], from: user)
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, user.newsletters.arts)
    do { _ = try await a.value; XCTFail("The failed write must report an error") } catch {}
    XCTAssertNotNil(fixture.feature.lastError)
    try fixture.provider.succeed(1)
    _ = try await b.value
    let retry = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    await fixture.provider.gate.waitFor(3)
    try fixture.provider.succeed(2)
    _ = try await retry.value
    XCTAssertNil(fixture.feature.lastError)
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.notifications.messages, true)
  }

  func testCanceledPresentationDoesNotAbandonAdmittedWrite() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let request = fixture.feature.requestPreferences(
      [.init(.privacy(.following), false)], from: try XCTUnwrap(fixture.user)
    )
    let waiter = Task {
      let user = try await request.value
      try Task.checkCancellation()
      return user
    }
    await fixture.provider.gate.waitFor(1)
    waiter.cancel()
    try fixture.provider.succeed(0)
    do { _ = try await waiter.value; XCTFail("Canceled waiter must not receive the result") }
    catch { XCTAssertTrue(error is CancellationError) }
    _ = try await request.value
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
    let a = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    let b = fixture.feature.requestPreferences([.init(.notification(.messages), true)], from: user)
    await fixture.provider.gate.waitFor(1)
    fixture.user = nil
    fixture.session.sessionChanged()
    try fixture.provider.succeed(0)
    do { _ = try await a.value; XCTFail("Old write must not return a user") }
    catch { XCTAssertTrue(error is CancellationError) }
    do { _ = try await b.value; XCTFail("Queued old write must not return a user") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(fixture.provider.sent.count, 1)
    XCTAssertEqual(fixture.commits, 0)
    XCTAssertNil(fixture.user)
  }

  func testSameAccountNewSessionRejectsOldErrorAndCanSaveIndependently() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let old = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged()
    let new = fixture.feature.requestPreferences([.init(.notification(.messages), true)], from: user)
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.succeed(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    _ = try await new.value
    do { _ = try await old.value; XCTFail("Old-session error must not be delivered") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(fixture.commits, 1)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testAllNewslettersCommandPreservesOtherPreferences() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let request = fixture.feature.requestPreferences(SettingsFeature.Change.allNewsletters(true), from: user)
    await fixture.provider.gate.waitFor(1)
    let sent = try XCTUnwrap(fixture.provider.sent.first)
    for newsletter in Newsletter.allCases {
      XCTAssertEqual(sent[keyPath: UserAttribute.newsletter(newsletter).keyPath], true)
    }
    XCTAssertEqual(sent.notifications.messages, user.notifications.messages)
    XCTAssertEqual(sent.social, user.social)
    try fixture.provider.succeed(0)
    _ = try await request.value
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
    let read = Task { try await feature.refresh() }
    await users.gate.waitFor(1)
    let write = feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    defer { read.cancel() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.succeed(0)
    try users.gate.finish(0, .success(user))
    do {
      _ = try await read.value
      XCTFail("A stale refresh must not return after a preference write")
    } catch is CancellationError {
      // Expected.
    }
    _ = try await write.value
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
  }

  func testWrongAccountSnapshotCannotWrite() async throws {
    let fixture = PreferencesFixture()
    var source = try XCTUnwrap(fixture.user)
    source.id += 1
    defer { fixture.provider.gate.releaseAll() }
    let request = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: source)
    do { _ = try await request.value; XCTFail("Wrong-account write must fail") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(fixture.provider.sent.count, 0)
    XCTAssertEqual(fixture.commits, 0)
  }

  func testWrongAccountSnapshotCannotResetAnExistingQueue() async throws {
    let fixture = PreferencesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let user = try XCTUnwrap(fixture.user)
    let first = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: user)
    await fixture.provider.gate.waitFor(1)
    var wrong = user
    wrong.id += 1
    let rejected = fixture.feature.requestPreferences([.init(.newsletter(.weekly), true)], from: wrong)
    let next = fixture.feature.requestPreferences([.init(.notification(.messages), true)], from: user)
    try fixture.provider.succeed(0)
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.arts, true)
    XCTAssertEqual(fixture.provider.sent[1].newsletters.weekly, user.newsletters.weekly)
    try fixture.provider.succeed(1)
    _ = try await first.value
    _ = try await next.value
    do { _ = try await rejected.value; XCTFail("Wrong-account write must fail") }
    catch { XCTAssertTrue(error is CancellationError) }
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
  func testEmailLookupRejectsResultAfterSessionReplacement() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.emails.releaseAll() }
    let read = Task { try await fixture.feature.emailUser() }
    await fixture.provider.emails.waitFor(1)
    fixture.session.sessionChanged()
    try fixture.provider.emails.finish(0, .success(.template))
    do {
      _ = try await read.value
      XCTFail("A result from a replaced session must not be returned")
    } catch is CancellationError {
      // Expected.
    }
  }

  func testDisposedAccountFieldsReadCannotPublishLateValue() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.emails.releaseAll() }
    let read = Task { try await fixture.feature.accountFields(sleep: { _ in }) }
    await fixture.provider.emails.waitFor(1)
    read.cancel()
    try fixture.provider.emails.finish(0, .success(.template))
    do {
      _ = try await read.value
      XCTFail("A cancelled read must not publish its late value")
    } catch is CancellationError {
      // Expected.
    }
  }

  func testEmailLookupSharesAndAccountEditRejectsLateResult() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.emails.releaseAll(); fixture.provider.gate.releaseAll() }
    let first = Task { try await fixture.feature.emailUser() }
    let second = Task { try await fixture.feature.emailUser() }
    await fixture.provider.emails.waitFor(1)
    _ = try fixture.feature.requestAccount(.email(.init(
      email: "new@example.invalid",
      currentPassword: "fixture"
    )))
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
    let first = try fixture.feature.requestAccount(.currency("GBP"))
    let duplicate = try fixture.feature.requestAccount(.currency("GBP"))
    let next = try fixture.feature.requestAccount(.currency("EUR"))
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.commands, [.currency("GBP")])
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    try fixture.provider.gate.finish(1, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "EUR")
    XCTAssertEqual(fixture.commits, 2)
    let firstUser = try await first.value
    let duplicateUser = try await duplicate.value
    let nextUser = try await next.value
    XCTAssertEqual(firstUser.chosenCurrency, "GBP")
    XCTAssertEqual(duplicateUser.chosenCurrency, "GBP")
    XCTAssertEqual(nextUser.chosenCurrency, "EUR")
  }

  func testAccountAndPreferenceWritesUseOneQueue() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let source = try XCTUnwrap(fixture.user)
    _ = try fixture.feature.requestAccount(.currency("GBP"))
    let preference = fixture.feature.requestPreferences([.init(.newsletter(.arts), true)], from: source)
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.preferences.count, 0)
    try fixture.provider.gate.finish(0, .success(nil))
    _ = try await preference.value
    XCTAssertEqual(fixture.provider.preferences.first?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.user?.newsletters.arts, true)
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
  }

  func testFailedAccountWriteDoesNotStrandNextCommandAndRetryIsExplicit() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let original = fixture.user?.chosenCurrency
    let failure = try fixture.feature.requestAccount(.currency("GBP"))
    let next = try fixture.feature.requestAccount(.currency("EUR"))
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(fixture.user?.chosenCurrency, original)
    try fixture.provider.gate.finish(1, .success(nil))
    await fixture.feature.waitForOperations()
    do { _ = try await failure.value; XCTFail("Expected account write failure") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    let nextUser = try await next.value
    XCTAssertEqual(nextUser.chosenCurrency, "EUR")
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
    let admitted = try fixture.feature.requestAccount(.currency("GBP"))
    let waiter = Task { _ = try await admitted.value; try Task.checkCancellation() }
    await fixture.provider.gate.waitFor(1)
    waiter.cancel()
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    do { _ = try await waiter.value; XCTFail("Cancelled waiter returned a value") }
    catch { XCTAssertTrue(error is CancellationError) }
  }

  func testReplacedSessionSuppressesAcceptedWriteAndDoesNotDispatchQueuedWrite() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll() }
    let first = try fixture.feature.requestAccount(.currency("GBP"))
    let queued = try fixture.feature.requestAccount(.currency("EUR"))
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged() // Even re-login as the same account is a new identity.
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.commands.count, 1)
    XCTAssertEqual(fixture.commits, 0)
    for task in [first, queued] {
      do { _ = try await task.value; XCTFail("Stale account write completed") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
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
    _ = try fixture.feature.requestAccount(.currency("GBP"))
    let refresh = fixture.feature.requestRefresh()
    defer { refresh.cancel() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.readProvider.gate.count, 0)
    try fixture.provider.gate.finish(0, .success(nil))
    await fixture.readProvider.gate.waitFor(1)
    var response = try XCTUnwrap(fixture.user)
    response.name = "Fresh account"
    try fixture.readProvider.gate.finish(0, .success(response))
    _ = try await refresh.value
    XCTAssertEqual(fixture.user?.chosenCurrency, "GBP")
    XCTAssertEqual(fixture.user?.name, "Fresh account")
  }

  func testRefreshStartedBeforeAccountEditCannotOverwriteConfirmedWrite() async throws {
    let fixture = AccountWritesFixture()
    defer { fixture.provider.gate.releaseAll(); fixture.readProvider.gate.releaseAll() }
    let stale = try XCTUnwrap(fixture.user)
    let refresh = fixture.feature.requestRefresh()
    await fixture.readProvider.gate.waitFor(1)
    _ = try fixture.feature.requestAccount(.currency("GBP"))
    defer { refresh.cancel() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success(nil))
    try fixture.readProvider.gate.finish(0, .success(stale)) // Transport ignores cancellation.
    do { _ = try await refresh.value; XCTFail("Stale refresh must not return") }
    catch { XCTAssertTrue(error is CancellationError) }
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
