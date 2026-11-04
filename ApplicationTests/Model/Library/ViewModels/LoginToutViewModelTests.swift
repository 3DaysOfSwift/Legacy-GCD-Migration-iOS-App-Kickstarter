@testable import Kickstarter_iOS
@testable import FacebookLogin
@testable import KsApi


import Prelude
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

  fileprivate let attemptAppleLogin = SocialLoginRecorder<Void>()
  fileprivate let attemptFacebookLogin = SocialLoginRecorder<Void>()
  fileprivate let didSignInWithApple = SocialLoginRecorder<SignInWithAppleEnvelope>()
  fileprivate let dismissViewController = SocialLoginRecorder<Void>()
  fileprivate let headlineLabelHidden = SocialLoginRecorder<Bool>()
  fileprivate let isLoading = SocialLoginRecorder<Bool>()
  fileprivate let logInContextText = SocialLoginRecorder<String>()
  fileprivate let logIntoEnvironmentWithApple = SocialLoginRecorder<AccessTokenEnvelope>()
  fileprivate let logIntoEnvironmentWithFacebook = SocialLoginRecorder<AccessTokenEnvelope>()
  fileprivate let postNotification = SocialLoginRecorder<(Notification.Name, Notification.Name)>()
  fileprivate let showAppleErrorAlert = SocialLoginRecorder<String>()
  fileprivate let showFacebookErrorAlert = SocialLoginRecorder<AlertError>()
  fileprivate let startFacebookConfirmation = SocialLoginRecorder<String>()
  fileprivate let startOAuthSignupOrLogin = SocialLoginRecorder<Void>()
  fileprivate let startTwoFactorChallenge = SocialLoginRecorder<String>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.vm.waitForFacebook()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onAppleLogin = { [weak self] in self?.attemptAppleLogin.values.append(()) }
    self.vm.onFacebookLogin = { [weak self] in self?.attemptFacebookLogin.values.append(()) }
    self.vm.onDismiss = { [weak self] in self?.dismissViewController.values.append(()) }
    self.vm.onOAuth = { [weak self] in self?.startOAuthSignupOrLogin.values.append(()) }
    self.vm.onContext = { [weak self] text, hidden in
      self?.logInContextText.values.append(text)
      self?.headlineLabelHidden.values.append(hidden)
    }
    self.vm.onLoading = { [weak self] in self?.isLoading.values.append($0) }
    self.vm.onAppleSuccess = { [weak self] in self?.logIntoEnvironmentWithApple.values.append($0) }
    self.vm.onFacebookSuccess = { [weak self] in self?.logIntoEnvironmentWithFacebook.values.append($0) }
    self.vm.onNotification = { [weak self] in self?.postNotification.values.append(($0.name, $1.name)) }
    self.vm.onAppleError = { [weak self] in self?.showAppleErrorAlert.values.append($0) }
    self.vm.onFacebookError = { [weak self] in self?.showFacebookErrorAlert.values.append($0) }
    self.vm.onFacebookConfirmation = { [weak self] _, token in self?.startFacebookConfirmation.values.append(token) }
    self.vm.onFacebookTwoFactor = { [weak self] in self?.startTwoFactorChallenge.values.append($0) }
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

private final class SocialLoginRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension SocialLoginRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, [expected], message, file: file, line: line)
  }
}
