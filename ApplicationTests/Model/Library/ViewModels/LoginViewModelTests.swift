@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class LoginViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let authenticationFeature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: LoginViewModel = LoginViewModel(authenticationFeature: self.authenticationFeature)
  fileprivate let emailTextFieldBecomeFirstResponder = LoginRecorder<Void>()
  fileprivate let passwordTextFieldBecomeFirstResponder = LoginRecorder<Void>()
  fileprivate let isFormValid = LoginRecorder<Bool>()
  fileprivate let dismissKeyboard = LoginRecorder<Void>()
  fileprivate let postNotificationName = LoginRecorder<(Notification.Name, Notification.Name)>()
  fileprivate let logIntoEnvironment = LoginRecorder<AccessTokenEnvelope>()
  fileprivate let showError = LoginRecorder<String>()
  fileprivate let tfaChallenge = LoginRecorder<String>()
  fileprivate let tfaChallengePasswordText = LoginRecorder<String>()
  fileprivate let showHidePassword = LoginRecorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.vm.waitForLogin()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onEmailFirstResponder = { [weak self] in self?.emailTextFieldBecomeFirstResponder.values.append(()) }
    self.vm.onPasswordFirstResponder = { [weak self] in self?.passwordTextFieldBecomeFirstResponder.values.append(()) }
    self.vm.onFormValid = { [weak self] in self?.isFormValid.values.append($0) }
    self.vm.onDismissKeyboard = { [weak self] in self?.dismissKeyboard.values.append(()) }
    self.vm.onNotification = { [weak self] in self?.postNotificationName.values.append(($0.name, $1.name)) }
    self.vm.onLogin = { [weak self] in self?.logIntoEnvironment.values.append($0) }
    self.vm.onError = { [weak self] in self?.showError.values.append($0) }
    self.vm.onTwoFactor = { [weak self] email, password in
      self?.tfaChallenge.values.append(email)
      self?.tfaChallengePasswordText.values.append(password)
    }
    self.vm.onPasswordVisibility = { [weak self] in self?.showHidePassword.values.append($0) }
  }

  func testLoginFlow() async {
    self.vm.viewWillAppear()
    self.vm.viewDidLoad()

    XCTAssertEqual(["Page Viewed"], self.segmentTrackingClient.events)

    self.emailTextFieldBecomeFirstResponder
      .assertValueCount(1, "Email field is first responder when view loads.")

    self.isFormValid.assertValues([false], "Form is not valid")

    self.vm.emailChanged("puppies@rule.com")
    self.isFormValid.assertValues([false], "Form is not valid")

    self.vm.emailTextFieldDoneEditing()
    self.passwordTextFieldBecomeFirstResponder
      .assertValueCount(1, "Password textfield becomes first responder when done editing email.")
    self.emailTextFieldBecomeFirstResponder
      .assertValueCount(1, "Does not emit again.")

    self.vm.passwordChanged("hello")
    self.isFormValid.assertValues([false, true], "Form is valid")

    self.vm.passwordTextFieldDoneEditing()
    await self.vm.waitForLogin()

    XCTAssertEqual(["Page Viewed", "CTA Clicked"], self.segmentTrackingClient.events)

    self.dismissKeyboard.assertValueCount(1, "Keyboard is dismissed")
    self.logIntoEnvironment
      .assertValueCount(
        1,
        "Log into environment without showing email verification because feature flag is false (not set)."
      )

    self.vm.environmentLoggedIn()
    XCTAssertEqual(
      self.postNotificationName.values.first?.0, .ksr_sessionStarted,
      "Login notification posted."
    )
    XCTAssertEqual(
      self.postNotificationName.values.first?.1, .ksr_showNotificationsDialog,
      "Contextual Dialog notification posted."
    )

    self.showError.assertValueCount(0, "Error did not happen")
    self.tfaChallenge.assertValueCount(0, "TFA challenge did not happen")
  }

  func testBecomefirstResponder() async {
    self.vm.viewDidLoad()
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Email starts as first responder.")
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder yet.")

    self.vm.emailTextFieldDoneEditing()
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "Password becomes first responder.")

    self.vm.passwordTextFieldDoneEditing()
    await self.vm.waitForLogin()
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
  }

  func testLoginError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to log in."],
      ksrCode: .InvalidXauthLogin,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.emailChanged("user@example.com")
      self.vm.passwordChanged("helloooooo")
      self.vm.loginButtonPressed()
      await self.vm.waitForLogin()

      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")

      self.showError.assertValues(["Unable to log in."], "Login errored")
      self.tfaChallenge.assertValueCount(0, "TFA challenge did not happen")
    }
  }

  func testLoginError_WithNoErrorMessage() async {
    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: .InvalidXauthLogin,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.emailChanged("user@example.com")
      self.vm.passwordChanged("helloooooo")
      self.vm.loginButtonPressed()
      await self.vm.waitForLogin()

      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")

      self.showError.assertValues([Strings.login_errors_unable_to_log_in()], "Login errored")
      self.tfaChallenge.assertValueCount(0, "TFA challenge did not happen")
    }
  }

  func testTfaChallenge() async {
    let error = ErrorEnvelope(
      errorMessages: ["Two Factor Authenticaion is required."],
      ksrCode: .TfaRequired,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.emailChanged("user@example.com")
      self.vm.passwordChanged("helloooooo")
      self.vm.loginButtonPressed()
      await self.vm.waitForLogin()

      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")

      self.showError.assertValueCount(0, "Login error did not happen")
      self.tfaChallenge.assertValues(
        ["user@example.com"],
        "Two factor challenge emitted with email and password"
      )
      self.tfaChallengePasswordText.assertValues(["helloooooo"], "Two factor challenge emitted with password")
    }
  }

  func testShowPassword() async {
    self.vm.viewWillAppear()
    self.vm.viewDidLoad()
    self.vm.showHidePasswordButtonTapped()

    self.showHidePassword.assertValue(true)
  }

  func testHidePassword() async {
    self.vm.viewWillAppear()
    self.vm.viewDidLoad()
    self.vm.showHidePasswordButtonTapped()
    self.showHidePassword.assertValue(true, "Password is shown")

    self.vm.showHidePasswordButtonTapped()
    self.showHidePassword.assertValueCount(2)
    self.showHidePassword.assertLastValue(false, "Password not shown")
  }

  func testShowPasswordForTraitCollectionDidChange() async {
    self.vm.viewWillAppear()
    self.vm.viewDidLoad()
    self.vm.showHidePasswordButtonTapped()
    self.showHidePassword.assertValue(true, "Password is shown")

    self.vm.traitCollectionDidChange()
    self.showHidePassword.assertValueCount(2)
    self.showHidePassword.assertLastValue(true, "Password still shown")
  }
}

private final class LoginRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension LoginRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, [expected], message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}
