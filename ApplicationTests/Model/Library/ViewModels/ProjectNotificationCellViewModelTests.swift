@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
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
  private let projectName = NotificationRecorder<String>()
  private let notificationOn = NotificationRecorder<Bool>()
  private let notifyDelegateOfSaveError = NotificationRecorder<String>()

  internal override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.onName = { [weak self] in self?.projectName.record($0) }
      self.vm.onSwitch = { [weak self] in self?.notificationOn.record($0) }
      self.vm.onError = { [weak self] in self?.notifyDelegateOfSaveError.record($0) }
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  internal func testCellReuse() async {
    let notification = ProjectNotification.template
    self.vm.configureWith(notification: notification)
    self.notificationOn.assertValues([false], "Notification off by default.")

    self.vm.notificationTapped(on: true)
    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
    self.notificationOn.assertValues([false, true], "Notification turned on.")

    self.vm.configureWith(notification: notification)
    self.notificationOn.assertValues([false, true], "Notification stays on despite cell reuse.")
  }

  internal func testProjectNotificationEmits() async {
    let notification = ProjectNotification.template
      |> ProjectNotification.lens.email .~ true
      |> ProjectNotification.lens.mobile .~ true
      |> ProjectNotification.lens.project.name .~ "My cool project"

    self.vm.configureWith(notification: notification)
    self.projectName.assertValues(["My cool project"], "Notification name emitted.")
    self.notificationOn.assertValues([true], "Notification state emitted.")
  }

  internal func testTappingNotification() async {
    let notification = ProjectNotification.template

    self.vm.configureWith(notification: notification)
    self.notificationOn.assertValues([false], "Notification off by default.")

    self.vm.notificationTapped(on: true)
    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
    self.notificationOn.assertValues([false, true], "Notification turned on.")
    self.notifyDelegateOfSaveError.assertDidNotEmitValue("Notification saved.")

    self.vm.notificationTapped(on: true)
    self.notificationOn.assertValues([false, true], "Notification unchanged.")
    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
    self.notificationOn.assertValues([false, true], "Notification unchanged.")

    self.vm.notificationTapped(on: false)
    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
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
      self.vm.configureWith(notification: notification)
      self.notificationOn.assertValues([false], "Notification off by default.")

      self.vm.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true], "Notification immediately turned on on tap.")

      await self.feature.waitForOperations()
      await self.vm.waitForPresentation()
      self.notifyDelegateOfSaveError.assertValueCount(1, "Updating notification errored.")
      self.notificationOn.assertValues([false, true, false], "Notification was not successfully saved.")

      self.vm.notificationTapped(on: true)
      self.notificationOn.assertValues(
        [false, true, false, true],
        "Notification immediately turned on on tap."
      )

      await self.feature.waitForOperations()
      await self.vm.waitForPresentation()
      self.notifyDelegateOfSaveError.assertValueCount(2, "Updating notification errored.")
      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification was not successfully saved."
      )

      self.vm.notificationTapped(on: true)
      self.notificationOn.assertValues(
        [false, true, false, true, false, true],
        "Notification immediately turned on on tap."
      )

      await self.feature.waitForOperations()
      await self.vm.waitForPresentation()
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
      self.vm.configureWith(notification: notification)
      self.notificationOn.assertValues([false], "Notification off by default.")

      self.vm.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true], "Notification immediately turned on on tap.")

      await self.feature.waitForOperations()
      await self.vm.waitForPresentation()
      self.notifyDelegateOfSaveError.assertValueCount(1, "Updating notification errored.")
      self.notificationOn.assertValues([false, true, false], "Notification was not successfully saved.")

      self.vm.configureWith(notification: notification)

      self.notificationOn.assertValues([false, true, false], "Notification still off after cell reuse.")

      self.vm.notificationTapped(on: true)
      self.notificationOn.assertValues([false, true, false, true], "Notification immediately turned on.")

      await self.feature.waitForOperations()
      await self.vm.waitForPresentation()
      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification reverted to off after failure."
      )

      self.vm.configureWith(notification: notification)

      self.notificationOn.assertValues(
        [false, true, false, true, false],
        "Notification still off after cell reuse."
      )
    }

    self.vm.notificationTapped(on: true)
    self.notificationOn.assertValues(
      [false, true, false, true, false, true],
      "Notification turned on on tap."
    )

    await self.feature.waitForOperations()
    await self.vm.waitForPresentation()
    self.notificationOn.assertValues(
      [false, true, false, true, false, true],
      "Notification remains on after API request."
    )
  }
}

private final class NotificationRecorder<Value: Equatable> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
