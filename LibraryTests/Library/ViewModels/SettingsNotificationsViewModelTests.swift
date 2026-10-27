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
internal final class SettingsNotificationsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNotificationsViewModel(feature: self.feature)

  let goToManageProjectNotifications = TestObserver<Void, Never>()
  let pickerViewIsHidden = TestObserver<Bool, Never>()
  let pickerViewSelectedRow = TestObserver<EmailFrequency, Never>()
  let unableToSaveError = TestObserver<String, Never>()
  let updateCurrentUser = TestObserver<User, Never>()

  internal override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      // Settings is a signed-in flow; the original fixtures omitted authentication.
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
      self.vm.outputs.goToManageProjectNotifications
        .observe(self.goToManageProjectNotifications.observer)
      self.vm.outputs.pickerViewIsHidden.observe(self.pickerViewIsHidden.observer)
      self.vm.outputs.pickerViewSelectedRow.observe(self.pickerViewSelectedRow.observer)
      self.vm.outputs.unableToSaveError.observe(self.unableToSaveError.observer)
      self.vm.outputs.updateCurrentUser.observe(self.updateCurrentUser.observer)
    }
  }

  override func tearDown() async throws {
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testGoToManageProjectNotifications() async {
    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()
    self.vm.inputs.didSelectRow(cellType: .projectNotifications)
    self.goToManageProjectNotifications
      .assertValueCount(1, "Go to manage project notifications screen.")
  }

  func testUpdateError() async {
    let user = User.template
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))
    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()
    self.updateCurrentUser.assertValueCount(2, "Begin with environment's current user and refresh.")
    self.vm.inputs.failedToUpdateUser(error: "Unable to save")
    self.unableToSaveError.assertValueCount(1, "Unable to save")
    self.updateCurrentUser.assertValueCount(2, "User is not updated")
  }

  func testUpdateUser() async {
    let user = User.template
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))
    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()
    self.updateCurrentUser.assertValueCount(2, "Begin with environment's current user and refresh.")

    self.vm.inputs.updateUser(user: user)

    self.updateCurrentUser.assertValueCount(3, "User should be updated.")
  }

  func testCorrectPickerViewRowSelected() async {
    let user = User.template
      |> UserAttribute.notification(.creatorDigest).keyPath .~ true

    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.viewDidLoad()
      await self.feature.waitForOperations()

      self.pickerViewSelectedRow.assertLastValue(EmailFrequency.dailySummary)
    }
  }

  func testEmailFrequencySelected_updateSuccess() async {
    let user = User.template
      |> UserAttribute.notification(.creatorDigest).keyPath .~ true

    let mockService = MockService(fetchUserSelfResponse: user)

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.viewDidLoad()
      await self.feature.waitForOperations()

      self.updateCurrentUser.assertValueCount(2)

      self.pickerViewSelectedRow.assertLastValue(EmailFrequency.dailySummary)

      self.vm.inputs.didSelectEmailFrequency(frequency: EmailFrequency.twiceADaySummary)

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.updateCurrentUser.assertValueCount(3)
      self.pickerViewIsHidden.assertLastValue(true)
      self.pickerViewSelectedRow.assertLastValue(EmailFrequency.twiceADaySummary)
    }
  }

  func testEmailFrequencySelected_updateError() async {
    let user = User.template
      |> UserAttribute.notification(.creatorDigest).keyPath .~ true

    let errorEnvelope = ErrorEnvelope(
      errorMessages: ["Something went wrong"],
      ksrCode: nil,
      httpCode: 500,
      exception: nil
    )

    let mockService = MockService(
      fetchUserSelfResponse: user,
      updateUserSelfError: errorEnvelope
    )

    await withEnvironment(apiService: mockService, currentUser: user) {
      self.vm.viewDidLoad()
      await self.feature.waitForOperations()

      self.updateCurrentUser.assertValueCount(2)

      self.pickerViewSelectedRow.assertLastValue(EmailFrequency.dailySummary)

      self.vm.inputs.didSelectEmailFrequency(frequency: EmailFrequency.twiceADaySummary)

      await self.feature.waitForOperations()

      await self.scheduler.advance()

      self.updateCurrentUser.assertValueCount(2)
      self.pickerViewIsHidden.assertLastValue(true)
      self.pickerViewSelectedRow.assertLastValue(EmailFrequency.dailySummary)
      self.unableToSaveError.assertValueCount(1)
    }
  }

  func testShowHidePickerView_SelectingRow() async {
    self.pickerViewIsHidden.assertDidNotEmitValue()

    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()

    self.pickerViewIsHidden.assertValues([true], "Picker should be hidden")

    self.vm.inputs.didSelectRow(cellType: .emailFrequency)

    self.pickerViewIsHidden.assertValues([true, false], "Picker view should not be hidden")
  }

  func testShowHidePickerView_TapGesture() async {
    self.pickerViewIsHidden.assertDidNotEmitValue()

    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()

    self.pickerViewIsHidden.assertValues([true], "Picker should be hidden")

    self.vm.inputs.didSelectRow(cellType: .emailFrequency)

    self.pickerViewIsHidden.assertValues([true, false], "Picker view is shown")

    self.vm.inputs.dismissPickerTap()

    self.pickerViewIsHidden.assertValues([true, false, true], "Picker view should be hidden")
  }

  func testShowHidePickerView_EmailFrequencyDisabled() async {
    let user = .template
      |> UserAttribute.notification(.pledgeActivity).keyPath .~ false

    self.pickerViewIsHidden.assertDidNotEmitValue()

    self.vm.inputs.viewDidLoad()
    await self.feature.waitForOperations()

    self.pickerViewIsHidden.assertValues([true], "Picker should be hidden")

    self.vm.inputs.didSelectRow(cellType: .emailFrequency)

    self.pickerViewIsHidden.assertValues([true, false], "Picker view is shown")

    self.vm.inputs.updateUser(user: user)

    self.pickerViewIsHidden.assertValues([true, false, true], "Picker view should be hidden")
  }
}
