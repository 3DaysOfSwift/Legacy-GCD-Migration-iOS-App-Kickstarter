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
final class ChangeEmailViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm: ChangeEmailViewModelType = ChangeEmailViewModel(settingsFeature: self.feature)
  fileprivate let fetchUserQueryData = GraphUserEnvelopeTemplates.fetchUser
  private let activityIndicatorShouldShow = TestObserver<Bool, Never>()
  private let didChangeEmail = TestObserver<Void, Never>()
  private let didFailToChangeEmail = TestObserver<String, Never>()
  private let didFailToSendVerificationEmail = TestObserver<String, Never>()
  private let didSendVerificationEmail = TestObserver<Void, Never>()
  private let dismissKeyboard = TestObserver<(), Never>()
  private let emailText = TestObserver<String, Never>()
  private let messageLabelViewHidden = TestObserver<Bool, Never>()
  private let passwordFieldBecomeFirstResponder = TestObserver<Void, Never>()
  private let passwordText = TestObserver<String, Never>()
  private let resendVerificationEmailViewIsHidden = TestObserver<Bool, Never>()
  private let resetFields = TestObserver<String, Never>()
  private let saveButtonIsEnabled = TestObserver<Bool, Never>()
  private let textFieldsAreEnabled = TestObserver<Bool, Never>()
  private let unverifiedEmailLabelHidden = TestObserver<Bool, Never>()
  private let warningMessageLabelHidden = TestObserver<Bool, Never>()
  private let verificationEmailButtonTitle = TestObserver<String, Never>()

  // MARK: Computed Properties

  private var userChangeEmailSuccessMockService: MockService {
    guard let envelope = UserEnvelope<GraphUser>.userEnvelope(from: fetchUserQueryData) else {
      return MockService()
    }

    let mockService = MockService(
      changeEmailResult: .success(EmptyResponseEnvelope()),
      fetchGraphUserResult: .success(envelope)
    )

    return mockService
  }

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))

      self.vm.outputs.activityIndicatorShouldShow.observe(self.activityIndicatorShouldShow.observer)
      self.vm.outputs.didChangeEmail.observe(self.didChangeEmail.observer)
      self.vm.outputs.didFailToChangeEmail.observe(self.didFailToChangeEmail.observer)
      self.vm.outputs.emailText.observe(self.emailText.observer)
      self.vm.outputs.dismissKeyboard.observe(self.dismissKeyboard.observer)
      self.vm.outputs.messageLabelViewHidden.observe(self.messageLabelViewHidden.observer)
      self.vm.outputs.passwordFieldBecomeFirstResponder
        .observe(self.passwordFieldBecomeFirstResponder.observer)
      self.vm.outputs.resendVerificationEmailViewIsHidden.observe(
        self.resendVerificationEmailViewIsHidden.observer
      )
      self.vm.outputs.didSendVerificationEmail.observe(
        self.didSendVerificationEmail.observer
      )
      self.vm.outputs.didFailToSendVerificationEmail.observe(
        self.didFailToSendVerificationEmail.observer
      )
      self.vm.outputs.resetFields.observe(self.resetFields.observer)
      self.vm.outputs.saveButtonIsEnabled.observe(self.saveButtonIsEnabled.observer)
      self.vm.outputs.textFieldsAreEnabled.observe(self.textFieldsAreEnabled.observer)
      self.vm.outputs.unverifiedEmailLabelHidden.observe(self.unverifiedEmailLabelHidden.observer)
      self.vm.outputs.warningMessageLabelHidden.observe(self.warningMessageLabelHidden.observer)
      self.vm.outputs.verificationEmailButtonTitle.observe(self.verificationEmailButtonTitle.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testChangeEmail_OnSuccess() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.resendVerificationEmailViewIsHidden.assertValues([true])
      self.unverifiedEmailLabelHidden.assertValues([true])
      self.emailText.assertValues(["user@example.com"])

      self.vm.inputs.emailFieldTextDidChange(text: "example@example.com")
      self.vm.inputs.passwordFieldTextDidChange(text: "123456")

      self.vm.inputs.saveButtonIsEnabled(true)
      self.vm.inputs.saveButtonTapped()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.didChangeEmail.assertDidEmitValue()
      self.emailText.assertValues(["user@example.com", "example@example.com"])
      self.resendVerificationEmailViewIsHidden.assertValues(
        [true],
        "Resend verification email button does not show"
      )
      self.unverifiedEmailLabelHidden.assertValues([true])
    }
  }

  func testDidFailToChangeEmailEmits_OnFailure() async {
    let errorEnvelope = ErrorEnvelope(
      errorMessages: ["error"],
      ksrCode: nil,
      httpCode: 1,
      exception: nil
    )

    await withEnvironment(apiService: MockService(changeEmailResult: .failure(errorEnvelope))) {
      self.vm.inputs.emailFieldTextDidChange(text: "user@example.com")
      self.vm.inputs.passwordFieldTextDidChange(text: "123456")

      self.vm.inputs.saveButtonIsEnabled(true)
      self.vm.inputs.saveButtonTapped()

      self.activityIndicatorShouldShow.assertValues([true])

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.didFailToChangeEmail.assertDidEmitValue()

      self.activityIndicatorShouldShow.assertValues([true, false])
    }
  }

  func testEmailText_AfterFetchingUsersEmail() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.emailText.assertValues(["user@example.com"])
    }
  }

  func testSaveButtonEnabledStatus() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.vm.inputs.emailFieldTextDidChange(text: "red@example.com")
      self.saveButtonIsEnabled.assertDidNotEmitValue()

      self.vm.inputs.passwordFieldTextDidChange(text: "123456")
      self.saveButtonIsEnabled.assertValues([true])

      // Disabled if new email is equal to the old one.
      self.vm.inputs.emailFieldTextDidChange(text: "blue@example.com")
      self.saveButtonIsEnabled.assertValues([true, true])
    }
  }

  func testResendVerificationViewIsHidden_onViewDidLoad_andIfEmailIsVerified() async {
    self.vm.inputs.viewDidLoad()

    await self.feature.waitForOperations()

    await self.scheduler.advance()

    self.resendVerificationEmailViewIsHidden
      .assertValues([true], "Email is deliverable and verified")
  }

  func testResendVerificationViewIsNotHidden_IfEmailIsNotVerified() async {
    let userTemplate = GraphUser.template |> \.isEmailVerified .~ false
    let userEnvelope = UserEnvelope(me: userTemplate)
    let mockService = MockService(fetchGraphUserResult: .success(userEnvelope))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.resendVerificationEmailViewIsHidden.assertValues([true, false], "Email is unverified")
    }
  }

  func testResendVerificationViewIsNotHidden_IfEmailIsUndeliverable() async {
    let userTemplate = GraphUser.template |> \.isDeliverable .~ false
    let userEnvelope = UserEnvelope(me: userTemplate)
    let mockService = MockService(fetchGraphUserResult: .success(userEnvelope))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.resendVerificationEmailViewIsHidden
        .assertValues([true, false], "Email is undeliverable")
    }
  }

  func testWarningMessageLabel_isHidden() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.warningMessageLabelHidden.assertValues([true], "Email is deliverable")
    }
  }

  func testWarningMessageLabel_isNotHidden_whenEmailIsNotDeliverable() async {
    let userTemplate = GraphUser.template |> \.isDeliverable .~ false
    let userEnvelope = UserEnvelope(me: userTemplate)
    let mockService = MockService(fetchGraphUserResult: .success(userEnvelope))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.warningMessageLabelHidden
        .assertValues([false], "Email is not deliverable")
    }
  }

  func testUnverifiedEmailLabel_isHidden_whenEmailIsVerified() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.unverifiedEmailLabelHidden.assertValues([true], "Email is verified & deliverable")
    }
  }

  func testUnverifiedEmailLabel_isNotHidden_whenEmailIsUnverified() async {
    let userTemplate = GraphUser.template |> \.isEmailVerified .~ false
    let userEnvelope = UserEnvelope(me: userTemplate)
    let mockService = MockService(fetchGraphUserResult: .success(userEnvelope))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.unverifiedEmailLabelHidden
        .assertValues([false], "Email is not verified, but deliverable")
    }
  }

  func testUnverifiedEmailLabel_isHidden_whenEmailIsUnverifiedAndUndeliverable() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.viewDidLoad()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.unverifiedEmailLabelHidden
        .assertValues([true], "Email is not verified, but deliverable message takes precendent")
    }
  }

  func testDidFailToSendVerificationEmailEmits_OnFailure() async {
    await withEnvironment(apiService: MockService(
      sendEmailVerificationResult: .failure(.couldNotParseJSON)
    )) {
      self.vm.inputs.resendVerificationEmailButtonTapped()
      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.didFailToSendVerificationEmail.assertValue(ErrorEnvelope.couldNotParseJSON.localizedDescription)
    }
  }

  func testDidSendVerificationEmailEmits_OnSuccess() async {
    await withEnvironment(
      apiService: MockService(sendEmailVerificationResult: .success(EmptyResponseEnvelope()))
    ) {
      self.vm.inputs.resendVerificationEmailButtonTapped()
      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.didSendVerificationEmail.assertDidEmitValue()
    }
  }

  func testVerificationEmailButtonTitle_Backer() async {
    let user = User.template
      |> \.stats.createdProjectsCount .~ 0

    await withEnvironment(currentUser: user) {
      self.vm.inputs.viewDidLoad()

      self.verificationEmailButtonTitle.assertValue(Strings.Send_verfication_email())
    }
  }

  func testVerificationEmailButtonTitle_Creator() async {
    let user = User.template
      |> \.stats.createdProjectsCount .~ 1

    await withEnvironment(currentUser: user) {
      self.vm.inputs.viewDidLoad()

      self.verificationEmailButtonTitle.assertValue(Strings.Resend_verification_email())
    }
  }

  func testDismissKeyboard_OnSuccess() async {
    self.dismissKeyboard.assertDidNotEmitValue()

    self.vm.inputs.emailFieldTextDidChange(text: "new@email.com")
    self.vm.inputs.passwordFieldTextDidChange(text: "123456")

    self.vm.inputs.saveButtonTapped()

    self.dismissKeyboard.assertValueCount(1)

    self.vm.inputs.textFieldShouldReturn(with: .done)
    self.dismissKeyboard.assertValueCount(2)
  }

  func testDismissKeyboard_InvalidEmail() async {
    self.dismissKeyboard.assertDidNotEmitValue()

    self.vm.inputs.emailFieldTextDidChange(text: "new@email.com.")
    self.vm.inputs.passwordFieldTextDidChange(text: "123456")

    self.vm.inputs.saveButtonIsEnabled(false)
    self.vm.inputs.textFieldShouldReturn(with: .done)

    self.dismissKeyboard.assertValueCount(1)
    self.didChangeEmail.assertDidNotEmitValue()
  }

  func testPasswordFieldBecomeFirstResponder_WhenTappingNext() async {
    self.vm.inputs.viewDidLoad()
    self.passwordFieldBecomeFirstResponder.assertValueCount(0)

    self.vm.inputs.textFieldShouldReturn(with: .done)
    self.passwordFieldBecomeFirstResponder.assertValueCount(0)

    self.vm.inputs.textFieldShouldReturn(with: .next)
    self.passwordFieldBecomeFirstResponder.assertValueCount(1)
  }

  func testFieldsResetWithEmptyString_AfterChangingEmail() async {
    await withEnvironment(apiService: self.userChangeEmailSuccessMockService) {
      self.vm.inputs.emailFieldTextDidChange(text: "user@example.com")
      self.vm.inputs.passwordFieldTextDidChange(text: "123456")
      self.vm.inputs.saveButtonIsEnabled(true)

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.vm.inputs.emailFieldTextDidChange(text: "user@example.com")
      self.vm.inputs.passwordFieldTextDidChange(text: "123456")
      self.vm.inputs.saveButtonIsEnabled(true)

      self.vm.inputs.saveButtonTapped()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.resetFields.assertValue("")
    }
  }

  func testTextFieldsAreEnabled() async {
    self.vm.inputs.emailFieldTextDidChange(text: "user@example.com")
    self.vm.inputs.passwordFieldTextDidChange(text: "123456")

    self.vm.inputs.saveButtonIsEnabled(true)
    self.vm.inputs.saveButtonTapped()

    self.textFieldsAreEnabled.assertValues([false])

    await self.feature.waitForOperations()

    await self.scheduler.advance()

    self.textFieldsAreEnabled.assertValues([false, true])
  }
}
