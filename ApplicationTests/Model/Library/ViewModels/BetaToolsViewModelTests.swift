@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class BetaToolsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = BetaToolsViewModel()

  func testInitialStateAndEnvironmentChange() {
    withEnvironment(apiService: MockService(serverConfig: ServerConfig.production), language: .en) {
      var environments: [EnvironmentType] = []
      var logout: DiscoveryParams?
      self.vm.onEnvironment = { environments.append($0) }
      self.vm.onLogout = { logout = $0 }
      self.vm.viewDidLoad()
      XCTAssertEqual(self.vm.data?.currentLanguage, "English")
      XCTAssertEqual(self.vm.data?.currentEnvironment, "Production")
      self.vm.setEnvironment(.production)
      XCTAssertTrue(environments.isEmpty)
      self.vm.setEnvironment(.staging)
      XCTAssertEqual(environments, [.staging])
      XCTAssertEqual(self.vm.data?.currentEnvironment, "Staging")
      self.vm.didUpdateEnvironment()
      XCTAssertNotNil(logout)
    }
  }

  func testLanguageRowsAndFeedback() {
    withEnvironment(apiService: MockService(serverConfig: ServerConfig.staging), language: .en) {
      var languages: [Language] = []
      var rows: [BetaToolsRow] = []
      var feedback: [Bool] = []
      self.vm.onLanguage = { languages.append($0) }
      self.vm.onSelectRow = { rows.append($0) }
      self.vm.onFeedback = { feedback.append($0) }
      self.vm.viewDidLoad()
      self.vm.setCurrentLanguage(.en)
      self.vm.setCurrentLanguage(.de)
      self.vm.setCurrentLanguage(.de)
      XCTAssertEqual(languages, [.de])
      XCTAssertEqual(self.vm.data?.currentLanguage, "German")
      BetaToolsRow.allCases.forEach { self.vm.didSelectBetaToolsRow($0) }
      XCTAssertEqual(rows, BetaToolsRow.allCases)
      self.vm.betaFeedbackButtonTapped(canSendMail: true)
      self.vm.betaFeedbackButtonTapped(canSendMail: false)
      XCTAssertEqual(feedback, [true, false])
    }
  }
}
