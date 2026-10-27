@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class AuthenticationFeatureTests: XCTestCase {
  func testOAuthSharedSuccessTracksBeforeSingleSessionCommit() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var loginCountsAtTracking: [Int] = []
    let feature = AuthenticationFeature(
      sessionFeature: fixture.session, makeProvider: { fixture.provider },
      trackOAuthLogin: { loginCountsAtTracking.append(fixture.logins) }
    )
    let first = feature.result(.oauth(code: "fixture", verifier: "fixture")).start()
    let second = feature.result(.oauth(code: "fixture", verifier: "fixture")).start()
    defer { first.dispose(); second.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertTrue(loginCountsAtTracking.isEmpty)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await feature.waitForOperations()
    XCTAssertEqual(loginCountsAtTracking, [0])
    XCTAssertEqual(fixture.logins, 1)
  }

  func testSignupSharesPendingWriteAndPreservesNewsletterIntent() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let credentials = AuthenticationFeature.Credentials.facebookSignup("fixture", sendNewsletters: true)
    var successes = 0
    let first = fixture.feature.result(credentials)
      .startWithResult { if case .success = $0 { successes += 1 } }
    let second = fixture.feature.result(credentials)
      .startWithResult { if case .success = $0 { successes += 1 } }
    defer { first.dispose(); second.dispose() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.credentials, [credentials])
    XCTAssertEqual(fixture.logins, 0)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(successes, 2)
    XCTAssertEqual(fixture.logins, 1)
  }

  func testAppleAndOAuthResultsCannotCommitAfterReplacementOrSessionChange() async throws {
    for credentials in [
      AuthenticationFeature.Credentials.apple(
        appID: "fixture",
        firstName: nil,
        lastName: nil,
        token: "fixture"
      ),
      .oauth(code: "fixture", verifier: "fixture")
    ] {
      let fixture = AuthenticationFixture()
      defer { fixture.provider.gate.releaseAll() }
      var oldSuccesses = 0
      let old = fixture.feature.result(credentials)
        .startWithResult { if case .success = $0 { oldSuccesses += 1 } }
      await fixture.provider.gate.waitFor(1)
      let newer = fixture.feature.result(.facebook("new-token")).start()
      defer { old.dispose(); newer.dispose() }
      await fixture.provider.gate.waitFor(2)
      fixture.session.sessionChanged()
      try fixture.provider.gate.finish(0, .success(fixture.envelope))
      try fixture.provider.gate.finish(1, .success(fixture.envelope))
      await fixture.feature.waitForOperations()
      XCTAssertEqual(oldSuccesses, 0)
      XCTAssertEqual(fixture.logins, 0)
      XCTAssertNil(fixture.user)
    }
  }

  func testDisposedSocialSignupDoesNotCommitLateServerSuccess() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let pending = fixture.feature.result(.facebookSignup("fixture", sendNewsletters: false)).start()
    await fixture.provider.gate.waitFor(1)
    pending.dispose()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertEqual(fixture.provider.gate.count, 1, "No automatic retry of account creation")
  }

  func testAppleUserFailureCannotPersistPartialTokenAndExplicitRetryUsesMatchingPair() async throws {
    let fixture = AuthenticationFixture()
    let failure = ErrorEnvelope(errorMessages: ["User failed"], ksrCode: nil, httpCode: 503, exception: nil)
    var service = MockService(
      fetchUserResult: .failure(failure), signInWithAppleResult: .success(.template)
    )
    let feature = AuthenticationFeature(sessionFeature: fixture.session, makeProvider: {
      AsyncAuthenticationProvider(service: service)
    })
    let credentials = AuthenticationFeature.Credentials.apple(
      appID: "fixture", firstName: "First", lastName: "Last", token: "fixture"
    )
    do { _ = try await feature.authenticate(credentials); XCTFail("Partial Apple login committed") }
    catch let error as ErrorEnvelope { XCTAssertEqual(error.errorMessages, failure.errorMessages) }
    XCTAssertNil(fixture.user)
    XCTAssertEqual(fixture.logins, 0)
    service = MockService(fetchUserResult: .success(.template), signInWithAppleResult: .success(.template))
    let result = try await feature.authenticate(credentials)
    XCTAssertEqual(result.accessToken, SignInWithAppleEnvelope.template.signInWithApple.apiAccessToken)
    XCTAssertEqual(result.user.id, User.template.id)
    XCTAssertEqual(fixture.logins, 1)
  }

  func testMalformedAppleUserIDFailsWithoutSessionCommit() async {
    let fixture = AuthenticationFixture()
    var envelope = SignInWithAppleEnvelope.template
    envelope.signInWithApple.user.uid = "not-an-id"
    let feature = AuthenticationFeature(sessionFeature: fixture.session, makeProvider: {
      AsyncAuthenticationProvider(service: MockService(
        fetchUserResult: .success(.template), signInWithAppleResult: .success(envelope)
      ))
    })
    do {
      _ = try await feature.authenticate(.apple(
        appID: "fixture",
        firstName: nil,
        lastName: nil,
        token: "fixture"
      ))
      XCTFail("Malformed user ID accepted")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
    XCTAssertEqual(fixture.logins, 0)
  }

  func testOAuthUserFailureLeavesSessionIntactAndRetryCommitsMatchingToken() async throws {
    let fixture = AuthenticationFixture()
    fixture.user = .template
    let failure = ErrorEnvelope(errorMessages: ["User failed"], ksrCode: nil, httpCode: 503, exception: nil)
    var service = MockService(fetchUserSelfError: failure, tokenExchangeResponse: .init(token: "first-token"))
    let feature = AuthenticationFeature(sessionFeature: fixture.session, makeProvider: {
      AsyncAuthenticationProvider(service: service)
    })
    do { _ = try await feature.authenticate(.oauth(
      code: "code",
      verifier: "verifier"
    )); XCTFail("Partial login") } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.errorMessages, failure.errorMessages)
    }
    XCTAssertEqual(fixture.user?.id, User.template.id)
    XCTAssertEqual(fixture.logins, 0)
    service = MockService(
      fetchUserSelfResponse: .template,
      tokenExchangeResponse: .init(token: "second-token")
    )
    let result = try await feature.authenticate(.oauth(code: "new-code", verifier: "verifier"))
    XCTAssertEqual(result.accessToken, "second-token")
    XCTAssertEqual(result.user.id, User.template.id)
    XCTAssertEqual(fixture.logins, 1)
  }

  func testPasswordResetSharesSendAndDisposedWaiterCannotCancelAnother() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll() }
    var successes = 0
    let first = fixture.feature.passwordResetResult(email: "person@example.invalid")
      .startWithResult { if case .success = $0 { successes += 1 } }
    let second = fixture.feature.passwordResetResult(email: "person@example.invalid")
      .startWithResult { if case .success = $0 { successes += 1 } }
    defer { second.dispose() }
    await fixture.provider.resetGate.waitFor(1)
    first.dispose()
    try fixture.provider.resetGate.finish(0, .success(()))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(fixture.provider.resetEmails, ["person@example.invalid"])
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.user)
  }

  func testPasswordResetReplacesOldEmailAndSuppressesLateFailure() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll() }
    var errors = 0
    var successes = 0
    let old = fixture.feature.passwordResetResult(email: "old@example.invalid")
      .startWithFailed { _ in errors += 1 }
    await fixture.provider.resetGate.waitFor(1)
    let new = fixture.feature.passwordResetResult(email: "new@example.invalid")
      .startWithResult { if case .success = $0 { successes += 1 } }
    defer { old.dispose(); new.dispose() }
    await fixture.provider.resetGate.waitFor(2)
    try fixture.provider.resetGate.finish(1, .success(()))
    try fixture.provider.resetGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(errors, 0)
    XCTAssertEqual(fixture.logins, 0)
  }

  func testPasswordResetFailureThenExplicitRetryDoesNotSupersedeLogin() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll(); fixture.provider.gate.releaseAll() }
    var errors = 0
    var successes = 0
    let login = Task { try await fixture.feature.authenticate(.facebook("fixture")) }
    await fixture.provider.gate.waitFor(1)
    let failed = fixture.feature.passwordResetResult(email: "person@example.invalid")
      .startWithFailed { _ in errors += 1 }
    defer { failed.dispose() }
    await fixture.provider.resetGate.waitFor(1)
    try fixture.provider.resetGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(fixture.logins, 0)
    let retry = fixture.feature.passwordResetResult(email: "person@example.invalid")
      .startWithResult { if case .success = $0 { successes += 1 } }
    defer { retry.dispose() }
    await fixture.provider.resetGate.waitFor(2)
    try fixture.provider.resetGate.finish(1, .success(()))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(fixture.logins, 0)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    _ = try await login.value
    XCTAssertEqual(fixture.logins, 1)
  }

  func testCancelledPasswordResetCallerCannotReportSuccess() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll() }
    let request = Task { try await fixture.feature.resetPassword(email: "person@example.invalid") }
    await fixture.provider.resetGate.waitFor(1)
    request.cancel()
    try fixture.provider.resetGate.finish(0, .success(()))
    do { try await request.value; XCTFail("Cancelled caller reported success") }
    catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.logins, 0)
  }

  func testEquivalentAttemptsShareAndDisposedCallerCannotCancelAnotherLogin() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var outcomes = 0
    let first = fixture.feature.result(.email("person@example.invalid", password: "fixture"))
      .startWithResult { if case .success = $0 { outcomes += 1 } }
    await fixture.provider.gate.waitFor(1)
    let second = fixture.feature.result(.email("person@example.invalid", password: "fixture"))
      .startWithResult { if case .success = $0 { outcomes += 1 } }
    defer { second.dispose() }
    first.dispose()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.gate.count, 1)
    XCTAssertEqual(outcomes, 1)
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertEqual(fixture.user?.id, fixture.envelope.user.id)
  }

  func testChangedCodeReplacesOldAttemptEvenIfOldTransportIgnoresCancellation() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var outcomes = 0
    let old = fixture.feature.result(.facebook("fixture-token"), code: "111111")
      .startWithResult { if case .success = $0 { outcomes += 1 } }
    await fixture.provider.gate.waitFor(1)
    let new = fixture.feature.result(.facebook("fixture-token"), code: "222222")
      .startWithResult { if case .success = $0 { outcomes += 1 } }
    defer { old.dispose(); new.dispose() }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.codes, ["111111", "222222"])
    XCTAssertEqual(outcomes, 1)
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testExternalSessionChangeSuppressesOldSuccessEvenForSameUserID() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    fixture.user = .template
    var outcomes = 0
    let pending = fixture.feature.result(.facebook("fixture-token"))
      .startWithResult { if case .success = $0 { outcomes += 1 } }
    defer { pending.dispose() }
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(outcomes, 0)
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testDisposedOnlyObserverDoesNotEstablishSession() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let pending = fixture.feature.result(.facebook("fixture-token")).start()
    await fixture.provider.gate.waitFor(1)
    pending.dispose()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.user)
  }

  func testCancelledAsyncCallerCannotCommitAndLaterRetrySucceeds() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let pending = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    pending.cancel()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    do { _ = try await pending.value; XCTFail("Cancelled login succeeded") }
    catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.logins, 0)
    let retry = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    _ = try await retry.value
    XCTAssertEqual(fixture.logins, 1)
  }

  func testFailurePreservesSessionAndRetryCommitsExactlyOnceForSharedCallers() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var failures = 0
    let first = fixture.feature.result(.facebook("fixture-token"))
      .startWithFailed { _ in failures += 1 }
    defer { first.dispose() }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(failures, 1)
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNotNil(fixture.feature.lastError)
    var successes = 0
    let second = fixture.feature.result(.facebook("fixture-token"))
      .startWithResult { if case .success = $0 { successes += 1 } }
    let duplicate = fixture.feature.result(.facebook("fixture-token"))
      .startWithResult { if case .success = $0 { successes += 1 } }
    defer { second.dispose(); duplicate.dispose() }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(successes, 2)
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testResendNeverCommitsUnexpectedSuccessAndRemainsDistinctFromLogin() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let resend = Task { try await fixture.feature.resendCode(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    try await resend.value
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.user)
    XCTAssertNil(fixture.provider.codes[0])
  }

  func testObsoleteFailureCannotOverwriteNewSuccessfulAttempt() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var errors = 0
    let old = fixture.feature.result(.email("old@example.invalid", password: "fixture"))
      .startWithFailed { _ in errors += 1 }
    await fixture.provider.gate.waitFor(1)
    let new = fixture.feature.result(.email("new@example.invalid", password: "fixture")).start()
    defer { old.dispose(); new.dispose() }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertEqual(errors, 0)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testPublicDemoCannotAuthenticateSignupOrSendPasswordReset() async {
    let provider = AsyncAuthenticationProvider(service: MockService.publicDemo())
    for credentials in [
      AuthenticationFeature.Credentials.email("person@example.invalid", password: "fixture"),
      .facebook("fixture-token"),
      .facebookSignup("fixture", sendNewsletters: true),
      .apple(appID: "fixture", firstName: nil, lastName: nil, token: "fixture"),
      .oauth(code: "fixture", verifier: "fixture")
    ] {
      do { _ = try await provider.login(credentials, code: nil); XCTFail("Demo authenticated") }
      catch { XCTAssertTrue(error is ErrorEnvelope) }
    }
    do { try await provider.resetPassword(email: "person@example.invalid"); XCTFail("Demo sent reset") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  func testResendDoesNotCancelPendingVerification() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    var successes = 0
    var resendErrors: [ErrorEnvelope.KsrCode?] = []
    let resendFinished = expectation(description: "Resend publishes independently")
    let login = fixture.feature.result(.facebook("fixture-token"), code: "123456")
      .startWithResult { if case .success = $0 { successes += 1 } }
    await fixture.provider.gate.waitFor(1)
    let resend = fixture.feature.result(.facebook("fixture-token"), resend: true)
      .startWithFailed {
        resendErrors.append($0.ksrCode)
        resendFinished.fulfill()
      }
    defer { login.dispose(); resend.dispose() }
    await fixture.provider.gate.waitFor(2)
    let challenge = ErrorEnvelope(
      errorMessages: ["Verification required"], ksrCode: .TfaRequired, httpCode: 403, exception: nil
    )
    try fixture.provider.gate.finish(1, .failure(challenge))
    // Let resend publish before completing the independently pending login.
    await fulfillment(of: [resendFinished], timeout: 2)
    XCTAssertEqual(resendErrors, [.TfaRequired])
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    await fixture.feature.waitForOperations()
    XCTAssertEqual(fixture.provider.codes, ["123456", nil])
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(fixture.logins, 1)
  }
}

