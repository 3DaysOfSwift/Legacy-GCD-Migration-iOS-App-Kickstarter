@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class SettingsAccountViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private lazy var feature = SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  )
  private lazy var vm = SettingsAccountViewModel(feature: self.feature, sleep: { _ in })

  func testAccountFieldsAndSelection() async {
    let service = MockService(fetchGraphUserResult: .success(UserEnvelope(me: GraphUser.template)))
    await withEnvironment(apiService: service) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear()
      await self.vm.waitForLoad()
      XCTAssertEqual(self.vm.data?.currency, .USD)
      XCTAssertEqual(self.vm.data?.email, "user@example.com")
      XCTAssertEqual(self.vm.data?.shouldHideEmailWarning, true)
      var selected: SettingsAccountCellType?
      self.vm.onSelect = { type, _ in selected = type }
      self.vm.didSelectRow(cellType: .changeEmail)
      XCTAssertEqual(selected, .changeEmail)
      self.vm.viewWillAppear()
      await self.vm.waitForLoad()
      XCTAssertEqual(self.vm.data?.currency, .USD)
    }
  }

  func testAccountPresentationForPasswordAndAppleStates() async {
    for (hasPassword, apple) in [(false, false), (true, false), (false, true)] {
      let user = GraphUser.template |> \.hasPassword .~ hasPassword |> \.isAppleConnected .~ apple
      await withEnvironment(apiService: MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))) {
        self.vm.viewDidLoad()
        await self.vm.waitForLoad()
        XCTAssertEqual(self.vm.data?.shouldHideEmailPasswordSection, !hasPassword || apple)
        XCTAssertEqual(self.vm.data?.isAppleConnectedAccount, apple)
        XCTAssertEqual(self.vm.createPasswordFooter?.0, !hasPassword && !apple)
      }
    }
  }

  func testEmailWarningsAndFetchFailure() async {
    for (verified, deliverable) in [(false, true), (true, false), (true, true)] {
      let user = GraphUser.template |> \.isEmailVerified .~ verified |> \.isDeliverable .~ deliverable
      await withEnvironment(apiService: MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))) {
        self.vm.viewDidLoad()
        await self.vm.waitForLoad()
        XCTAssertEqual(self.vm.data?.shouldHideEmailWarning, verified && deliverable)
      }
    }
    await withEnvironment(apiService: MockService(fetchGraphUserResult: .failure(.couldNotParseJSON))) {
      var failed = false
      self.vm.onFetchError = { failed = true }
      self.vm.viewDidLoad()
      await self.vm.waitForLoad()
      XCTAssertTrue(failed)
    }
  }
}
