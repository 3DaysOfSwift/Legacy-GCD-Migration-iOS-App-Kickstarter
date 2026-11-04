@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SettingsNotificationsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNotificationsViewModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testLoadingPickerNavigationAndSave() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user), currentUser: user) {
      var users = 0
      var hidden: [Bool] = []
      var selection: EmailFrequency?
      var navigated = 0
      self.vm.onUser = { _ in users += 1 }
      self.vm.onPickerHidden = { hidden.append($0) }
      self.vm.onPickerSelection = { selection = $0 }
      self.vm.onManageProjects = { navigated += 1 }
      self.vm.viewDidLoad()
      await self.vm.waitForLoads()
      XCTAssertEqual(users, 2)
      XCTAssertNotNil(selection)
      self.vm.didSelectRow(cellType: .emailFrequency)
      self.vm.dismissPickerTap()
      self.vm.didSelectRow(cellType: .projectNotifications)
      self.vm.didSelectEmailFrequency(frequency: .dailySummary)
      await self.vm.waitForSaves()
      XCTAssertEqual(hidden, [true, false, true])
      XCTAssertEqual(navigated, 1)
      XCTAssertEqual(users, 3)
    }
  }

  func testSaveFailureAndCellError() async {
    let error = ErrorEnvelope(errorMessages: ["Unable to save."], ksrCode: .UnknownCode,
                              httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(updateUserSelfError: error)) {
      var messages: [String] = []
      self.vm.onError = { messages.append($0) }
      self.vm.viewDidLoad()
      await self.vm.waitForLoads()
      self.vm.didSelectEmailFrequency(frequency: .dailySummary)
      await self.vm.waitForSaves()
      self.vm.failedToUpdateUser(error: "Cell error")
      XCTAssertEqual(messages, ["Unable to save.", "Cell error"])
    }
  }
}
