@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SettingsNewslettersViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNewslettersViewModel(feature: self.feature)

  func testCachedAndIdenticalRefreshedUsersAndDelegateUpdates() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user), currentUser: user) {
      var users: [User] = []
      self.vm.onUser = { users.append($0) }
      self.vm.viewDidLoad()
      await self.vm.waitForLoads()
      XCTAssertEqual(users.count, 1)
      self.vm.didUpdate(user: user)
      XCTAssertEqual(users.count, 2)
    }
  }
}
