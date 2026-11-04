@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ProjectNotificationsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let session = SessionFeature(makeProvider: {
    AsyncSessionProvider(service: AppEnvironment.current.apiService)
  })
  private lazy var feature = SettingsFeature(
    sessionFeature: self.session,
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = ProjectNotificationsViewModel(feature: self.feature)

  internal override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
    }
  }

  func testProjectNotificationsEmit() async {
    self.vm.viewDidLoad()
    await self.vm.waitForLoading()
    XCTAssertFalse(self.vm.projectNotifications.isEmpty, "Project notifications loaded.")
  }
}
