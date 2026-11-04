@testable import Kickstarter_iOS
@testable import KsApi

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
    let first = Task { try await feature.authenticate(.oauth(code: "fixture", verifier: "fixture")) }
    let second = Task { try await feature.authenticate(.oauth(code: "fixture", verifier: "fixture")) }
    defer { first.cancel(); second.cancel() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertTrue(loginCountsAtTracking.isEmpty)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    _ = try await first.value
    _ = try await second.value
    XCTAssertEqual(loginCountsAtTracking, [0])
    XCTAssertEqual(fixture.logins, 1)
  }

  func testSignupSharesPendingWriteAndPreservesNewsletterIntent() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let credentials = AuthenticationFeature.Credentials.facebookSignup("fixture", sendNewsletters: true)
    let first = Task { try await fixture.feature.authenticate(credentials) }
    let second = Task { try await fixture.feature.authenticate(credentials) }
    defer { first.cancel(); second.cancel() }
    await fixture.provider.gate.waitFor(1)
    XCTAssertEqual(fixture.provider.credentials, [credentials])
    XCTAssertEqual(fixture.logins, 0)
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    _ = try await first.value
    _ = try await second.value
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
      let old = Task { try await fixture.feature.authenticate(credentials) }
      await fixture.provider.gate.waitFor(1)
      let newer = Task { try await fixture.feature.authenticate(.facebook("new-token")) }
      defer { old.cancel(); newer.cancel() }
      await fixture.provider.gate.waitFor(2)
      fixture.session.sessionChanged()
      try fixture.provider.gate.finish(0, .success(fixture.envelope))
      try fixture.provider.gate.finish(1, .success(fixture.envelope))
      do { _ = try await old.value; XCTFail("Obsolete attempt succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
      do { _ = try await newer.value; XCTFail("Changed-session attempt succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
      XCTAssertEqual(fixture.logins, 0)
      XCTAssertNil(fixture.user)
    }
  }

  func testDisposedSocialSignupDoesNotCommitLateServerSuccess() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let pending = Task { try await fixture.feature.authenticate(.facebookSignup("fixture", sendNewsletters: false)) }
    await fixture.provider.gate.waitFor(1)
    pending.cancel()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    do { _ = try await pending.value; XCTFail("Cancelled signup succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
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

  func testPasswordResetSharesSendAndCancelledWaiterCannotCancelAnother() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll() }
    let first = Task { try await fixture.feature.resetPassword(email: "person@example.invalid") }
    await fixture.provider.resetGate.waitFor(1)
    let second = Task { try await fixture.feature.resetPassword(email: "person@example.invalid") }
    await Task.yield()
    first.cancel()
    try fixture.provider.resetGate.finish(0, .success(()))
    do { try await first.value; XCTFail("Cancelled waiter should not succeed") }
    catch is CancellationError { }
    try await second.value
    XCTAssertEqual(fixture.provider.resetEmails, ["person@example.invalid"])
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.user)
  }

  func testPasswordResetReplacesOldEmailAndSuppressesLateFailure() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll() }
    let old = Task { try await fixture.feature.resetPassword(email: "old@example.invalid") }
    await fixture.provider.resetGate.waitFor(1)
    let new = Task { try await fixture.feature.resetPassword(email: "new@example.invalid") }
    await fixture.provider.resetGate.waitFor(2)
    try fixture.provider.resetGate.finish(1, .success(()))
    try fixture.provider.resetGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try await new.value
    do { try await old.value; XCTFail("Obsolete request should not succeed") }
    catch is CancellationError { }
    XCTAssertEqual(fixture.logins, 0)
  }

  func testPasswordResetFailureThenExplicitRetryDoesNotSupersedeLogin() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.resetGate.releaseAll(); fixture.provider.gate.releaseAll() }
    let login = Task { try await fixture.feature.authenticate(.facebook("fixture")) }
    await fixture.provider.gate.waitFor(1)
    let failed = Task { try await fixture.feature.resetPassword(email: "person@example.invalid") }
    await fixture.provider.resetGate.waitFor(1)
    try fixture.provider.resetGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { try await failed.value; XCTFail("Expected failure") } catch { }
    XCTAssertEqual(fixture.logins, 0)
    let retry = Task { try await fixture.feature.resetPassword(email: "person@example.invalid") }
    await fixture.provider.resetGate.waitFor(2)
    try fixture.provider.resetGate.finish(1, .success(()))
    try await retry.value
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

  func testEquivalentAttemptsShareAndCancelledCallerCannotCancelAnotherLogin() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let credentials = AuthenticationFeature.Credentials.email("person@example.invalid", password: "fixture")
    let first = Task { try await fixture.feature.authenticate(credentials) }
    await fixture.provider.gate.waitFor(1)
    let second = Task { try await fixture.feature.authenticate(credentials) }
    await Task.yield()
    first.cancel()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    do { _ = try await first.value; XCTFail("Cancelled caller succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
    _ = try await second.value
    XCTAssertEqual(fixture.provider.gate.count, 1)
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertEqual(fixture.user?.id, fixture.envelope.user.id)
  }

  func testChangedCodeReplacesOldAttemptEvenIfOldTransportIgnoresCancellation() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let old = Task { try await fixture.feature.authenticate(.facebook("fixture-token"), code: "111111") }
    await fixture.provider.gate.waitFor(1)
    let new = Task { try await fixture.feature.authenticate(.facebook("fixture-token"), code: "222222") }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    _ = try await new.value
    do { _ = try await old.value; XCTFail("Obsolete code succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.provider.codes, ["111111", "222222"])
    XCTAssertEqual(fixture.logins, 1)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testExternalSessionChangeSuppressesOldSuccessEvenForSameUserID() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    fixture.user = .template
    let pending = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    fixture.session.sessionChanged()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    do { _ = try await pending.value; XCTFail("Old session succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNil(fixture.feature.lastError)
  }

  func testCancelledOnlyCallerDoesNotEstablishSession() async throws {
    let fixture = AuthenticationFixture()
    defer { fixture.provider.gate.releaseAll() }
    let pending = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    pending.cancel()
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    do { _ = try await pending.value; XCTFail("Cancelled caller succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
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
    let first = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await first.value; XCTFail("Failed request succeeded") } catch is ErrorEnvelope {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertNotNil(fixture.feature.lastError)
    let second = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    let duplicate = Task { try await fixture.feature.authenticate(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    _ = try await second.value
    _ = try await duplicate.value
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
    let old = Task { try await fixture.feature.authenticate(.email("old@example.invalid", password: "fixture")) }
    await fixture.provider.gate.waitFor(1)
    let new = Task { try await fixture.feature.authenticate(.email("new@example.invalid", password: "fixture")) }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(fixture.envelope))
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    _ = try await new.value
    do { _ = try await old.value; XCTFail("Obsolete request succeeded") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(fixture.logins, 1)
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
    let login = Task { try await fixture.feature.authenticate(.facebook("fixture-token"), code: "123456") }
    await fixture.provider.gate.waitFor(1)
    let resend = Task { try await fixture.feature.resendCode(.facebook("fixture-token")) }
    await fixture.provider.gate.waitFor(2)
    let challenge = ErrorEnvelope(errorMessages: ["Verification required"], ksrCode: .TfaRequired, httpCode: 403, exception: nil)
    try fixture.provider.gate.finish(1, .failure(challenge))
    do { try await resend.value; XCTFail("Expected challenge") } catch let error as ErrorEnvelope {
      XCTAssertEqual(error.ksrCode, .TfaRequired)
    }
    try fixture.provider.gate.finish(0, .success(fixture.envelope))
    _ = try await login.value
    XCTAssertEqual(fixture.provider.codes, ["123456", nil])
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
