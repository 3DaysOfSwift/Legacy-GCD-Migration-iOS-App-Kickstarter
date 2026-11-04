import Foundation
import KsApi

@MainActor
public final class TwoFactorViewModel {
  var onFirstResponder: (() -> Void)?
  var onFormValid: ((Bool) -> Void)?
  var onLoading: ((Bool) -> Void)?
  var onLogin: ((AccessTokenEnvelope) -> Void)?
  var onNotification: ((Notification, Notification) -> Void)?
  var onResendSuccess: (() -> Void)?
  var onError: ((String) -> Void)?

  private let feature: AuthenticationFeature
  private var emailValue: String?
  private var password: String?
  private var token: String?
  private var code: String?
  private var lastValid: Bool?
  private var loginTask: Task<Void, Never>?
  private var resendTask: Task<Void, Never>?
  private var loginVersion = UUID()
  private var resendVersion = UUID()

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    self.feature = authenticationFeature ?? AppModel.shared.authenticationFeature
  }
  deinit { self.loginTask?.cancel(); self.resendTask?.cancel() }

  func codeChanged(_ code: String?) { self.code = code; self.publishValidity(code?.count == 6) }
  func email(_ email: String, password: String) { self.emailValue = email; self.password = password }
  func facebookToken(_ token: String) { self.token = token }
  func viewDidLoad() { self.onFirstResponder?() }
  func viewWillAppear() { self.publishValidity(false) }
  private func publishValidity(_ value: Bool) {
    guard self.lastValid != value else { return }
    self.lastValid = value; self.onFormValid?(value)
  }
  private var credentials: AuthenticationFeature.Credentials? {
    if let email = self.emailValue, let password = self.password { return .email(email, password: password) }
    if let token = self.token { return .facebook(token) }
    return nil
  }
  func submitPressed() {
    guard let credentials = self.credentials else { return }
    if self.loginTask != nil { self.loginTask?.cancel(); self.onLoading?(false) }
    let version = UUID(); self.loginVersion = version
    let feature = self.feature, code = self.code
    self.onLoading?(true)
    self.loginTask = Task { [weak self] in
      do {
        let result = try await feature.authenticate(credentials, code: code)
        guard !Task.isCancelled, let self, self.loginVersion == version else { return }
        self.onLogin?(result)
      } catch {
        guard !Task.isCancelled, let self, self.loginVersion == version else { return }
        let envelope = error as? ErrorEnvelope ?? .couldNotParseJSON
        self.onError?(envelope.errorMessages.first ?? (envelope.ksrCode == .TfaFailed ? Strings.two_factor_error_message() : Strings.login_errors_unable_to_log_in()))
      }
      guard let self, self.loginVersion == version else { return }
      self.loginTask = nil; self.onLoading?(false)
    }
  }
  func resendPressed() {
    guard let credentials = self.credentials else { return }
    if self.resendTask != nil { self.resendTask?.cancel(); self.onLoading?(false) }
    let version = UUID(); self.resendVersion = version
    let feature = self.feature
    self.onLoading?(true)
    self.resendTask = Task { [weak self] in
      do { try await feature.resendCode(credentials) }
      catch {
        guard !Task.isCancelled, let self, self.resendVersion == version else { return }
        if (error as? ErrorEnvelope)?.ksrCode == .TfaRequired { self.onResendSuccess?() }
      }
      guard let self, self.resendVersion == version else { return }
      self.resendTask = nil; self.onLoading?(false)
    }
  }
  func environmentLoggedIn() {
    self.onNotification?(Notification(name: .ksr_sessionStarted), Notification(
      name: .ksr_showNotificationsDialog,
      userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.login]
    ))
  }
  func waitForRequests() async { await self.loginTask?.value; await self.resendTask?.value }
}
