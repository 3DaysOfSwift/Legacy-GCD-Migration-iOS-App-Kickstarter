import Observation

@MainActor
@Observable
public final class LoginSignupUseCase {
  public private(set) var isLoggedIn = false
  var onLogin: ((LoginIntent) -> Void)?
  var onSessionChanged: (() -> Void)?
  var onLoginState: ((Bool) -> Void)?
  private let intent: LoginIntent

  init(withLoginIntent intent: LoginIntent) { self.intent = intent }

  public func initialDataAvailable() { self.publishLoginState() }
  public func goToLoginSignupTapped() { self.onLogin?(self.intent) }
  public func userSessionDidChange() {
    self.publishLoginState()
    self.onSessionChanged?()
  }

  private func publishLoginState() {
    self.isLoggedIn = AppEnvironment.current.currentUser != nil
    self.onLoginState?(self.isLoggedIn)
  }
}
