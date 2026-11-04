@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class ResetPasswordViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = ResetPasswordViewModel(authenticationFeature: self.feature)

  func testInitialEmailAndValidation() {
    self.vm.emailChanged("user@example.com")
    self.vm.viewDidLoad()
    XCTAssertEqual(self.vm.email, "user@example.com")
    XCTAssertTrue(self.vm.formIsValid)
    self.vm.emailChanged("bad")
    XCTAssertFalse(self.vm.formIsValid)
  }

  func testResetSuccessAndConfirmation() async {
    var message: String?
    var returned = false
    self.vm.onResetSuccess = { message = $0 }
    self.vm.onReturnToLogin = { returned = true }
    self.vm.viewDidLoad()
    self.vm.emailChanged("user@example.com")
    self.vm.resetButtonPressed()
    await self.vm.waitForReset()
    XCTAssertEqual(message, Strings.forgot_password_we_sent_an_email_to_email_address_with_instructions_to_reset_your_password(email: "user@example.com"))
    self.vm.confirmResetButtonPressed()
    XCTAssertTrue(returned)
  }

  func testUnknownEmailAndOtherErrors() async {
    for code in [404, 400] {
      let error = ErrorEnvelope(errorMessages: [], ksrCode: nil, httpCode: code, exception: nil)
      await withEnvironment(apiService: MockService(resetPasswordError: error)) {
        var message: String?
        self.vm.onError = { message = $0 }
        self.vm.emailChanged("user@example.com")
        self.vm.resetButtonPressed()
        await self.vm.waitForReset()
        XCTAssertEqual(message, code == 404 ? Strings.forgot_password_error() : Strings.general_error_something_wrong())
      }
    }
  }
}
