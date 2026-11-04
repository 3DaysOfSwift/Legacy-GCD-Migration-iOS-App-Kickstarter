import AuthenticationServices
import FacebookLogin
import KsApi
import Prelude
import ReactiveSwift

public typealias SignInWithAppleData = (appId: String, firstName: String?, lastName: String?, token: String)

@MainActor
public protocol LoginToutViewModelInputs {
  /// Call when Apple completes authorization
  func appleAuthorizationDidSucceed(with data: SignInWithAppleData?)

  /// Call when Apple completes authorization with error
  func appleAuthorizationDidFail(with error: AppleAuthServicesError)

  /// Call when Continue withApple button is pressed
  func appleLoginButtonPressed()

  /// Call to set the reason the user is attempting to log in
  func configureWith(_ intent: LoginIntent)

  /// Call when the environment has been logged into
  func environmentLoggedIn()

  /// Call when Faceboook login button is pressed
  func facebookLoginButtonPressed()

  /// Call when Facebook login completed with error
  func facebookLoginFail(error: Error?)

  /// Call when Facebook login completed successfully with a result
  func facebookLoginSuccess(result: LoginManagerLoginResult)

  /// Call with login with OAuth button is pressed
  func signupOrLoginWithOAuthButtonPressed()

  /// Call when a user session starts.
  func userSessionStarted()

  /// Call when the view appears with a boolean telling us whether or not this controller was presented,
  /// i.e. it's presentingViewController is non-`nil`.
  func view(isPresented: Bool)

  /// Call when the view controller's viewWillAppear() method is called
  func viewWillAppear()
}

@MainActor
public protocol LoginToutViewModelOutputs {
  /// Emits whether a request is loading or not
  var isLoading: Signal<Bool, Never> { get }

  /// Emits when a login success notification should be posted.
  var postNotification: Signal<(Notification, Notification), Never> { get }

}

@MainActor
public protocol LoginToutViewModelType {
  var inputs: LoginToutViewModelInputs { get }
  var outputs: LoginToutViewModelOutputs { get }
}

@MainActor
public final class LoginToutViewModel: LoginToutViewModelType, LoginToutViewModelInputs,
  LoginToutViewModelOutputs {
  private let authenticationFeature: AuthenticationFeature
  private let loadingProperty = MutableProperty(false)
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
    let isLoading = self.loadingProperty
    self.isLoading = isLoading.signal.skipRepeats()

    self.postNotification = self.environmentLoggedInProperty.signal
      .mapConst((
        Notification(name: .ksr_sessionStarted),
        Notification(
          name: .ksr_showNotificationsDialog,
          userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.login]
        )
      ))
      // Post notifications on the next run loop to avoid race condition with VCs being deallocated.
      .ksr_delay(.nanoseconds(0), on: AppEnvironment.current.scheduler)

    self.viewWillAppearProperty.signal
      .take(first: 1)
      .observeValues { AppEnvironment.current.ksrAnalytics.trackLoginTOutPageViewed() }

  }

  deinit { self.appleTask?.cancel(); self.facebookTask?.cancel() }

  public var inputs: LoginToutViewModelInputs { return self }
  public var outputs: LoginToutViewModelOutputs { return self }

  var onAppleLogin: (() -> Void)?
  var onFacebookLogin: (() -> Void)?
  var onOAuth: (() -> Void)?
  var onDismiss: (() -> Void)?
  private var isPresented: Bool?
  public func appleLoginButtonPressed() { self.onAppleLogin?() }

  public func appleAuthorizationDidSucceed(with data: SignInWithAppleData?) {
    guard let data else { return }
    if self.appleTask != nil { self.appleTask?.cancel(); self.loadingProperty.value = false }
    let version = UUID()
    self.appleVersion = version
    let feature = self.authenticationFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.loadingProperty.value = true
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
      self.loadingProperty.value = false
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

  fileprivate let environmentLoggedInProperty = MutableProperty(())
  public func environmentLoggedIn() {
    self.environmentLoggedInProperty.value = ()
  }

  public func facebookLoginButtonPressed() { self.onFacebookLogin?() }

  public func facebookLoginFail(error: Error?) {
    if let error = error as NSError? { self.onFacebookError?(.facebookLoginAttemptFail(error: error)) }
  }

  public func facebookLoginSuccess(result: LoginManagerLoginResult) {
    let token = result.token?.tokenString ?? ""
    if self.facebookTask != nil { self.facebookTask?.cancel(); self.loadingProperty.value = false }
    let version = UUID()
    self.facebookVersion = version
    let feature = self.authenticationFeature
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.loadingProperty.value = true
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
      self.loadingProperty.value = false
    }
  }
  func waitForFacebook() async { await self.facebookTask?.value }

  public func signupOrLoginWithOAuthButtonPressed() {
    self.onOAuth?()
    AppEnvironment.current.ksrAnalytics.trackLoginInitiateButtonClicked()
  }

  public func userSessionStarted() { if self.isPresented == true { self.onDismiss?() } }
  public func view(isPresented: Bool) { self.isPresented = isPresented }

  fileprivate var viewWillAppearProperty = MutableProperty(())
  public func viewWillAppear() {
    self.viewWillAppearProperty.value = ()
    if let intent = self.configuredIntent {
      self.onContext?(statusString(intent), intent != .generic && intent != .discoveryOnboarding)
    }
  }

  public let isLoading: Signal<Bool, Never>
  public let postNotification: Signal<(Notification, Notification), Never>
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
