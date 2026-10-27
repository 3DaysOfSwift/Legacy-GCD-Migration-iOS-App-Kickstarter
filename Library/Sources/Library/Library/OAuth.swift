import AuthenticationServices
import FirebaseCrashlytics
import Foundation
import KsApi

public enum OAuthAuthorizationResult {
  case loggedIn
  case failure(errorMessage: String)
  case canceled
}

@MainActor
public final class OAuth {
  private let authenticationFeature: AuthenticationFeature
  private var redirectTask: Task<Void, Never>?
  private var browserSession: ASWebAuthenticationSession?
  private var authorizationID = UUID()

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    self.authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
  }

  deinit { self.redirectTask?.cancel() }

  public func cancel() {
    self.authorizationID = UUID()
    self.redirectTask?.cancel()
    self.redirectTask = nil
    self.browserSession?.cancel()
    self.browserSession = nil
  }

  static let redirectScheme = "ksrauth2"

  static func authorizationURL(withCodeChallenge challenge: String) -> URL? {
    let serverConfig = AppEnvironment.current.apiService.serverConfig
    let baseURL = serverConfig.webBaseUrl

    let parameters = [
      URLQueryItem(name: "redirect_uri", value: redirectScheme),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "email"),
      URLQueryItem(name: "client_id", value: serverConfig.apiClientAuth.clientId),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "code_challenge", value: challenge)
    ]

    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    components?.path = "/oauth/authorizations/new"
    components?.queryItems = parameters

    return components?.url
  }

  public func createAuthorizationSession(onComplete: @escaping (OAuthAuthorizationResult) -> Void)
    -> ASWebAuthenticationSession? {
    self.cancel()
    let authorizationID = self.authorizationID
    let sessionGeneration = self.authenticationFeature.sessionGeneration
    do {
      let verifier = try PKCE.createCodeVerifier(byteLength: 32)
      if !PKCE.checkCodeVerifier(verifier) {
        return nil
      }

      let challenge = try PKCE.createCodeChallenge(fromVerifier: verifier)

      guard let url = Self.authorizationURL(withCodeChallenge: challenge) else {
        return nil
      }

      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: OAuth.redirectScheme
      ) { [weak self] url, error in
        // AuthenticationServices owns the callback. This hop only hands it to
        // the screen-owned adapter; all awaited work is retained below.
        Task { @MainActor [weak self] in
          guard let self, self.authorizationID == authorizationID else { return }
          self.browserSession = nil
          guard self.authenticationFeature.sessionGeneration == sessionGeneration else {
            onComplete(.canceled)
            return
          }
          self.receiveRedirect(redirectURL: url, error: error, verifier: verifier, onComplete: onComplete)
        }
      }

      self.browserSession = session
      return session

    } catch {
      // If these get triggered, we could add additional logging in the PKCE code to pass
      // through the security failure codes. For now, log them all as one type.
      Crashlytics.crashlytics().record(error: OAuthError.pkceError.nsError)
      return nil
    }
  }

  /// The browser callback hands work to this retained, screen-owned task.
  /// Replacing or releasing the adapter cancels its caller before session commit.
  @discardableResult
  func receiveRedirect(
    redirectURL: URL?, error: Error?, verifier: String,
    onComplete: @escaping (OAuthAuthorizationResult) -> Void
  ) -> Task<Void, Never> {
    self.redirectTask?.cancel()
    let authorizationID = self.authorizationID
    let task = Task { [weak self, feature = self.authenticationFeature] in
      let result = await Self.handleRedirect(
        redirectURL: redirectURL, error: error, verifier: verifier, authenticationFeature: feature
      )
      guard !Task.isCancelled, let self, self.authorizationID == authorizationID else { return }
      self.redirectTask = nil
      onComplete(result)
    }
    self.redirectTask = task
    return task
  }

  internal static func handleRedirect(
    redirectURL url: URL?,
    error: Error?,
    verifier: String,
    authenticationFeature: AuthenticationFeature
  ) async -> OAuthAuthorizationResult {
    guard !Task.isCancelled else { return .canceled }
    if let error {
      if let authenticationError = error as? ASWebAuthenticationSessionError,
         authenticationError.code == .canceledLogin { return .canceled }
      Crashlytics.crashlytics().record(error: OAuthError.redirectError(error).nsError)
      return .failure(errorMessage: Strings.Something_went_wrong_please_try_again())
    }
    if self.isRedirectURLCanceled(url) { return .canceled }
    guard let code = self.codeFromRedirectURL(url) else {
      Crashlytics.crashlytics().record(error: OAuthError.missingCodeError.nsError)
      return .failure(errorMessage: Strings.Something_went_wrong_please_try_again())
    }
    do {
      _ = try await authenticationFeature.authenticate(.oauth(code: code, verifier: verifier))
      return .loggedIn
    } catch is CancellationError {
      return .canceled
    } catch {
      let envelope = error as? ErrorEnvelope ?? .couldNotParseJSON
      Crashlytics.crashlytics().record(error: OAuthError.exchangeFailedError(envelope).nsError)
      return .failure(errorMessage: envelope.errorMessages.first ?? Strings.login_errors_unable_to_log_in())
    }
  }

  private static func codeFromRedirectURL(_ url: URL?) -> String? {
    guard let redirectURL = url else {
      return nil
    }

    let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
    return components?.queryItems?.first(where: { $0.name == "code" })?.value
  }

  private static func isRedirectURLCanceled(_ url: URL?) -> Bool {
    guard let redirectURL = url else {
      return false
    }

    let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
    return components?.queryItems?.first(where: { $0.name == "canceled" && $0.value == "true" }) != nil
  }
}
