@testable import Kickstarter_Framework
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import XCTest

@MainActor
internal final class SettingsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsViewModel(
    SettingsViewController.viewController(for:), settingsFeature: self.feature
  )
  private let expectedLogoutPromptText = (
    messsage: "Are you sure you want to log out?",
    cancel: "Cancel",
    confirm: "Yes"
  )

  private let findFriendsDisabled = TestObserver<Bool, Never>()
  private let goToAppStoreRating = TestObserver<String, Never>()
  private let logout = TestObserver<DiscoveryParams, Never>()
  private let reloadDataWithUser = TestObserver<User, Never>()
  private let showConfirmLogout = TestObserver<(message: String, cancel: String, confirm: String), Never>()
  private let transitionToViewController = TestObserver<UIViewController, Never>()

  internal override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.findFriendsDisabledProperty.signal.observe(self.findFriendsDisabled.observer)
      self.vm.outputs.goToAppStoreRating.observe(self.goToAppStoreRating.observer)
      self.vm.outputs.logoutWithParams.observe(self.logout.observer)
      self.vm.outputs.reloadDataWithUser.observe(self.reloadDataWithUser.observer)
      self.vm.outputs.showConfirmLogoutPrompt.signal.observe(self.showConfirmLogout.observer)
      self.vm.outputs.transitionToViewController.observe(self.transitionToViewController.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testViewDidLoad_withSocialEnabledUser() async {
    let user = User.template |> \.social .~ true
    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.viewDidLoad()
      await self.feature.waitForOperations()

      self.reloadDataWithUser.assertValueCount(2)
      self.findFriendsDisabled.assertValues([false, false])
    }
  }

  func testViewDidLoad_withSocialDisabledUser() async {
    let user = User.template |> \.social .~ false
    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.viewDidLoad()
      await self.feature.waitForOperations()

      self.reloadDataWithUser.assertValueCount(2)
      self.findFriendsDisabled.assertValues([true, true])
    }
  }

  func testLogoutCellTapped() {
    self.showConfirmLogout.assertValueCount(0)
    self.logout.assertValueCount(0)
    self.vm.settingsCellTapped(cellType: .logout)

    self.showConfirmLogout.assertValueCount(1, "Shows confirm logout alert.")

    self.vm.settingsCellTapped(cellType: .logout)

    self.showConfirmLogout.assertValueCount(2, "Show confirm logout alert")
    self.vm.inputs.logoutConfirmed()

    self.logout.assertValueCount(1, "Log out triggered")
  }

  func testLogoutPromptText() {
    XCTAssertNil(self.showConfirmLogout.lastValue)

    self.vm.settingsCellTapped(cellType: .logout)

    XCTAssertEqual(self.showConfirmLogout.lastValue!.message, self.expectedLogoutPromptText.messsage)
    XCTAssertEqual(self.showConfirmLogout.lastValue!.confirm, self.expectedLogoutPromptText.confirm)
    XCTAssertEqual(self.showConfirmLogout.lastValue!.cancel, self.expectedLogoutPromptText.cancel)
  }

  func testNotificationsCellTapped() {
    self.vm.inputs.viewDidLoad()
    self.transitionToViewController.assertValueCount(0)
    self.vm.settingsCellTapped(cellType: .notifications)
    self.transitionToViewController.assertValueCount(1)
  }

  func testNewslettersCellTapped() {
    self.vm.inputs.viewDidLoad()
    self.transitionToViewController.assertValueCount(0)
    self.vm.settingsCellTapped(cellType: .newsletters)
    self.transitionToViewController.assertValueCount(1)
  }

  func testCellSelection() {
    XCTAssertTrue(self.vm.shouldSelectRow(for: .newsletters))
  }

  func testShouldSelectRow_findFriends_FollowingEnabled() {
    let user = User.template |> \.social .~ true

    withEnvironment(currentUser: user) {
      XCTAssertTrue(self.vm.shouldSelectRow(for: .findFriends))
    }
  }

  func testShouldSelectRow_findFriends_FollowingDisabled() {
    let user = User.template |> \.social .~ false

    withEnvironment(currentUser: user) {
      XCTAssertFalse(self.vm.shouldSelectRow(for: .findFriends))
    }
  }

  func testAppStoreRatingCellTapped() {
    self.goToAppStoreRating.assertValueCount(0)
    self.vm.settingsCellTapped(cellType: .rateInAppStore)
    self.goToAppStoreRating.assertValueCount(1, "Opens app store url")
  }

  func testUserUpdatedNotification() async {
    let storedUser = User.template |> \.social .~ false
    let updatedUser = User.template |> \.social .~ true
    let mockService = MockService(fetchUserSelfResponse: updatedUser)

    await withEnvironment(apiService: mockService, currentUser: storedUser) {
      self.vm.currentUserUpdated()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataWithUser.assertValueCount(2)
      self.findFriendsDisabled.assertValues([true, false])
    }
  }
}