@MainActor
private final class AuthenticationFixture {
  let provider = ControlledAuthenticationProvider()
  var user: User?
  var logins = 0
  let envelope = AccessTokenEnvelope(accessToken: "fixture-token", user: .template)
  lazy var session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) },
    currentUser: { [weak self] in self?.user },
    updateUser: { [weak self] in self?.user = $0 },
    login: { [weak self] in self?.user = $0.user; self?.logins += 1 }
  )
  lazy var feature = AuthenticationFeature(
    sessionFeature: self.session,
    makeProvider: { [provider] in provider }
  )
}

@MainActor
private final class ControlledAuthenticationProvider: AuthenticationProvider {
  let gate = AccountRequestGate<AccessTokenEnvelope>()
  let resetGate = AccountRequestGate<Void>()
  private(set) var resetEmails: [String] = []
  private(set) var credentials: [AuthenticationFeature.Credentials] = []
  private(set) var codes: [String?] = []
  func resetPassword(email: String) async throws {
    self.resetEmails.append(email)
    try await self.resetGate.request()
  }

  func login(
    _ credentials: AuthenticationFeature.Credentials, code: String?
  ) async throws -> AccessTokenEnvelope {
    self.credentials.append(credentials)
    self.codes.append(code)
    return try await self.gate.request()
  }
}
