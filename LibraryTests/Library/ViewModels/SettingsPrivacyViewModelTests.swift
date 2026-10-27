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
internal final class SettingsPrivacyViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsPrivacyViewModel(feature: self.feature)
  internal let focusScreenReaderOnFollowingCell = TestObserver<Void, Never>()
  internal let reloadData = TestObserver<User, Never>()
  internal let resetFollowingSection = TestObserver<Void, Never>()
  internal let unableToSaveError = TestObserver<String, Never>()
  internal let updateCurrentUser = TestObserver<User, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      // Settings is a signed-in flow; the original fixtures omitted authentication.
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.focusScreenReaderOnFollowingCell.observe(self.focusScreenReaderOnFollowingCell.observer)
      self.vm.outputs.reloadData.observe(self.reloadData.observer)
      self.vm.outputs.resetFollowingSection.observe(self.resetFollowingSection.observer)
      self.vm.outputs.unableToSaveError.observe(self.unableToSaveError.observer)
      self.vm.outputs.updateCurrentUser.observe(self.updateCurrentUser.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testFocusScreenReaderOnFollowingCel() async {
    await withEnvironment(isVoiceOverRunning: { true }) {
      self.vm.inputs.didCancelSocialOptOut()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.focusScreenReaderOnFollowingCell.assertValueCount(1)

      self.vm.inputs.didConfirmSocialOptOut()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.focusScreenReaderOnFollowingCell.assertValueCount(2)
    }
  }

  func testResetFollowingSection_WhenCancelingSocialOptOut() async {
    let user = User.template
      |> \.social .~ true

    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()

      self.vm.inputs.didCancelSocialOptOut()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.resetFollowingSection.assertValueCount(1)
    }
  }

  func testReloadData() async {
    let user = User.template
    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.reloadData.assertValues([user, user])
    }
  }

  func testUnableToSaveError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to save."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(updateUserSelfError: error)) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()

      self.vm.inputs.didConfirmSocialOptOut()

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.unableToSaveError.assertValueCount(1)
    }
  }

  func testFollowingSwitchTapped_updatesCurrentUser() async {
    self.vm.viewDidLoad()
    await self.feature.waitForOperations()

    self.vm.didCancelSocialOptOut()
    self.updateCurrentUser.assertValueCount(0)

    self.vm.didConfirmSocialOptOut()

    await self.feature.waitForOperations()

    await self.scheduler.advance()

    self.updateCurrentUser.assertValueCount(1)
  }

  func testUpdateCurrentUser() async {
    let mockService = MockService(fetchUserSelfResponse: User.template)

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      self.updateCurrentUser.assertValueCount(0)

      self.vm.inputs.didCancelSocialOptOut()
      self.updateCurrentUser.assertValueCount(0)

      self.vm.inputs.didConfirmSocialOptOut()
      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.updateCurrentUser.assertValueCount(1)
    }
  }

  func testPrivateProfileToggled_updatesCurrentUser() async {
    let updatedUser = User.template
      |> UserAttribute.privacy(.showPublicProfile).keyPath .~ false
    let mockService = MockService(fetchUserSelfResponse: User.template)

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      await self.feature.waitForOperations()
      self.updateCurrentUser.assertValueCount(0)

      self.vm.privateProfileToggled(on: true)

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.updateCurrentUser.assertValue(updatedUser)
    }
  }
}
