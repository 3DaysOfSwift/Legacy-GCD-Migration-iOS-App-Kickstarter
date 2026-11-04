import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class FacebookConfirmationViewModel {
  public private(set) var displayEmail = ""
  public private(set) var sendNewsletters = false
  public private(set) var isLoading = false
  public var onLogin: (() -> Void)?
  public var onSignupSuccess: (() -> Void)?
  public var onSignupError: ((String) -> Void)?
  public var onHelp: ((HelpType) -> Void)?

  private let authenticationFeature: AuthenticationFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var token = ""
  private var signupTask: Task<Void, Never>?
  private var revision = 0

  public init(authenticationFeature: AuthenticationFeature? = nil,
              sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
                if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
              }) {
    self.authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
    self.sleep = sleep
  }

  public func viewDidLoad() { self.sendNewsletters = false }
  public func email(_ email: String) { self.displayEmail = email }
  public func facebookToken(_ token: String) { self.token = token }
  public func sendNewslettersToggled(_ newsletters: Bool) { self.sendNewsletters = newsletters }
  public func loginButtonPressed() { self.onLogin?() }
  public func tapped(_ url: URL) {
    guard let helpType = HelpType.allCases.first(where: {
      url.absoluteString == $0.url(withBaseUrl: AppEnvironment.current.apiService.serverConfig.webBaseUrl)?.absoluteString
    }) else { return }
    self.onHelp?(helpType)
  }
  public func createAccountButtonPressed() {
    self.signupTask?.cancel()
    self.revision += 1
    let revision = self.revision
    let credentials = AuthenticationFeature.Credentials.facebookSignup(self.token, sendNewsletters: self.sendNewsletters)
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.isLoading = true
    self.signupTask = Task { [weak self, authenticationFeature, sleep] in
      do {
        _ = try await authenticationFeature.authenticate(credentials)
        try Task.checkCancellation()
        guard self?.revision == revision else { return }
        self?.isLoading = false
        try await sleep(delay)
        try Task.checkCancellation()
        guard self?.revision == revision else { return }
        self?.onSignupSuccess?()
      } catch {
        guard let self, !Task.isCancelled, !(error is CancellationError), self.revision == revision else { return }
        self.isLoading = false
        do { try await sleep(delay); try Task.checkCancellation() } catch { return }
        guard self.revision == revision else { return }
        self.onSignupError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.facebook_confirmation_could_not_log_in())
      }
    }
  }
  internal func waitForSignup() async { await self.signupTask?.value }
}
