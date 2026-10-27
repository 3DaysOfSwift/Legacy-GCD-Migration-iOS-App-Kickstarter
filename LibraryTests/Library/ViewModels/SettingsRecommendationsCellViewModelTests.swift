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
internal final class SettingsRecommendationsCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsRecommendationsCellViewModel(feature: self.feature)
  internal let postNotification = TestObserver<Notification, Never>()
  internal let recommendationsOn = TestObserver<Bool, Never>()
  internal let unableToSaveError = TestObserver<String, Never>()
  internal let updateCurrentUser = TestObserver<User, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      // Settings is a signed-in flow; the original fixtures omitted authentication.
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.postNotification.observe(self.postNotification.observer)
      self.vm.outputs.recommendationsOn.observe(self.recommendationsOn.observer)
      self.vm.outputs.unableToSaveError.observe(self.unableToSaveError.observer)
      self.vm.outputs.updateCurrentUser.observe(self.updateCurrentUser.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testOpOutOfRecommendations() async {
    let user = User.template
    self.vm.inputs.configureWith(user: user)
    self.recommendationsOn.assertValues([true])
    self.vm.inputs.recommendationsTapped(on: false)
    self.recommendationsOn.assertValues([true, false])
  }

  func testUpdateUser() async {
    let user = User.template
    self.vm.inputs.configureWith(user: user)
    self.updateCurrentUser.assertValueCount(1)
    self.vm.inputs.recommendationsTapped(on: true)
    self.updateCurrentUser.assertValueCount(2)
    self.vm.inputs.recommendationsTapped(on: true)
    self.updateCurrentUser.assertValueCount(3)
  }

  func testPostNotification() async {
    let notification = Notification(name: Notification.Name.ksr_recommendationsSettingChanged)
    let user = User.template

    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user)) {
      self.vm.inputs.configureWith(user: user)
      self.postNotification.assertDidNotEmitValue()
      self.vm.inputs.recommendationsTapped(on: true)

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.postNotification.assertValue(notification)
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
      let user = User.template
      self.vm.inputs.configureWith(user: user)

      self.recommendationsOn.assertValues([true], "Recommendations turned on as default.")

      self.vm.inputs.recommendationsTapped(on: false)

      self.recommendationsOn.assertValues([true, false], "Recommendations immediately turned off on tap.")

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.unableToSaveError.assertValueCount(1, "Updating user errored.")
      self.recommendationsOn.assertValues([true, false, true], "Did not successfully save preference.")
    }
  }
}
