@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class FacebookResetPasswordViewModelTests: TestCase {
  // Logic-only coverage; visual suites retain their reference-device requirement.
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let authenticationFeature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: FacebookResetPasswordViewModelType =
    FacebookResetPasswordViewModel(authenticationFeature: self.authenticationFeature)

  internal let emailLabel = TestObserver<String, Never>()
  internal let contextLabelText = TestObserver<String, Never>()
  internal let setPasswordButtonIsEnabled = TestObserver<Bool, Never>()
  internal let setPasswordSuccess = TestObserver<String, Never>()
  internal let setPasswordFailure = TestObserver<String, Never>()
  internal let shouldShowActivityIndicator = TestObserver<Bool, Never>()
  internal let textFieldAndSetPasswordButtonAreEnabled = TestObserver<Bool, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  override func tearDown() async throws {
    await self.authenticationFeature.waitForOperations()
    try await super.tearDown()
  }

  private func bindOutputs() {
    self.vm.outputs.contextLabelText.observe(self.contextLabelText.observer)
    self.vm.outputs.emailLabel.observe(self.emailLabel.observer)
    self.vm.outputs.setPasswordButtonIsEnabled.observe(self.setPasswordButtonIsEnabled.observer)
    self.vm.outputs.setPasswordSuccess.observe(self.setPasswordSuccess.observer)
    self.vm.outputs.setPasswordFailure.observe(self.setPasswordFailure.observer)
    self.vm.outputs.shouldShowActivityIndicator.observe(self.shouldShowActivityIndicator.observer)
    self.vm.outputs.textFieldAndSetPasswordButtonAreEnabled
      .observe(self.textFieldAndSetPasswordButtonAreEnabled.observer)
  }

  func testTextLabelsSet_onSetUp() async {
    self.vm.inputs.viewWillAppear()

    self.contextLabelText.assertValue(Strings.We_re_simplifying_our_login_process_To_log_in())
    self.emailLabel.assertValue(Strings.forgot_password_placeholder_email())
  }

  func testSetPasswordButtonIsEnabled() async {
    self.setPasswordButtonIsEnabled.assertDidNotEmitValue("Button is valid did not emit any values")

    self.vm.inputs.viewDidLoad()

    self.setPasswordButtonIsEnabled.assertValues([], "Button is valid did not emit any values")

    self.vm.inputs.emailTextFieldFieldDidChange("bad")

    self.setPasswordButtonIsEnabled.assertValues([false])

    self.vm.inputs.emailTextFieldFieldDidChange("user@example.com")

    self.setPasswordButtonIsEnabled.assertValues([false, true])
  }

  func testResetSuccessValues_EnabledTextFieldsAndLoadingIndicator() async {
    await withEnvironment(apiService: MockService(resetPasswordResponse: .template)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailTextFieldFieldDidChange("user@example.com")

      self.shouldShowActivityIndicator.assertValues([])
      self.textFieldAndSetPasswordButtonAreEnabled.assertValues([])

      self.vm.inputs.setPasswordButtonPressed()

      await self.authenticationFeature.waitForOperations()

      self.setPasswordSuccess.assertValues(
        [
          Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(
            email: "user@example.com"
          )
        ]
      )

      self.textFieldAndSetPasswordButtonAreEnabled.assertValues([false, true])
      self.shouldShowActivityIndicator.assertValues([true, false])
    }
  }

  func testResetSuccessWhenTextFieldReturnsAndFormIsValid() async {
    let testEmail = "test@email.com"

    await withEnvironment(apiService: MockService(resetPasswordResponse: .template)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailTextFieldFieldDidChange(testEmail)

      self.shouldShowActivityIndicator.assertValues([])

      self.vm.inputs.emailTextFieldFieldDidReturn()

      await self.authenticationFeature.waitForOperations()

      self.shouldShowActivityIndicator.assertValues([true, false])

      self.setPasswordSuccess.assertValues(
        [Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(
          email: testEmail
        )]
      )
    }
  }

  func testResetDoesNotEmitWhenTextFieldReturnsAndFormIsNotValid() async {
    let testEmail = "bad@email"

    await withEnvironment(apiService: MockService(resetPasswordError: ErrorEnvelope.couldNotParseJSON)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailTextFieldFieldDidChange(testEmail)

      self.shouldShowActivityIndicator.assertValues([])

      self.vm.inputs.emailTextFieldFieldDidReturn()

      await self.authenticationFeature.waitForOperations()

      self.shouldShowActivityIndicator.assertValues([])

      self.setPasswordSuccess.assertValues([])
      self.setPasswordFailure.assertValues([])
    }
  }

  func testResetFail_WithUnknownEmail() async {
    let error = ErrorEnvelope(
      errorMessages: ["The resource you are looking for does not exist."],
      ksrCode: nil,
      httpCode: 404,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resetPasswordError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailTextFieldFieldDidChange("test@email.com")
      self.shouldShowActivityIndicator.assertValues([])

      self.vm.inputs.setPasswordButtonPressed()

      await self.authenticationFeature.waitForOperations()

      self.setPasswordFailure.assertValues(
        [error.errorMessages.last ?? Strings.general_error_something_wrong()],
        "Error alert is shown on bad request"
      )
    }
  }

  func testResetFail_WithNon404Error() async {
    let error = ErrorEnvelope(
      errorMessages: ["Zoinks!"],
      ksrCode: nil,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(resetPasswordError: error)) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailTextFieldFieldDidChange("test@email.com")

      self.shouldShowActivityIndicator.assertValues([])

      self.vm.inputs.setPasswordButtonPressed()

      await self.authenticationFeature.waitForOperations()

      self.setPasswordFailure
        .assertValues(
          [error.errorMessages.last ?? Strings.general_error_something_wrong()],
          "Error alert is shown on bad request"
        )

      self.shouldShowActivityIndicator.assertValues([true, false])
    }
  }
}
