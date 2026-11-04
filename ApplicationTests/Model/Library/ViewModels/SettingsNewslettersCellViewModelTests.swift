@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SettingsNewslettersCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsNewsletterCellViewModel(feature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testIndividualAndAllSubscriptions() {
    var user = User.template
    for newsletter in Newsletter.allCases { user[keyPath: UserAttribute.newsletter(newsletter).keyPath] = true }
    self.vm.configureWith(value: user)
    XCTAssertEqual(self.vm.subscribeToAllSwitchIsOn, true)
    for newsletter in Newsletter.allCases {
      self.vm.configureWith(value: (newsletter, user))
      XCTAssertEqual(self.vm.switchIsOn, true)
    }
    user.newsletters.arts = false
    self.vm.configureWith(value: (.arts, user))
    XCTAssertEqual(self.vm.switchIsOn, false)
    XCTAssertEqual(self.vm.subscribeToAllSwitchIsOn, false)
  }

  func testGermanOptInAndSuccessfulSave() async {
    let user = User.template
    await withEnvironment(apiService: MockService(fetchUserSelfResponse: user), config: Config.deConfig) {
      var prompts: [String] = []
      var saved: User?
      self.vm.onOptIn = { prompts.append($0) }
      self.vm.onUserUpdated = { saved = $0 }
      self.vm.configureWith(value: (.arts, user))
      self.vm.newslettersSwitchTapped(on: true)
      await self.vm.waitForSaves()
      XCTAssertEqual(prompts, [Newsletter.arts.displayableName])
      XCTAssertEqual(saved?.newsletters.arts, true)
    }
  }

  func testSaveFailure() async {
    let error = ErrorEnvelope(errorMessages: ["Unable to save."], ksrCode: .UnknownCode,
                              httpCode: 400, exception: nil)
    await withEnvironment(apiService: MockService(updateUserSelfError: error)) {
      var message: String?
      self.vm.onError = { message = $0 }
      self.vm.configureWith(value: User.template)
      self.vm.allNewslettersSwitchTapped(on: true)
      await self.vm.waitForSaves()
      XCTAssertEqual(message, "Unable to save.")
    }
  }
}
