@testable import Kickstarter_iOS
@testable import KsApi

import XCTest

@MainActor
final class SettingsRecommendationsCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsRecommendationsCellViewModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testSaveNotifiesAndUpdatesImmediately() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user)) {
      var notifications = 0
      self.vm.onSaved = { notifications += 1 }
      self.vm.configureWith(user: user)
      XCTAssertEqual(self.vm.recommendationsOn, true)
      self.vm.recommendationsTapped(on: false)
      XCTAssertEqual(self.vm.recommendationsOn, false)
      await self.vm.waitForSaves()
      XCTAssertEqual(notifications, 1)
    }
  }

  func testFailureRollsBackAndReportsError() async {
    let error = ErrorEnvelope(errorMessages: ["Unable to save."], ksrCode: .UnknownCode,
                              httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(updateUserSelfError: error)) {
      var message: String?
      self.vm.onError = { message = $0 }
      self.vm.configureWith(user: .template)
      self.vm.recommendationsTapped(on: false)
      XCTAssertEqual(self.vm.recommendationsOn, false)
      await self.vm.waitForSaves()
      XCTAssertEqual(message, "Unable to save.")
      XCTAssertEqual(self.vm.recommendationsOn, true)
    }
  }
}
