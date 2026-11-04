@testable import Kickstarter_iOS
@testable import FacebookLogin
@testable import KsApi


import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class LoginToutViewModelTests: TestCase {
  // Logic-only coverage; visual suites retain their reference-device requirement.
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let authenticationFeature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: LoginToutViewModel = LoginToutViewModel(
    authenticationFeature: self
      .authenticationFeature
  )

  fileprivate let attemptAppleLogin = TestObserver<(), Never>()
  fileprivate let attemptFacebookLogin = TestObserver<(), Never>()
  fileprivate let didSignInWithApple = TestObserver<SignInWithAppleEnvelope, Never>()
  fileprivate let dismissViewController = TestObserver<(), Never>()
  fileprivate let headlineLabelHidden = TestObserver<Bool, Never>()
  fileprivate let isLoading = TestObserver<Bool, Never>()
  fileprivate let logInContextText = TestObserver<String, Never>()
  fileprivate let logIntoEnvironmentWithApple = TestObserver<AccessTokenEnvelope, Never>()
  fileprivate let logIntoEnvironmentWithFacebook = TestObserver<AccessTokenEnvelope, Never>()
  fileprivate let postNotification = TestObserver<(Notification.Name, Notification.Name), Never>()
  fileprivate let showAppleErrorAlert = TestObserver<String, Never>()
  fileprivate let showFacebookErrorAlert = TestObserver<AlertError, Never>()
  fileprivate let startFacebookConfirmation = TestObserver<String, Never>()
  fileprivate let startOAuthSignupOrLogin = TestObserver<(), Never>()
  fileprivate let startTwoFactorChallenge = TestObserver<String, Never>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.vm.waitForFacebook()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onAppleLogin = { [weak self] in self?.attemptAppleLogin.observer.send(value: ()) }
    self.vm.onFacebookLogin = { [weak self] in self?.attemptFacebookLogin.observer.send(value: ()) }
    self.vm.onDismiss = { [weak self] in self?.dismissViewController.observer.send(value: ()) }
    self.vm.onOAuth = { [weak self] in self?.startOAuthSignupOrLogin.observer.send(value: ()) }
    self.vm.onContext = { [weak self] text, hidden in
      self?.logInContextText.observer.send(value: text)
      self?.headlineLabelHidden.observer.send(value: hidden)
    }
    self.vm.onLoading = { [weak self] in self?.isLoading.observer.send(value: $0) }
    self.vm.onAppleSuccess = { [weak self] in self?.logIntoEnvironmentWithApple.observer.send(value: $0) }
    self.vm.onFacebookSuccess = { [weak self] in self?.logIntoEnvironmentWithFacebook.observer.send(value: $0) }
    self.vm.onNotification = { [weak self] in self?.postNotification.observer.send(value: ($0.name, $1.name)) }
    self.vm.onAppleError = { [weak self] in self?.showAppleErrorAlert.observer.send(value: $0) }
    self.vm.onFacebookError = { [weak self] in self?.showFacebookErrorAlert.observer.send(value: $0) }
    self.vm.onFacebookConfirmation = { [weak self] _, token in self?.startFacebookConfirmation.observer.send(value: token) }
    self.vm.onFacebookTwoFactor = { [weak self] in self?.startTwoFactorChallenge.observer.send(value: $0) }
  }

  func testLoginIntent_Pledge() async {
    self.vm.configureWith(.backProject)
    self.vm.viewWillAppear()

    self.logInContextText.assertValues(
      ["Please log in or sign up to back this project."],
      "Emits login Context Text"
    )
  }

  func testStartSignupOrLoginWithOAuth() async {
    self.vm.viewWillAppear()
    self.vm.signupOrLoginWithOAuthButtonPressed()
    self.startOAuthSignupOrLogin.assertValueCount(1, "OAuth signup/loginlogin emitted")
  }

  func testHeadlineLabelHidden() async {
    self.vm.configureWith(.starProject)
    self.vm.viewWillAppear()

    self.headlineLabelHidden.assertValues([true])
  }

  func testHeadlineLabelShown() async {
    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.headlineLabelHidden.assertValues([false])
  }

  func testLoginContextText() async {
    self.vm.configureWith(.starProject)
    self.vm.viewWillAppear()

    self.logInContextText.assertValues(
      ["Log in or sign up to save this project. We’ll remind you 48 hours before it ends."],
      "Emits login Context Text"
    )
  }

  func testFacebookLoginFlow_Succes() async {
    let token = AccessToken(
      tokenString: "12344566",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    await withEnvironment {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.attemptFacebookLogin.assertValueCount(0, "Attempt Facebook login did not emit")

      self.vm.facebookLoginButtonPressed()

      self.attemptFacebookLogin.assertValueCount(1, "Attempt Facebook login emitted")

      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true])

      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironmentWithFacebook.assertValueCount(1, "Log into environment.")

      self.vm.environmentLoggedIn()

      self.postNotification.assertDidNotEmitValue()

      await self.vm.waitForNotification()

      // Notifications are posted on the next run loop
      XCTAssertEqual(self.postNotification.values.first?.0, .ksr_sessionStarted, "Login notification posted.")
      XCTAssertEqual(
        self.postNotification.values.first?.1, .ksr_showNotificationsDialog,
        "Contextual Dialog notification posted."
      )

      self.showFacebookErrorAlert.assertValueCount(0, "Facebook login error did not emit")
      self.startFacebookConfirmation.assertValueCount(0, "Facebook confirmation did not emit")
    }
  }

  func testLoginFacebookFlow_AttemptFail() async {
    let error = NSError(
      domain: "facebook.com",
      code: 404,
      userInfo: [
        ErrorLocalizedTitleKey: "Facebook Login Fail",
        ErrorLocalizedDescriptionKey: "Something went wrong yo."
      ]
    )

    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.attemptFacebookLogin.assertValueCount(0, "Attempt Facebook login did not emit")
    self.showFacebookErrorAlert.assertValueCount(0, "Facebook login error did not emit")

    self.vm.facebookLoginButtonPressed()

    self.isLoading.assertDidNotEmitValue()
    self.attemptFacebookLogin.assertValueCount(1, "Attempt Facebook login emitted")
    self.showFacebookErrorAlert.assertValueCount(0, "Facebook login fail does not emit")

    self.vm.facebookLoginFail(error: error)

    self.isLoading.assertDidNotEmitValue()
    self.showFacebookErrorAlert.assertValues(
      [AlertError.facebookLoginAttemptFail(error: error)],
      "Show Facebook Attempt Login error"
    )
  }

  func testLoginFacebookFlow_AttemptFail_WithDefaultMessage() async {
    let error = NSError(
      domain: "facebook.com",
      code: 404,
      userInfo: [:]
    )

    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.attemptFacebookLogin.assertValueCount(0, "Attempt Facebook login did not emit")
    self.showFacebookErrorAlert.assertValueCount(0, "Facebook login error did not emit")

    self.vm.facebookLoginButtonPressed()

    self.isLoading.assertDidNotEmitValue()
    self.attemptFacebookLogin.assertValueCount(1, "Attempt Facebook login emitted")
    self.showFacebookErrorAlert.assertValueCount(0, "Facebook login fail does not emit")

    self.vm.facebookLoginFail(error: error)

    self.isLoading.assertDidNotEmitValue()
    self.showFacebookErrorAlert.assertValues(
      [AlertError.facebookLoginAttemptFail(error: error)],
      "Show Facebook Attempt Login error"
    )
  }

  func testLoginFacebookFlow_InvalidTokenFail() async {
    let token = AccessToken(
      tokenString: "spaghetti",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    let error = ErrorEnvelope(
      errorMessages: ["Couldn't log into Facebook."],
      ksrCode: .FacebookInvalidAccessToken,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.showFacebookErrorAlert.assertValueCount(0, "Facebook login fail does not emit")

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true])
      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.showFacebookErrorAlert.assertValues(
        [AlertError.facebookTokenFail],
        "Show Facebook token fail error"
      )
    }
  }

  func testLoginFacebookFlow_GenericFail() async {
    let token = AccessToken(
      tokenString: "12344566",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    let error = ErrorEnvelope(
      errorMessages: ["Something went wrong."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true])
      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.showFacebookErrorAlert.assertValues(
        [AlertError.genericFacebookError(envelope: error)],
        "Show Facebook account taken error"
      )
    }
  }

  func testLoginFacebookFlow_GenericFail_WithDefaultMessage() async {
    let token = AccessToken(
      tokenString: "12344566",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true])
      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.showFacebookErrorAlert.assertValues(
        [AlertError.genericFacebookError(envelope: error)],
        "Show Facebook account taken error"
      )
    }
  }

  func testStartTwoFactorChallenge() async {
    let token = AccessToken(
      tokenString: "12344566",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    let error = ErrorEnvelope(
      errorMessages: ["Two Factor Authenticaion is required."],
      ksrCode: .TfaRequired,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.startTwoFactorChallenge.assertDidNotEmitValue()

      self.isLoading.assertValues([true])
      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.startTwoFactorChallenge.assertValues(["12344566"], "TFA challenge emitted with token")
      self.logIntoEnvironmentWithApple.assertValueCount(0, "Did not log into environment.")
      self.logIntoEnvironmentWithFacebook.assertValueCount(0, "Did not log into environment.")
      self.showFacebookErrorAlert.assertValueCount(0, "Facebook login fail does not emit")
      self.startFacebookConfirmation.assertValueCount(0, "Facebook confirmation did not emit")
    }
  }

  func testStartFacebookConfirmation() async {
    let token = AccessToken(
      tokenString: "12344566",
      permissions: [],
      declinedPermissions: [],
      expiredPermissions: [],
      appID: "834987809",
      userID: "0000000001",
      expirationDate: Date(),
      refreshDate: Date(),
      dataAccessExpirationDate: Date()
    )

    let result = LoginManagerLoginResult(
      token: token,
      authenticationToken: nil,
      isCancelled: false,
      grantedPermissions: [],
      declinedPermissions: []
    )

    let error = ErrorEnvelope(
      errorMessages: ["Confirm Facebook Signup"],
      ksrCode: .ConfirmFacebookSignup,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true])
      // Wait enough time for API request to be made.
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.startFacebookConfirmation.assertValues(
        ["12344566"],
        "Start Facebook confirmation emitted with token"
      )
      self.logIntoEnvironmentWithFacebook.assertValueCount(0, "Did not log into environment.")
      self.showFacebookErrorAlert.assertValueCount(0, "Facebook login fail does not emit")

      self.vm.viewWillAppear()

      self.startFacebookConfirmation.assertValues(["12344566"], "Facebook confirmation didn't start again.")

      self.vm.facebookLoginButtonPressed()
      self.vm.facebookLoginSuccess(result: result)

      self.isLoading.assertValues([true, false, true])
      await self.vm.waitForFacebook()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false, true, false])
      self.startFacebookConfirmation.assertValues(
        ["12344566", "12344566"],
        "Start Facebook confirmation emitted with token"
      )
    }
  }

  func testDismissalWhenNotPresented() async {
    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()
    self.vm.view(isPresented: false)
    self.vm.userSessionStarted()

    self.dismissViewController.assertValueCount(0)
  }

  func testDismissalWhenPresented() async {
    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()
    self.vm.view(isPresented: true)
    self.vm.userSessionStarted()

    self.dismissViewController.assertValueCount(1)
  }

  func testShowAppleErrorAlert_DoesNotEmitWhen_CancellingSignInWithAppleModal() async {
    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.vm.appleAuthorizationDidFail(with: .canceled)

    self.showAppleErrorAlert.assertDidNotEmitValue()
  }

  func testShowAppleErrorAlert_AppleAuthorizationError() async {
    let error = NSError(
      domain: "notonlinesorry", code: -1_234, userInfo: [NSLocalizedDescriptionKey: "Not online sorry"]
    )

    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.vm.appleAuthorizationDidFail(with: .other(error))

    self.showAppleErrorAlert.assertValue("Not online sorry")
  }

  func testShowAppleErrorAlert_SignInWithAppleMutationError() async {
    await withEnvironment(apiService: MockService(signInWithAppleResult: .failure(.couldNotParseJSON))) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      let data = SignInWithAppleData(
        appId: "com.kickstarter.test",
        firstName: "Nino",
        lastName: "Teixeira",
        token: "apple_auth_token"
      )

      self.isLoading.assertDidNotEmitValue()
      self.showAppleErrorAlert.assertDidNotEmitValue()

      self.vm.appleAuthorizationDidSucceed(with: data)

      self.isLoading.assertValues([true])
      await self.vm.waitForApple()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.showAppleErrorAlert.assertValue("Something went wrong.")
    }
  }

  func testShowAppleErrorAlert_FetchUserEventError() async {
    let envelope = SignInWithAppleEnvelope.template
      |> \.signInWithApple.apiAccessToken .~ "some_token"

    await withEnvironment(apiService: MockService(
      fetchUserResult: .failure(.couldNotParseJSON),
      signInWithAppleResult: .success(envelope)
    )) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      let data = SignInWithAppleData(
        appId: "com.kickstarter.test",
        firstName: "Nino",
        lastName: "Teixeira",
        token: "apple_auth_token"
      )

      self.isLoading.assertDidNotEmitValue()
      self.showAppleErrorAlert.assertDidNotEmitValue()

      self.vm.appleAuthorizationDidSucceed(with: data)

      self.isLoading.assertValues([true])
      await self.vm.waitForApple()
      await self.scheduler.advance()

      self.isLoading.assertValues([true, false])
      self.showAppleErrorAlert.assertValue(
        "Something went wrong."
      )
    }
  }

  func testLogIntoEnvironment_SignInWithApple() async {
    let user = User.template

    let envelope = SignInWithAppleEnvelope.template
      |> \.signInWithApple.apiAccessToken .~ "some_token"

    let service = MockService(fetchUserResult: .success(user), signInWithAppleResult: .success(envelope))

    await withEnvironment(apiService: service) {
      self.vm.configureWith(.generic)
      self.vm.viewWillAppear()

      let data = SignInWithAppleData(
        appId: "com.kickstarter.test",
        firstName: "Nino",
        lastName: "Teixeira",
        token: "apple_auth_token"
      )

      self.isLoading.assertDidNotEmitValue()
      self.logIntoEnvironmentWithApple.assertDidNotEmitValue()

      self.vm.appleAuthorizationDidSucceed(with: data)

      self.isLoading.assertValues([true])
      await self.vm.waitForApple()
      await self.scheduler.run()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironmentWithApple.assertValueCount(1)

      let value = self.logIntoEnvironmentWithApple.values.first

      XCTAssertEqual(user, value?.user)
      XCTAssertEqual("some_token", value?.accessToken)
    }
  }

  func testAttemptAppleLogin_Tracking() async {
    self.vm.configureWith(.generic)
    self.vm.viewWillAppear()

    self.attemptAppleLogin.assertDidNotEmitValue()

    self.vm.appleLoginButtonPressed()

    self.attemptAppleLogin.assertValueCount(1)
  }
}
