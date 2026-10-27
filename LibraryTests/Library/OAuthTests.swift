import AuthenticationServices
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
final class OAuthTests: XCTestCase {
  func testCancelSuppressesLateRedirectAndSessionCommit() async throws {
    let fixture = OAuthFixture()
    defer { fixture.provider.gate.releaseAll() }
    let oauth = OAuth(authenticationFeature: fixture.feature)
    var completions = 0
    let pending = oauth.receiveRedirect(
      redirectURL: URL(string: "ksrauth2://authenticate?code=fixture"), error: nil, verifier: "fixture"
    ) { _ in completions += 1 }
    await fixture.provider.gate.waitFor(1)
    oauth.cancel()
    try fixture.provider.gate.finish(0, .success(.init(accessToken: "fixture", user: .template)))
    await pending.value
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertEqual(completions, 0)
  }

  func testReleasingOAuthAdapterCancelsPendingLoginWithoutRetainCycle() async throws {
    let fixture = OAuthFixture()
    defer { fixture.provider.gate.releaseAll() }
    var oauth: OAuth? = OAuth(authenticationFeature: fixture.feature)
    weak var released = oauth
    var completions = 0
    let pending = try XCTUnwrap(oauth).receiveRedirect(
      redirectURL: URL(string: "ksrauth2://authenticate?code=fixture"), error: nil, verifier: "fixture"
    ) { _ in completions += 1 }
    await fixture.provider.gate.waitFor(1)
    oauth = nil
    XCTAssertNil(released)
    try fixture.provider.gate.finish(0, .success(.init(accessToken: "fixture", user: .template)))
    await pending.value
    XCTAssertEqual(fixture.logins, 0)
    XCTAssertEqual(completions, 0)
  }

  func verifyRedirectAsync(
    redirectURL url: URL?,
    error: Error?,
    verifier: String,
    verify: @escaping (OAuthAuthorizationResult) -> Void
  ) async {
    let feature = AuthenticationFeature(
      sessionFeature: SessionFeature(makeProvider: {
        AsyncSessionProvider(service: AppEnvironment.current.apiService)
      }),
      makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
    )
    let result = await OAuth.handleRedirect(
      redirectURL: url, error: error, verifier: verifier, authenticationFeature: feature
    )
    verify(result)
  }

  func testHandleRedirect_missingRedirectURL_fails() async {
    await self.verifyRedirectAsync(redirectURL: nil, error: nil, verifier: "") { result in
      if case .failure = result {
        // Success
      } else {
        XCTFail("Expected call to fail")
      }
    }
  }

  func testHandleRedirect_missingRedirectCodeWithNoCancelParam_fails() async {
    await self.verifyRedirectAsync(
      redirectURL: URL(string: "ksrauth2://authenticate?foo=bar"),
      error: nil,
      verifier: ""
    ) { result in
      if case .failure = result {
        // Success
      } else {
        XCTFail("Expected call to fail")
      }
    }
  }

  func testHandleRedirect_missingRedirectCodeAndIncludesCancelParam_cancels() async {
    await self.verifyRedirectAsync(
      redirectURL: URL(string: "ksrauth2://authenticate?canceled=true"),
      error: nil,
      verifier: ""
    ) { result in
      if case .canceled = result {
        // Success
      } else {
        XCTFail("Expected call to be cancelled")
      }
    }
  }

  func testHandleRedirect_cancellationError_cancels() async {
    let cancelledError = ASWebAuthenticationSessionError(.canceledLogin)
    await self.verifyRedirectAsync(redirectURL: nil, error: cancelledError, verifier: "") { result in
      if case .canceled = result {
        // Success
      } else {
        XCTFail("Expected call to be canceled")
      }
    }
  }

  func testHandleRedirect_anotherError_fails() async {
    let anotherError = ASWebAuthenticationSessionError(.presentationContextNotProvided)
    await self.verifyRedirectAsync(redirectURL: nil, error: anotherError, verifier: "") { result in
      if case .failure = result {
        // Success
      } else {
        XCTFail("Expected call to fail")
      }
    }
  }

