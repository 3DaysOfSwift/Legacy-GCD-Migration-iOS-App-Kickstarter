@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class FacebookConfirmationViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = AuthenticationFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAuthenticationProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = FacebookConfirmationViewModel(authenticationFeature: self.feature, sleep: { _ in })

  func testInitialStateAndNewsletterToggle() {
    self.vm.email("kittens@example.com")
    self.vm.viewDidLoad()
    XCTAssertEqual(self.vm.displayEmail, "kittens@example.com")
    XCTAssertFalse(self.vm.sendNewsletters)
    self.vm.sendNewslettersToggled(true)
    XCTAssertTrue(self.vm.sendNewsletters)
  }

  func testSignupAndLoginNavigation() async {
    var success = 0
    var login = 0
    self.vm.onSignupSuccess = { success += 1 }
    self.vm.onLogin = { login += 1 }
    self.vm.viewDidLoad()
    self.vm.facebookToken("PuRrrrrrr3848")
    self.vm.sendNewslettersToggled(true)
    self.vm.createAccountButtonPressed()
    XCTAssertTrue(self.vm.isLoading)
    await self.vm.waitForSignup()
    XCTAssertFalse(self.vm.isLoading)
    XCTAssertEqual(success, 1)
    self.vm.loginButtonPressed()
    XCTAssertEqual(login, 1)
  }

  func testSignupFailureShowsServerMessage() async {
    let error = ErrorEnvelope(errorMessages: ["Email address has an issue."], ksrCode: nil, httpCode: 422, exception: nil)
    await withEnvironment(apiService: MockService(signupError: error)) {
      var message: String?
      self.vm.onSignupError = { message = $0 }
      self.vm.viewDidLoad()
      self.vm.facebookToken("Meowwwww4484848")
      self.vm.createAccountButtonPressed()
      await self.vm.waitForSignup()
      XCTAssertEqual(message, "Email address has an issue.")
      XCTAssertFalse(self.vm.isLoading)
    }
  }
}
