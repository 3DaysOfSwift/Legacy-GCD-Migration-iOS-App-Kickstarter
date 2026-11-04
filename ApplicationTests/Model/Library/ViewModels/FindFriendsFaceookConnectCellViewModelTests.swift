@testable import Kickstarter_iOS
@testable import FacebookCore
@testable import FacebookLogin
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class FindFriendsFacebookConnectCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = FindFriendsFacebookConnectCellViewModel(settingsFeature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testLabelsAndActions() {
    var login = 0
    var dismiss = 0
    self.vm.onAttemptLogin = { login += 1 }
    self.vm.onDismiss = { dismiss += 1 }
    self.vm.configureWith(source: .findFriends)
    XCTAssertTrue(self.vm.hideCloseButton)
    XCTAssertEqual(self.vm.title, Strings.Discover_more_projects())
    self.vm.configureWith(source: .settings)
    XCTAssertFalse(self.vm.hideCloseButton)
    self.vm.facebookConnectButtonTapped()
    self.vm.closeButtonTapped()
    XCTAssertEqual(login, 1)
    XCTAssertEqual(dismiss, 1)
    withEnvironment(currentUser: User.template |> \.facebookConnected .~ true |> \.needsFreshFacebookToken .~ true) {
      self.vm.configureWith(source: .settings)
      XCTAssertEqual(self.vm.title, Strings.Facebook_reconnect())
    }
  }

  func testConnectionSuccess() async {
    var connected = 0
    self.vm.onConnected = { connected += 1 }
    self.vm.facebookLoginSuccess(result: self.loginResult())
    XCTAssertTrue(self.vm.isLoading)
    await self.vm.waitForConnection()
    XCTAssertFalse(self.vm.isLoading)
    XCTAssertEqual(connected, 1)
  }

  func testAccountTakenError() async {
    let error = ErrorEnvelope(errorMessages: ["Already linked"], ksrCode: .FacebookConnectAccountTaken, httpCode: 403, exception: nil)
    await withEnvironment(apiService: MockService(facebookConnectError: error), currentUser: .template) {
      var alert: AlertError?
      self.vm.onError = { alert = $0 }
      self.vm.facebookLoginSuccess(result: self.loginResult())
      await self.vm.waitForConnection()
      XCTAssertEqual(alert, .facebookConnectAccountTaken(envelope: error))
      XCTAssertFalse(self.vm.isLoading)
    }
  }

  private func loginResult() -> LoginManagerLoginResult {
    let token = AccessToken(tokenString: "token", permissions: [], declinedPermissions: [], expiredPermissions: [], appID: "123", userID: "1", expirationDate: Date(), refreshDate: Date(), dataAccessExpirationDate: Date())
    return LoginManagerLoginResult(token: token, authenticationToken: nil, isCancelled: false, grantedPermissions: [], declinedPermissions: [])
  }
}
