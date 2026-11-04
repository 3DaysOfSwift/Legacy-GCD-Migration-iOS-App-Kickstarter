import Foundation
import KsApi

@MainActor
public final class LoginViewModel {
  var onDismissKeyboard: (() -> Void)?
  var onEmailFirstResponder: (() -> Void)?
  var onFormValid: ((Bool) -> Void)?
  var onLogin: ((AccessTokenEnvelope) -> Void)?
  var onPasswordFirstResponder: (() -> Void)?
  var onNotification: ((Notification, Notification) -> Void)?
  var onError: ((String) -> Void)?
  var onResetPassword: (() -> Void)?
  var onPasswordVisibility: ((Bool) -> Void)?
  var onTwoFactor: ((String, String) -> Void)?

  private let authenticationFeature: AuthenticationFeature
  private var email: String?
  private var password: String?
  private var showPassword = false
  private var hasVisibilityValue = false
  private var appeared = false
  private var loginTask: Task<Void, Never>?
  private var loginVersion = UUID()

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    self.authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
  }
  deinit { self.loginTask?.cancel() }

  func viewWillAppear() {
    guard !self.appeared else { return }
    self.appeared = true
    self.onFormValid?(false)
  }
  func viewDidLoad() {
    self.onEmailFirstResponder?()
    AppEnvironment.current.ksrAnalytics.trackLoginPageViewed()
  }
  func emailChanged(_ email: String?) { guard let email else { return }; self.email = email; self.publishValidity() }
  func passwordChanged(_ password: String?) { guard let password else { return }; self.password = password; self.publishValidity() }
  private func publishValidity() {
    guard let email = self.email, let password = self.password else { return }
    self.onFormValid?(isValidEmail(email) && !password.isEmpty)
  }
  func emailTextFieldDoneEditing() { self.onPasswordFirstResponder?() }
  func passwordTextFieldDoneEditing() { self.submit(); self.onDismissKeyboard?() }
  func loginButtonPressed() { self.submit() }
  private func submit() {
    AppEnvironment.current.ksrAnalytics.trackLoginSubmitButtonClicked()
    guard let email = self.email, let password = self.password else { return }
    self.loginTask?.cancel()
    let version = UUID()
    self.loginVersion = version
    let feature = self.authenticationFeature
    self.loginTask = Task { [weak self] in
      do {
        let result = try await feature.authenticate(.email(email, password: password))
        guard !Task.isCancelled, let self, self.loginVersion == version else { return }
        self.onLogin?(result)
      } catch {
        guard !Task.isCancelled, let self, self.loginVersion == version else { return }
        if let error = error as? ErrorEnvelope, error.ksrCode == .TfaRequired {
          if let currentEmail = self.email, let currentPassword = self.password {
            self.onTwoFactor?(currentEmail, currentPassword)
          }
        } else if let error = error as? ErrorEnvelope {
          self.onError?(error.errorMessages.first ?? Strings.login_errors_unable_to_log_in())
        } else {
          self.onError?(Strings.login_errors_unable_to_log_in())
        }
      }
    }
  }
  func environmentLoggedIn() {
    self.onNotification?(Notification(name: .ksr_sessionStarted), Notification(
      name: .ksr_showNotificationsDialog,
      userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.login]
    ))
  }
  func resetPasswordButtonPressed() { self.onResetPassword?() }
  func showHidePasswordButtonTapped() { self.showPassword.toggle(); self.hasVisibilityValue = true; self.onPasswordVisibility?(self.showPassword) }
  func traitCollectionDidChange() { if self.hasVisibilityValue { self.onPasswordVisibility?(self.showPassword) } }
  func waitForLogin() async { await self.loginTask?.value }
}
