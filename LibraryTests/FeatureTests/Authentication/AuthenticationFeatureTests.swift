@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class AuthenticationFeatureTests: XCTestCase {
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

  func testPublicDemoCannotAuthenticateUsingEitherCredentialKind() async {
    let provider = AsyncAuthenticationProvider(service: MockService.publicDemo())
    for credentials in [
      AuthenticationFeature.Credentials.email("person@example.invalid", password: "fixture"),
      .facebook("fixture-token")
    ] {
      do { _ = try await provider.login(credentials, code: nil); XCTFail("Demo authenticated") }
      catch { XCTAssertTrue(error is ErrorEnvelope) }
    }
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
  private(set) var codes: [String?] = []
  func login(
    _: AuthenticationFeature.Credentials, code: String?
  ) async throws -> AccessTokenEnvelope {
    self.codes.append(code)
    return try await self.gate.request()
  }
}
