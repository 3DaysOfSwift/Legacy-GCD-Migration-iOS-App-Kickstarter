@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
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
  private lazy var vm: LoginViewModelType = LoginViewModel(authenticationFeature: self.authenticationFeature)
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

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.authenticationFeature.waitForOperations()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.outputs.emailTextFieldBecomeFirstResponder
      .observe(self.emailTextFieldBecomeFirstResponder.observer)
    self.vm.outputs.passwordTextFieldBecomeFirstResponder
      .observe(self.passwordTextFieldBecomeFirstResponder.observer)
    self.vm.outputs.isFormValid.observe(self.isFormValid.observer)
    self.vm.outputs.dismissKeyboard.observe(self.dismissKeyboard.observer)
    self.vm.outputs.postNotification.map { ($0.0.name, $0.1.name) }
      .observe(self.postNotificationName.observer)
    self.vm.outputs.logIntoEnvironment.observe(self.logIntoEnvironment.observer)
    self.vm.outputs.showError.observe(self.showError.observer)
    self.vm.outputs.tfaChallenge.map { $0.email }.observe(self.tfaChallenge.observer)
    self.vm.outputs.tfaChallenge.map { $0.password }.observe(self.tfaChallengePasswordText.observer)
    self.vm.outputs.showHidePasswordButtonToggled.observe(self.showHidePassword.observer)
  }

  func testLoginFlow() async {
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidLoad()

    XCTAssertEqual(["Page Viewed"], self.segmentTrackingClient.events)

    self.emailTextFieldBecomeFirstResponder
      .assertValueCount(1, "Email field is first responder when view loads.")

    self.isFormValid.assertValues([false], "Form is not valid")

    self.vm.inputs.emailChanged("puppies@rule.com")
    self.isFormValid.assertValues([false], "Form is not valid")

    self.vm.inputs.emailTextFieldDoneEditing()
    self.passwordTextFieldBecomeFirstResponder
      .assertValueCount(1, "Password textfield becomes first responder when done editing email.")
    self.emailTextFieldBecomeFirstResponder
      .assertValueCount(1, "Does not emit again.")

    self.vm.inputs.passwordChanged("hello")
    self.isFormValid.assertValues([false, true], "Form is valid")

    self.vm.inputs.passwordTextFieldDoneEditing()
    await self.authenticationFeature.waitForOperations()

    XCTAssertEqual(["Page Viewed", "CTA Clicked"], self.segmentTrackingClient.events)

    self.dismissKeyboard.assertValueCount(1, "Keyboard is dismissed")
    self.logIntoEnvironment
      .assertValueCount(
        1,
        "Log into environment without showing email verification because feature flag is false (not set)."
      )

    self.vm.inputs.environmentLoggedIn()
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
    self.vm.inputs.viewDidLoad()
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Email starts as first responder.")
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder yet.")

    self.vm.inputs.emailTextFieldDoneEditing()
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "Password becomes first responder.")

    self.vm.inputs.passwordTextFieldDoneEditing()
    await self.authenticationFeature.waitForOperations()
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
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.emailChanged("user@example.com")
      self.vm.inputs.passwordChanged("helloooooo")
      self.vm.inputs.loginButtonPressed()
      await self.authenticationFeature.waitForOperations()

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
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.emailChanged("user@example.com")
      self.vm.inputs.passwordChanged("helloooooo")
      self.vm.inputs.loginButtonPressed()
      await self.authenticationFeature.waitForOperations()

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
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.emailChanged("user@example.com")
      self.vm.inputs.passwordChanged("helloooooo")
      self.vm.inputs.loginButtonPressed()
      await self.authenticationFeature.waitForOperations()

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
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.showHidePasswordButtonTapped()

    self.showHidePassword.assertValue(true)
  }

  func testHidePassword() async {
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.showHidePasswordButtonTapped()
    self.showHidePassword.assertValue(true, "Password is shown")

    self.vm.inputs.showHidePasswordButtonTapped()
    self.showHidePassword.assertValueCount(2)
    self.showHidePassword.assertLastValue(false, "Password not shown")
  }

  func testShowPasswordForTraitCollectionDidChange() async {
    self.vm.inputs.viewWillAppear()
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.showHidePasswordButtonTapped()
    self.showHidePassword.assertValue(true, "Password is shown")

    self.vm.inputs.traitCollectionDidChange()
    self.showHidePassword.assertValueCount(2)
    self.showHidePassword.assertLastValue(true, "Password still shown")
  }
}
