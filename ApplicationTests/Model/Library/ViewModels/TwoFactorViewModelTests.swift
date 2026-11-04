@testable import Kickstarter_iOS
@testable import KsApi


import XCTest

@MainActor
final class TwoFactorViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let authenticationFeature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: TwoFactorViewModel = TwoFactorViewModel(
    authenticationFeature: self
      .authenticationFeature
  )
  private var codeTextFieldBecomeFirstResponder = TwoFactorRecorder<Void>()
  private var isFormValid = TwoFactorRecorder<Bool>()
  private var isLoading = TwoFactorRecorder<Bool>()
  private var logIntoEnvironment = TwoFactorRecorder<AccessTokenEnvelope>()
  private var postNotificationName = TwoFactorRecorder<(Notification.Name, Notification.Name)>()
  private var resendSuccess = TwoFactorRecorder<Void>()
  private var showError = TwoFactorRecorder<String>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.vm.waitForRequests()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.onFirstResponder = { [weak self] in self?.codeTextFieldBecomeFirstResponder.values.append(()) }
    self.vm.onFormValid = { [weak self] in self?.isFormValid.values.append($0) }
    self.vm.onLoading = { [weak self] in self?.isLoading.values.append($0) }
    self.vm.onLogin = { [weak self] in self?.logIntoEnvironment.values.append($0) }
    self.vm.onNotification = { [weak self] in self?.postNotificationName.values.append(($0.name, $1.name)) }
    self.vm.onResendSuccess = { [weak self] in self?.resendSuccess.values.append(()) }
    self.vm.onError = { [weak self] in self?.showError.values.append($0) }
  }

  func testCodeTextFieldBecomesFirstResponder() async {
    self.vm.viewDidLoad()
    self.codeTextFieldBecomeFirstResponder.assertValueCount(1)
  }

  func testFormIsValid_forEmailPasswordFlow() async {
    self.vm.viewWillAppear()

    self.isFormValid.assertValues([false])

    self.vm.email("user@example.com", password: "password")

    self.isFormValid.assertValues([false])

    self.vm.codeChanged("8")

    self.isFormValid.assertValues([false])

    self.vm.codeChanged("888888")

    self.isFormValid.assertValues([false, true])

    self.vm.codeChanged("88888")

    self.isFormValid.assertValues([false, true, false])
  }

  func testFormIsValid_forFacebookFlow() async {
    self.vm.viewWillAppear()

    self.isFormValid.assertValues([false])

    self.vm.facebookToken("token")

    self.isFormValid.assertValues([false])

    self.vm.codeChanged("8")

    self.isFormValid.assertValues([false])

    self.vm.codeChanged("888888")

    self.isFormValid.assertValues([false, true])

    self.vm.codeChanged("88888")

    self.isFormValid.assertValues([false, true, false])
  }

  func testLogin_withEmailPasswordFlow() async {
    self.vm.viewWillAppear()
    self.vm.email("user@example.com", password: "password")
    self.vm.codeChanged("454545")
    self.vm.submitPressed()
    await self.vm.waitForRequests()

    self.isLoading.assertValues([true, false])
    self.logIntoEnvironment.assertValueCount(1, "Log into environment.")

    self.vm.environmentLoggedIn()

    XCTAssertEqual(
      self.postNotificationName.values.first?.0, .ksr_sessionStarted,
      "Login notification posted."
    )
    XCTAssertEqual(
      self.postNotificationName.values.first?.1, .ksr_showNotificationsDialog,
      "Contextual dialog notification posted."
    )
  }

  func testLogin_withFacebookFlow() async {
    self.vm.viewWillAppear()
    self.vm.facebookToken("token")
    self.vm.codeChanged("454545")

    self.vm.submitPressed()
    await self.vm.waitForRequests()

    self.isLoading.assertValues([true, false])
    self.logIntoEnvironment.assertValueCount(1, "Log into environment.")

    self.vm.environmentLoggedIn()

    XCTAssertEqual(
      self.postNotificationName.values.first?.0, .ksr_sessionStarted,
      "Login notification posted."
    )
    XCTAssertEqual(
      self.postNotificationName.values.first?.1, .ksr_showNotificationsDialog,
      "Contextual dialog notification posted."
    )
  }

  func testLoginCodeMismatch_withEmailPasswordFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["The code provided does not match."],
      ksrCode: .TfaFailed,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.email("user@example.com", password: "password")
      self.vm.codeChanged("454545")
      self.vm.submitPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")
      self.showError.assertValues(["The code provided does not match."], "Code does not match error emitted")
    }
  }

  func testLoginCodeMismatch_withFacebookFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["The code provided does not match."],
      ksrCode: .TfaFailed,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.facebookToken("token")
      self.vm.codeChanged("454545")
      self.vm.submitPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")
      self.showError.assertValues(["The code provided does not match."], "Code does not match error emitted")
    }
  }

  func testLoginGenericFail_withEmailPasswordFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to login."],
      ksrCode: .UnknownCode,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.email("user@example.com", password: "password")
      self.vm.codeChanged("454545")
      self.vm.submitPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")
      self.showError.assertValues(["Unable to login."], "Login errored")
    }
  }

  func testLoginGenericFail_withFacebookFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to login."],
      ksrCode: .UnknownCode,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(loginError: error)) {
      self.vm.viewWillAppear()
      self.vm.facebookToken("token")
      self.vm.codeChanged("454545")
      self.vm.submitPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")
      self.showError.assertValues(["Unable to login."], "Errored user login")
    }
  }

  func testResend_withEmailPasswordFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["Two-factor authentication is enabled on this account."],
      ksrCode: .TfaRequired,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resendCodeResponse: error)) {
      self.vm.viewWillAppear()
      self.vm.email("user@example.com", password: "password")
      self.vm.resendPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.showError.assertValueCount(0, "No error was emitted")
      self.resendSuccess.assertValueCount(1, "Code resent successfully")
    }
  }

  func testResend_withFacebookFlow() async {
    let error = ErrorEnvelope(
      errorMessages: ["Two-factor authentication is enabled on this account."],
      ksrCode: .TfaRequired,
      httpCode: 403,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resendCodeResponse: error)) {
      self.vm.viewWillAppear()
      self.vm.facebookToken("token")
      self.vm.resendPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.showError.assertValueCount(0, "No error was emitted")
      self.resendSuccess.assertValueCount(1, "Code resent successfully")
    }
  }

  func testResendError_withEmailPasswordFlow() async {
    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resendCodeError: error)) {
      self.vm.viewWillAppear()
      self.vm.email("user@example.com", password: "password")
      self.vm.resendPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.showError.assertValueCount(0, "No error was emitted")
      self.resendSuccess.assertValueCount(0, "Code was not resent")
    }
  }

  func testResendError_withFacebookFlow() async {
    let error = ErrorEnvelope(
      errorMessages: [],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resendCodeError: error)) {
      self.vm.viewWillAppear()
      self.vm.facebookToken("token")
      self.vm.resendPressed()
      await self.vm.waitForRequests()

      self.isLoading.assertValues([true, false])
      self.showError.assertValueCount(0, "No error was emitted")
      self.resendSuccess.assertValueCount(0, "Code was not resent")
    }
  }
}

private final class TwoFactorRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension TwoFactorRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
