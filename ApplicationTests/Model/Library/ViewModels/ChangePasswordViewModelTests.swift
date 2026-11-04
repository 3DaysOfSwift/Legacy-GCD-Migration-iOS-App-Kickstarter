@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ChangePasswordViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = ChangePasswordViewModel(settingsFeature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture", user: .template))
  }

  func testValidationAndFocus() {
    var focused = 0
    self.vm.onFocusCurrent = { focused += 1 }
    self.vm.onFocusNew = { focused += 1 }
    self.vm.onFocusConfirmation = { focused += 1 }
    self.vm.viewDidAppear()
    self.vm.currentPasswordFieldDidReturn(currentPassword: "oldpassword")
    self.vm.newPasswordFieldDidReturn(newPassword: "short")
    XCTAssertEqual(self.vm.validationMessage, Strings.Password_min_length_message())
    self.vm.newPasswordFieldTextChanged(text: "newpassword")
    XCTAssertEqual(self.vm.validationMessage, "")
    self.vm.newPasswordConfirmationFieldTextChanged(text: "wrong")
    XCTAssertEqual(self.vm.validationMessage, Strings.Passwords_matching_message())
    self.vm.newPasswordConfirmationFieldTextChanged(text: "newpassword")
    XCTAssertTrue(self.vm.saveButtonIsEnabled)
    XCTAssertEqual(self.vm.validationMessage, "")
    XCTAssertEqual(focused, 3)
  }

  func testSaveSuccessAndFailure() async {
    for succeeds in [true, false] {
      let error = ErrorEnvelope(errorMessages: ["Error"], ksrCode: nil, httpCode: 1, exception: nil)
      let service = MockService(changePasswordResult: succeeds ? .success(EmptyResponseEnvelope()) : .failure(error))
      await withEnvironment(apiService: service, currentUser: .template) {
        var success = false
        var failure: String?
        self.vm.onSuccess = { success = true }
        self.vm.onFailure = { failure = $0 }
        self.vm.currentPasswordFieldTextChanged(text: "oldpassword")
        self.vm.newPasswordFieldTextChanged(text: "newpassword")
        self.vm.newPasswordConfirmationFieldTextChanged(text: "newpassword")
        self.vm.saveButtonTapped()
        XCTAssertTrue(self.vm.isLoading)
        await self.vm.waitForSaves()
        XCTAssertFalse(self.vm.isLoading)
        XCTAssertEqual(success, succeeds)
        XCTAssertEqual(failure != nil, !succeeds)
      }
    }
  }
}
