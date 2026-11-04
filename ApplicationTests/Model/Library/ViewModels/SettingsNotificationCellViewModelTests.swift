@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SettingsNotificationCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNotificationCellViewModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testInitialValuesAndUnsupportedNotifications() {
    var user = User.template
    user[keyPath: UserAttribute.notification(.updates).keyPath] = true
    user[keyPath: UserAttribute.notification(.mobileUpdates).keyPath] = false
    user.stats.backedProjectsCount = 5
    self.vm.configure(with: .init(cellType: .projectUpdates, user: user))
    XCTAssertEqual(self.vm.emailEnabled, true)
    XCTAssertEqual(self.vm.pushEnabled, false)
    XCTAssertEqual(self.vm.projectCountText, "5")
    XCTAssertNil(SettingsNotificationCellViewModel.notificationFor(cellType: .creatorTips, notificationType: .push))
    XCTAssertNil(SettingsNotificationCellViewModel.notificationFor(cellType: .marketingUpdate, notificationType: .email))
  }

  func testSuccessfulToggle() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user), currentUser: user) {
      var saved: User?
      self.vm.onUserUpdated = { saved = $0 }
      self.vm.configure(with: .init(cellType: .projectUpdates, user: user))
      self.vm.didTapEmailNotificationsButton(selected: false)
      XCTAssertEqual(self.vm.emailEnabled, true)
      await self.vm.waitForSaves()
      XCTAssertEqual(saved?[keyPath: UserAttribute.notification(.updates).keyPath], true)
    }
  }

  func testFailedToggleRestoresInitialValues() async {
    let error = ErrorEnvelope(errorMessages: ["Unable to save."], ksrCode: .UnknownCode,
                              httpCode: 400, exception: nil)
    var user = User.template
    user[keyPath: UserAttribute.notification(.updates).keyPath] = false
    await withEnvironment(apiService: MockService(updateUserSelfError: error), currentUser: user) {
      var message: String?
      self.vm.onError = { message = $0 }
      self.vm.configure(with: .init(cellType: .projectUpdates, user: user))
      self.vm.didTapEmailNotificationsButton(selected: false)
      XCTAssertEqual(self.vm.emailEnabled, true)
      await self.vm.waitForSaves()
      XCTAssertEqual(self.vm.emailEnabled, false)
      XCTAssertEqual(message, "Unable to save.")
    }
  }
}
