@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class LoginSignupUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private var useCase: LoginSignupUseCase!
  private var sessions = 0
  private var intents: [LoginIntent] = []
  private var loginStates: [Bool] = []

  override func setUp() async throws {
    try await super.setUp()
    self.useCase = LoginSignupUseCase(withLoginIntent: .generic)
    self.useCase.onSessionChanged = { [weak self] in self?.sessions += 1 }
    self.useCase.onLogin = { [weak self] in self?.intents.append($0) }
    self.useCase.onLoginState = { [weak self] in self?.loginStates.append($0) }
  }

  func testSessionChangeNotifiesAndReportsCurrentState() {
    self.useCase.initialDataAvailable()
    self.useCase.userSessionDidChange()
    XCTAssertEqual(self.sessions, 1)
    XCTAssertEqual(self.loginStates, [false, false])
    withEnvironment(currentUser: .template) {
      self.useCase.userSessionDidChange()
      XCTAssertEqual(self.loginStates, [false, false, true])
      XCTAssertTrue(self.useCase.isLoggedIn)
    }
  }

  func testLoginActionPreservesIntent() {
    self.useCase.goToLoginSignupTapped()
    XCTAssertEqual(self.intents.count, 1)
    XCTAssertEqual(self.intents.first, .generic)
  }

  func testInitialLoggedInState() {
    withEnvironment(currentUser: .template) {
      self.useCase.initialDataAvailable()
      XCTAssertEqual(self.loginStates, [true])
    }
  }
}
