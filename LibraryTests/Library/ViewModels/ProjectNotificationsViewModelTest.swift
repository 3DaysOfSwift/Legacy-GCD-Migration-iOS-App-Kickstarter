@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
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
  internal let projectNotificationsPresent = TestObserver<Bool, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.projectNotifications.map { !$0.isEmpty }
        .observe(self.projectNotificationsPresent.observer)
    }
  }

  func testProjectNotificationsEmit() async {
    self.vm.inputs.viewDidLoad()
    await self.vm.waitForLoading()
    self.projectNotificationsPresent.assertValues([true], "Project notifications emitted.")
  }
}
