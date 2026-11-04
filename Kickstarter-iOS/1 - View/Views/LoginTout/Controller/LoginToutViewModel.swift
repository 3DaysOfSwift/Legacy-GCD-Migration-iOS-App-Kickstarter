import AuthenticationServices
import FacebookLogin
import KsApi
import Prelude

public typealias SignInWithAppleData = (appId: String, firstName: String?, lastName: String?, token: String)

@MainActor
public final class LoginToutViewModel {
  private let authenticationFeature: AuthenticationFeature
  private var lastLoading: Bool?
  private var didTrackAppearance = false
  private var notificationTask: Task<Void, Never>?
  var onLoading: ((Bool) -> Void)?
  var onNotification: ((Notification, Notification) -> Void)?
  private func setLoading(_ value: Bool) {
    guard self.lastLoading != value else { return }
    self.lastLoading = value
    self.onLoading?(value)
  }
  private var appleTask: Task<Void, Never>?
  private var appleVersion = UUID()
  private var facebookTask: Task<Void, Never>?
  private var facebookVersion = UUID()
  var onFacebookSuccess: ((AccessTokenEnvelope) -> Void)?
  var onFacebookError: ((AlertError) -> Void)?
  var onFacebookConfirmation: ((ErrorEnvelope.FacebookUser?, String) -> Void)?
  var onFacebookTwoFactor: ((String) -> Void)?
  var onAppleSuccess: ((AccessTokenEnvelope) -> Void)?
  var onAppleError: ((String) -> Void)?
  var onAppleLog: ((NSError) -> Void)?

  public init(authenticationFeature: AuthenticationFeature? = nil) {
    let authenticationFeature = authenticationFeature ?? AppModel.shared.authenticationFeature
    self.authenticationFeature = authenticationFeature

  }

  deinit { self.appleTask?.cancel(); self.facebookTask?.cancel() }

  var onAppleLogin: (() -> Void)?
  var onFacebookLogin: (() -> Void)?
  var onOAuth: (() -> Void)?
  var onDismiss: (() -> Void)?
  private var isPresented: Bool?
  public func appleLoginButtonPressed() { self.onAppleLogin?() }

  public func appleAuthorizationDidSucceed(with data: SignInWithAppleData?) {
    guard let data else { return }
    if self.appleTask != nil { self.appleTask?.cancel(); self.setLoading(false) }
    let version = UUID()
    self.appleVersion = version
    let feature = self.authenticationFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.setLoading(true)
    self.appleTask = Task { [weak self] in
      let outcome: Result<AccessTokenEnvelope, Error>
      do {
        outcome = .success(try await feature.authenticate(.apple(
          appID: data.appId, firstName: data.firstName, lastName: data.lastName, token: data.token
        )))
      } catch { outcome = .failure(error) }
      do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) }; try Task.checkCancellation() }
      catch { return }
      guard let self, self.appleVersion == version else { return }
      switch outcome {
      case let .success(value): self.onAppleSuccess?(value)
      case let .failure(error): self.onAppleError?((error as? ErrorEnvelope ?? .couldNotParseJSON).localizedDescription)
      }
      self.appleTask = nil
      self.setLoading(false)
    }
  }
  public func appleAuthorizationDidFail(with error: AppleAuthServicesError) {
    if let message = errorMessage(from: error) { self.onAppleError?(message) }
    if let error = error.nsError { self.onAppleLog?(error) }
  }
  func waitForApple() async { await self.appleTask?.value }

  var onContext: ((String, Bool) -> Void)?
  private var configuredIntent: LoginIntent?
  public func configureWith(_ intent: LoginIntent) {
    self.configuredIntent = intent
  }

  public func environmentLoggedIn() {
    let notify = self.onNotification
    self.notificationTask = Task { @MainActor in
      await Task.yield()
      notify?(Notification(name: .ksr_sessionStarted), Notification(
        name: .ksr_showNotificationsDialog,
        userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.login]
      ))
    }
  }
  func waitForNotification() async { await self.notificationTask?.value }

  public func facebookLoginButtonPressed() { self.onFacebookLogin?() }

  public func facebookLoginFail(error: Error?) {
    if let error = error as NSError? { self.onFacebookError?(.facebookLoginAttemptFail(error: error)) }
  }

  public func facebookLoginSuccess(result: LoginManagerLoginResult) {
    let token = result.token?.tokenString ?? ""
    if self.facebookTask != nil { self.facebookTask?.cancel(); self.setLoading(false) }
    let version = UUID()
    self.facebookVersion = version
    let feature = self.authenticationFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.setLoading(true)
    self.facebookTask = Task { [weak self] in
      let outcome: Result<AccessTokenEnvelope, Error>
      do { outcome = .success(try await feature.authenticate(.facebook(token))) }
      catch { outcome = .failure(error) }
      do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) }; try Task.checkCancellation() }
      catch { return }
      guard let self, self.facebookVersion == version else { return }
      switch outcome {
      case let .success(value): self.onFacebookSuccess?(value)
      case let .failure(error):
        let envelope = error as? ErrorEnvelope ?? .couldNotParseJSON
        switch envelope.ksrCode {
        case .TfaRequired: self.onFacebookTwoFactor?(token)
        case .ConfirmFacebookSignup: self.onFacebookConfirmation?(envelope.facebookUser, token)
        case .FacebookInvalidAccessToken: self.onFacebookError?(.facebookTokenFail)
        default: self.onFacebookError?(.genericFacebookError(envelope: envelope))
        }
      }
      self.facebookTask = nil
      self.setLoading(false)
    }
  }
  func waitForFacebook() async { await self.facebookTask?.value }

  public func signupOrLoginWithOAuthButtonPressed() {
    self.onOAuth?()
    AppEnvironment.current.ksrAnalytics.trackLoginInitiateButtonClicked()
  }

  public func userSessionStarted() { if self.isPresented == true { self.onDismiss?() } }
  public func view(isPresented: Bool) { self.isPresented = isPresented }

  public func viewWillAppear() {
    if !self.didTrackAppearance {
      self.didTrackAppearance = true
      AppEnvironment.current.ksrAnalytics.trackLoginTOutPageViewed()
    }
    if let intent = self.configuredIntent {
      self.onContext?(statusString(intent), intent != .generic && intent != .discoveryOnboarding)
    }
  }

}

private func statusString(_ forStatus: LoginIntent) -> String {
  switch forStatus {
  case .starProject, .videoFeed:
    return Strings.Log_in_or_sign_up_to_save_this_project_and_we_ll_remind_you()
  case .backProject:
    return Strings.Please_log_in_or_sign_up_to_back_this_project()
  case .messageCreator:
    return Strings.Please_log_in_or_sign_up_to_message_this_creator()
  case .discoveryOnboarding, .onboarding, .generic, .activity, .loginTab, .erroredPledge:
    return Strings.Pledge_to_projects_and_view_all_your_saved_and_backed_projects_in_one_place()
  }
}

private func errorMessage(from error: AppleAuthServicesError) -> String? {
  switch error {
  case let .other(error):
    return error.localizedDescription
  case .canceled:
    return nil
  }
}
