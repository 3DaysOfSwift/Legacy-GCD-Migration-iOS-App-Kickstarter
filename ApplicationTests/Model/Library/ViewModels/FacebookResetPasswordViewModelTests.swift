@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class FacebookResetPasswordViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = FacebookResetPasswordViewModel(authenticationFeature: self.feature)

  func testInvalidEmailDoesNotSubmit() async {
    var success = false
    self.vm.onSuccess = { _ in success = true }
    self.vm.emailTextFieldFieldDidChange("bad@email")
    XCTAssertFalse(self.vm.isValid)
    self.vm.emailTextFieldFieldDidReturn()
    await self.vm.waitForReset()
    XCTAssertFalse(success)
    XCTAssertFalse(self.vm.isLoading)
  }

  func testValidEmailCanSubmitByReturn() async {
    var message: String?
    self.vm.onSuccess = { message = $0 }
    self.vm.emailTextFieldFieldDidChange("test@example.com")
    XCTAssertTrue(self.vm.isValid)
    self.vm.emailTextFieldFieldDidReturn()
    XCTAssertTrue(self.vm.isLoading)
    await self.vm.waitForReset()
    XCTAssertFalse(self.vm.isLoading)
    XCTAssertEqual(message, Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(email: "test@example.com"))
  }

  func testFailureShowsServerMessage() async {
    let error = ErrorEnvelope(errorMessages: ["Zoinks!"], ksrCode: nil, httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(resetPasswordError: error)) {
      var message: String?
      self.vm.onFailure = { message = $0 }
      self.vm.emailTextFieldFieldDidChange("test@example.com")
      self.vm.setPasswordButtonPressed()
      await self.vm.waitForReset()
      XCTAssertEqual(message, "Zoinks!")
      XCTAssertFalse(self.vm.isLoading)
    }
  }
}
