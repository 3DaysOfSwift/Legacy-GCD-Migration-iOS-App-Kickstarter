@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class CreatePasswordViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = CreatePasswordViewModel(settingsFeature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture", user: .template))
  }

  func testValidationAndFocusActions() {
    var focusPassword = 0
    var focusConfirmation = 0
    var dismiss = 0
    self.vm.onFocusPassword = { focusPassword += 1 }
    self.vm.onFocusConfirmation = { focusConfirmation += 1 }
    self.vm.onDismissKeyboard = { dismiss += 1 }
    self.vm.viewDidAppear()
    self.vm.newPasswordTextFieldChanged(text: "short")
    XCTAssertEqual(self.vm.validationLabelText, Strings.Password_min_length_message())
    self.vm.newPasswordTextFieldChanged(text: "longpassword")
    self.vm.newPasswordConfirmationTextFieldChanged(text: "different")
    XCTAssertEqual(self.vm.validationLabelText, Strings.Passwords_matching_message())
    XCTAssertFalse(self.vm.saveButtonIsEnabled)
    self.vm.newPasswordConfirmationTextFieldChanged(text: "longpassword")
    XCTAssertTrue(self.vm.saveButtonIsEnabled)
    XCTAssertNil(self.vm.validationLabelText)
    self.vm.newPasswordTextFieldDidReturn()
    XCTAssertEqual(focusPassword, 1)
    XCTAssertEqual(focusConfirmation, 1)
    self.vm.newPasswordConfirmationTextFieldChanged(text: "")
    self.vm.saveButtonTapped()
    XCTAssertEqual(dismiss, 1)
  }

  func testCreatePasswordSuccessAndFailure() async {
    for succeeds in [true, false] {
      let error = ErrorEnvelope(errorMessages: ["Error creating password"], ksrCode: nil, httpCode: 1, exception: nil)
      let service = MockService(createPasswordResult: succeeds ? .success(EmptyResponseEnvelope()) : .failure(error))
      await withEnvironment(apiService: service, currentUser: .template) {
        var succeeded = false
        var failure: String?
        self.vm.onSuccess = { succeeded = true }
        self.vm.onFailure = { failure = $0 }
        self.vm.newPasswordTextFieldChanged(text: "longpassword")
        self.vm.newPasswordConfirmationTextFieldChanged(text: "longpassword")
        self.vm.saveButtonTapped()
        XCTAssertTrue(self.vm.isLoading)
        await self.vm.waitForSave()
        XCTAssertFalse(self.vm.isLoading)
        XCTAssertEqual(succeeded, succeeds)
        XCTAssertEqual(failure != nil, !succeeds)
        if !succeeds { XCTAssertEqual(failure, error.localizedDescription) }
      }
    }
  }
}
