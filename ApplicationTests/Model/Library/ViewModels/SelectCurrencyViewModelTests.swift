@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class SelectCurrencyViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SelectCurrencyViewModel(settingsFeature: self.feature, sleep: { _ in })

  override func setUp() async throws {
    try await super.setUp()
    AppEnvironment.login(AccessTokenEnvelope(accessToken: "fixture-token", user: .template))
  }

  func testSelectionAndSuccessfulSave() async {
    await withEnvironment(apiService: MockService(changeCurrencyResult: .success(EmptyResponseEnvelope()))) {
      var successes = 0
      self.vm.onSuccess = { successes += 1 }
      self.vm.configure(with: .USD)
      self.vm.viewDidLoad()
      XCTAssertEqual(self.vm.currencyRows.first?.currency, .USD)
      XCTAssertFalse(self.vm.saveButtonIsEnabled)
      let index = currencies(orderedBySelected: .USD).firstIndex(of: .AUD)!
      self.vm.didSelectCurrency(atIndex: index)
      XCTAssertTrue(self.vm.saveButtonIsEnabled)
      XCTAssertTrue(self.vm.currencyRows[index].selected)
      self.vm.saveButtonTapped()
      XCTAssertTrue(self.vm.isLoading)
      await self.vm.waitForSave()
      XCTAssertFalse(self.vm.isLoading)
      XCTAssertFalse(self.vm.saveButtonIsEnabled)
      XCTAssertEqual(successes, 1)
    }
  }

  func testFailedSaveKeepsSelectionAndAllowsRetry() async {
    await withEnvironment(apiService: MockService(changeCurrencyResult: .failure(.couldNotParseJSON))) {
      var error: String?
      self.vm.onFailure = { error = $0 }
      self.vm.configure(with: .USD)
      self.vm.viewDidLoad()
      self.vm.didSelectCurrency(atIndex: currencies(orderedBySelected: .USD).firstIndex(of: .AUD)!)
      self.vm.saveButtonTapped()
      await self.vm.waitForSave()
      XCTAssertEqual(error, ErrorEnvelope.couldNotParseJSON.localizedDescription)
      XCTAssertFalse(self.vm.isLoading)
      XCTAssertTrue(self.vm.saveButtonIsEnabled)
    }
  }
}
