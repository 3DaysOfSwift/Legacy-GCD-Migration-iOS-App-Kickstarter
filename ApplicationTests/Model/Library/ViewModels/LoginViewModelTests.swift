@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
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
  fileprivate let emailTextFieldBecomeFirstResponder = TestObserver<(), Never>()
  fileprivate let passwordTextFieldBecomeFirstResponder = TestObserver<(), Never>()
  fileprivate let isFormValid = TestObserver<Bool, Never>()
  fileprivate let dismissKeyboard = TestObserver<(), Never>()
  fileprivate let postNotificationName = TestObserver<(Notification.Name, Notification.Name), Never>()
  fileprivate let logIntoEnvironment = TestObserver<AccessTokenEnvelope, Never>()
  fileprivate let showError = TestObserver<String, Never>()
  fileprivate let tfaChallenge = TestObserver<String, Never>()
  fileprivate let tfaChallengePasswordText = TestObserver<String, Never>()
  fileprivate let showHidePassword = TestObserver<Bool, Never>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.vm.waitForLogin()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onEmailFirstResponder = { [weak self] in self?.emailTextFieldBecomeFirstResponder.observer.send(value: ()) }
    self.vm.onPasswordFirstResponder = { [weak self] in self?.passwordTextFieldBecomeFirstResponder.observer.send(value: ()) }
    self.vm.onFormValid = { [weak self] in self?.isFormValid.observer.send(value: $0) }
    self.vm.onDismissKeyboard = { [weak self] in self?.dismissKeyboard.observer.send(value: ()) }
    self.vm.onNotification = { [weak self] in self?.postNotificationName.observer.send(value: ($0.name, $1.name)) }
    self.vm.onLogin = { [weak self] in self?.logIntoEnvironment.observer.send(value: $0) }
    self.vm.onError = { [weak self] in self?.showError.observer.send(value: $0) }
    self.vm.onTwoFactor = { [weak self] email, password in
      self?.tfaChallenge.observer.send(value: email)
      self?.tfaChallengePasswordText.observer.send(value: password)
    }
    self.vm.onPasswordVisibility = { [weak self] in self?.showHidePassword.observer.send(value: $0) }
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
