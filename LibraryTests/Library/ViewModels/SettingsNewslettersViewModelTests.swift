import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class SettingsNewslettersViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNewslettersViewModel(feature: self.feature)

  let currentUser = TestObserver<User, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      // Settings is a signed-in flow; the original fixtures omitted authentication.
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.currentUser.observe(self.currentUser.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testCurrentUserEmits_OnViewDidLoad() async {
    let user = User.template

    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.currentUser.assertValueCount(0)

    self.vm.inputs.viewDidLoad()
    self.currentUser.assertValueCount(1, "currentUser should emit after viewDidLoad.")
  }

  func testCurrentUserEmits_WhenDelegateIsCalled() async {
    let user = User.template
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

    self.vm.inputs.didUpdate(user: user)
    self.currentUser.assertValueCount(1, "currentUser should emit after user updates.")
  }
}
