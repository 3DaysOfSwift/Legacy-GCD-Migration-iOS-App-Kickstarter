@testable import Kickstarter_iOS
@testable import KsApi

import Prelude
import XCTest

@MainActor
final class SettingsPrivacyViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsPrivacyViewModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testCachedAndRefreshedUserAndPrivateProfileSave() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user), currentUser: user) {
      var loaded: [User] = []
      var updated: [User] = []
      self.vm.onReload = { loaded.append($0) }
      self.vm.onUserUpdated = { updated.append($0) }
      self.vm.viewDidLoad()
      await self.vm.waitForLoad()
      XCTAssertEqual(loaded.count, 2)
      self.vm.privateProfileToggled(on: true)
      await self.vm.waitForSaves()
      XCTAssertEqual(updated.last?.showPublicProfile, false)
    }
  }

  func testSaveFailureAndFollowingConfirmation() async {
    let error = ErrorEnvelope(errorMessages: ["Unable to save."], ksrCode: .UnknownCode,
                              httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(updateUserSelfError: error), isVoiceOverRunning: { true }) {
      var message: String?
      var focusCount = 0
      var resetCount = 0
      var updated: User?
      self.vm.onError = { message = $0 }
      self.vm.onFocusFollowing = { focusCount += 1 }
      self.vm.onResetFollowing = { resetCount += 1 }
      self.vm.onUserUpdated = { updated = $0 }
      self.vm.viewDidLoad()
      await self.vm.waitForLoad()
      self.vm.didCancelSocialOptOut()
      self.vm.didConfirmSocialOptOut()
      await self.vm.waitForSaves()
      XCTAssertEqual(resetCount, 1)
      XCTAssertEqual(focusCount, 2)
      XCTAssertEqual(message, "Unable to save.")
      XCTAssertNotNil(updated)
    }
  }
}