  func testHandleRedirect_validCodeAndVerifier_logsIn() async {
    let urlWithCode = URL(string: "ksrauth2://authenticate?code=a1b2c3")

    XCTAssertNil(AppEnvironment.current.currentUser)
    XCTAssertNil(AppEnvironment.current.apiService.oauthToken)

    // The redirect makes two calls - the first is for token exchange, the second fetches the current user.
    let exchangeResponse = OAuthTokenExchangeResponse(token: "test_token")
    var currentUser = User.template
    currentUser.id = 123_456
    let mockService = MockService(fetchUserSelfResponse: currentUser, tokenExchangeResponse: exchangeResponse)

    await withEnvironment(apiService: mockService) {
      await self
        .verifyRedirectAsync(redirectURL: urlWithCode, error: nil, verifier: "test_verifier") { result in
          if case .loggedIn = result {
            XCTAssertNotNil(AppEnvironment.current.currentUser)
            XCTAssertEqual(AppEnvironment.current.currentUser?.id, currentUser.id)

            XCTAssertNotNil(AppEnvironment.current.apiService.oauthToken)
            XCTAssertEqual(AppEnvironment.current.apiService.oauthToken?.token, exchangeResponse.token)
          } else {
            XCTFail("Expected call to succeed")
          }
        }
    }
  }

  func testHandleRedirect_exchangeEndpointReturnsError_fails() async {
    let urlWithCode = URL(string: "ksrauth2://authenticate?code=a1b2c3")

    XCTAssertNil(AppEnvironment.current.currentUser)
    XCTAssertNil(AppEnvironment.current.apiService.oauthToken)

    // The redirect makes two calls - the first is for token exchange, the second fetches the current user.
    let expectedErrorMessage = "The token exchange failed."
    let exchangeError = ErrorEnvelope(
      errorMessages: [expectedErrorMessage],
      ksrCode: .UnknownCode,
      httpCode: 403,
      exception: nil
    )
    var currentUser = User.template
    currentUser.id = 123_456
    let mockService = MockService(loginError: exchangeError)

    await withEnvironment(apiService: mockService) {
      await self
        .verifyRedirectAsync(redirectURL: urlWithCode, error: nil, verifier: "test_verifier") { result in
          if case let .failure(errorMessage: errorMessage) = result {
            XCTAssertNil(AppEnvironment.current.currentUser)
            XCTAssertNil(AppEnvironment.current.apiService.oauthToken)

            XCTAssertEqual(errorMessage, expectedErrorMessage)
          } else {
            XCTFail("Expected call to fail")
          }
        }
    }
  }

  func testHandleRedirect_userEndpointReturnsError_fails() async {
    let urlWithCode = URL(string: "ksrauth2://authenticate?code=a1b2c3")

    XCTAssertNil(AppEnvironment.current.currentUser)
    XCTAssertNil(AppEnvironment.current.apiService.oauthToken)

    // The redirect makes two calls - the first is for token exchange, the second fetches the current user.
    let exchangeResponse = OAuthTokenExchangeResponse(token: "test_token")
    let expectedErrorMessage = "Unable to load user."
    let userError = ErrorEnvelope(
      errorMessages: [expectedErrorMessage],
      ksrCode: .UnknownCode,
      httpCode: 403,
      exception: nil
    )
    let mockService = MockService(fetchUserSelfError: userError, tokenExchangeResponse: exchangeResponse)

    await withEnvironment(apiService: mockService) {
      await self
        .verifyRedirectAsync(redirectURL: urlWithCode, error: nil, verifier: "test_verifier") { result in
          if case let .failure(errorMessage: errorMessage) = result {
            XCTAssertNil(AppEnvironment.current.currentUser)
            XCTAssertNil(AppEnvironment.current.apiService.oauthToken)

            XCTAssertEqual(errorMessage, expectedErrorMessage)
          } else {
            XCTFail("Expected call to fail")
          }
        }
    }
  }
}

@MainActor
private final class OAuthFixture {
  let provider = OAuthControlledProvider()
  var logins = 0
  lazy var feature = AuthenticationFeature(
    sessionFeature: SessionFeature(
      makeProvider: { AsyncSessionProvider(service: MockService()) },
      currentUser: { nil }, updateUser: { _ in }, login: { [weak self] _ in self?.logins += 1 }
    ), makeProvider: { [provider] in provider }
  )
}

@MainActor
private final class OAuthControlledProvider: AuthenticationProvider {
  let gate = AccountRequestGate<AccessTokenEnvelope>()
  func login(_: AuthenticationFeature.Credentials, code _: String?) async throws -> AccessTokenEnvelope {
    try await self.gate.request()
  }

  func resetPassword(email _: String) async throws { XCTFail("OAuth must not reset passwords") }
}
