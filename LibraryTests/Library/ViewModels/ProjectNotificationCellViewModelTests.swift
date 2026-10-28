@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class ProjectNotificationCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let session = SessionFeature(makeProvider: {
    AsyncSessionProvider(service: AppEnvironment.current.apiService)
  })
  private lazy var feature = SettingsFeature(
    sessionFeature: self.session,
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = ProjectNotificationCellViewModel(feature: self.feature)
  internal let projectName = TestObserver<String, Never>()
  internal let notificationOn = TestObserver<Bool, Never>()
  internal let notifyDelegateOfSaveError = TestObserver<String, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.name.observe(self.projectName.observer)
      self.vm.outputs.notificationOn.observe(self.notificationOn.observer)
      self.vm.outputs.notifyDelegateOfSaveError.observe(self.notifyDelegateOfSaveError.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  internal func testCellReuse() async {
    let notification = ProjectNotification.template
    self.vm.inputs.configureWith(notification: notification)
    self.notificationOn.assertValues([false], "Notification off by default.")

    self.vm.inputs.notificationTapped(on: true)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    self.notificationOn.assertValues([false, true], "Notification turned on.")

    self.vm.inputs.configureWith(notification: notification)
    self.notificationOn.assertValues([false, true], "Notification stays on despite cell reuse.")
  }

  internal func testProjectNotificationEmits() async {
    let notification = ProjectNotification.template
      |> ProjectNotification.lens.email .~ true
      |> ProjectNotification.lens.mobile .~ true
      |> ProjectNotification.lens.project.name .~ "My cool project"

    self.vm.inputs.configureWith(notification: notification)
    self.projectName.assertValues(["My cool project"], "Notification name emitted.")
    self.notificationOn.assertValues([true], "Notification state emitted.")
  }

  internal func testTappingNotification() async {
    let notification = ProjectNotification.template

    self.vm.inputs.configureWith(notification: notification)
    self.notificationOn.assertValues([false], "Notification off by default.")

    self.vm.inputs.notificationTapped(on: true)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    self.notificationOn.assertValues([false, true], "Notification turned on.")
    self.notifyDelegateOfSaveError.assertDidNotEmitValue("Notification saved.")

    self.vm.inputs.notificationTapped(on: true)
    self.notificationOn.assertValues([false, true], "Notification unchanged.")
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    self.notificationOn.assertValues([false, true], "Notification unchanged.")

    self.vm.inputs.notificationTapped(on: false)
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    self.notificationOn.assertValues([false, true, false], "Notification turned off.")
    self.notifyDelegateOfSaveError.assertDidNotEmitValue("Notification preference saved successfully.")
  }

  internal func testUpdateError() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to save."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(updateProjectNotificationError: error)) {
      let notification = ProjectNotification.template
      self.vm.inputs.configureWith(notification: notification)
      self.notificationOn.assertValues([false], "Notification off by default.")

      self.vm.inputs.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true], "Notification immediately turned on on tap.")

      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.notifyDelegateOfSaveError.assertValueCount(1, "Updating notification errored.")
      self.notificationOn.assertValues([false, true, false], "Notification was not successfully saved.")

      self.vm.inputs.notificationTapped(on: true)
      self.notificationOn.assertValues(
        [false, true, false, true],
        "Notification immediately turned on on tap."
      )

      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.notifyDelegateOfSaveError.assertValueCount(2, "Updating notification errored.")
      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification was not successfully saved."
      )

      self.vm.inputs.notificationTapped(on: true)
      self.notificationOn.assertValues(
        [false, true, false, true, false, true],
        "Notification immediately turned on on tap."
      )

      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.notifyDelegateOfSaveError.assertValueCount(3, "Updating notification errored.")
      self.notificationOn.assertValues(
        [false, true, false, true, false, true, false],
        "Notification still not saved."
      )
    }
  }

  internal func testErroringWithCellReuse() async {
    let error = ErrorEnvelope(
      errorMessages: ["Unable to save."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    await withEnvironment(apiService: MockService(updateProjectNotificationError: error)) {
      let notification = ProjectNotification.template
      self.vm.inputs.configureWith(notification: notification)
      self.notificationOn.assertValues([false], "Notification off by default.")

      self.vm.inputs.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true], "Notification immediately turned on on tap.")

      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.notifyDelegateOfSaveError.assertValueCount(1, "Updating notification errored.")
      self.notificationOn.assertValues([false, true, false], "Notification was not successfully saved.")

      self.vm.inputs.configureWith(notification: notification)

      self.notificationOn.assertValues([false, true, false], "Notification still off after cell reuse.")

      self.vm.inputs.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true, false, true], "Notification immediately turned on.")

      await self.feature.waitForOperations()
      await self.scheduler.advance()
      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification reverted to off after failure."
      )

      self.vm.inputs.configureWith(notification: notification)

      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification still off after cell reuse."
      )
    }

    self.vm.inputs.notificationTapped(on: true)
    self.notificationOn.assertValues(
      [false, true, false, true, false, true],
      "Notification turned on on tap."
    )

    await self.feature.waitForOperations()
    await self.scheduler.advance()
    self.notificationOn.assertValues(
      [false, true, false, true, false, true],
      "Notification remains on after API request."
    )
  }
}
