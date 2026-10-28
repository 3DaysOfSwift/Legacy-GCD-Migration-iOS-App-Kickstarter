import Foundation
@testable import Kickstarter_Framework
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class SettingsAccountViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private var vm: SettingsAccountViewModelType!
  private var feature: SettingsFeature!

  private let fetchAccountFieldsError = TestObserver<Void, Never>()
  private let reloadDataCurrency = TestObserver<Currency, Never>()
  private let reloadDataEmail = TestObserver<String?, Never>()
  private let reloadDataIsAppleConnectedAccount = TestObserver<Bool, Never>()
  private let reloadDataShouldHideEmailPasswordSection = TestObserver<Bool, Never>()
  private let reloadDataShouldHideWarningIcon = TestObserver<Bool, Never>()

  internal override func setUp() async throws {
    try await super.setUp()
    self.feature = SettingsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
      makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
    )
    self.vm = SettingsAccountViewModel(feature: self.feature)
    self.vm.outputs.fetchAccountFieldsError.observe(self.fetchAccountFieldsError.observer)
    self.vm.outputs.reloadData.map { $0.currency }.observe(self.reloadDataCurrency.observer)
    self.vm.outputs.reloadData.map { $0.email }.observe(self.reloadDataEmail.observer)
    self.vm.outputs.reloadData.map { $0.shouldHideEmailWarning }
      .observe(self.reloadDataShouldHideWarningIcon.observer)
    self.vm.outputs.reloadData.map { $0.shouldHideEmailPasswordSection }
      .observe(self.reloadDataShouldHideEmailPasswordSection.observer)
    self.vm.outputs.reloadData.map { $0.isAppleConnectedAccount }
      .observe(self.reloadDataIsAppleConnectedAccount.observer)
  }

  func testReloadData() async {
    let userEnvelope = UserEnvelope(me: GraphUser.template)
    let mockService = MockService(fetchGraphUserResult: .success(userEnvelope))

    await withEnvironment(apiService: mockService) {
      self.reloadDataCurrency.assertValueCount(0)
      self.reloadDataEmail.assertValueCount(0)
      self.reloadDataIsAppleConnectedAccount.assertValueCount(0)
      self.reloadDataShouldHideEmailPasswordSection.assertValueCount(0)
      self.reloadDataShouldHideWarningIcon.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([false])
      self.reloadDataShouldHideEmailPasswordSection.assertValues([false])
      self.reloadDataShouldHideWarningIcon.assertValues([true])

      self.fetchAccountFieldsError.assertDidNotEmitValue()

      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValueCount(2)
      self.reloadDataEmail.assertValueCount(2)
      self.reloadDataIsAppleConnectedAccount.assertValueCount(2)
      self.reloadDataShouldHideEmailPasswordSection.assertValueCount(2)
      self.reloadDataShouldHideWarningIcon.assertValueCount(2)

      self.fetchAccountFieldsError.assertDidNotEmitValue()
    }
  }

  func testFetchUserAccountFields_Failure() async {
    let mockService = MockService(fetchGraphUserResult: .failure(.couldNotParseJSON))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValueCount(0)
      self.reloadDataEmail.assertValueCount(0)
      self.reloadDataIsAppleConnectedAccount.assertValueCount(0)
      self.reloadDataShouldHideEmailPasswordSection.assertValueCount(0)
      self.reloadDataShouldHideWarningIcon.assertValueCount(0)

      self.fetchAccountFieldsError.assertValueCount(1)
    }
  }

  func testHideEmailPasswordHeaderView_HasNoPassword() async {
    let user = GraphUser.template
      |> \.hasPassword .~ false

    let mockService = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([false])
      self.reloadDataShouldHideEmailPasswordSection
        .assertValues([true], "Change email & password options are hidden.")
      self.reloadDataShouldHideWarningIcon.assertValues([true])

      self.fetchAccountFieldsError.assertDidNotEmitValue()

      let shouldShowCreatePasswordFooter = self.vm.outputs.shouldShowCreatePasswordFooter()

      XCTAssertEqual(true, shouldShowCreatePasswordFooter?.0)
      XCTAssertEqual("user@example.com", shouldShowCreatePasswordFooter?.1)
    }
  }

  func testHideEmailPasswordHeaderView_HasPassword() async {
    let user = GraphUser.template
      |> \.hasPassword .~ true

    let mockService = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([false])
      self.reloadDataShouldHideEmailPasswordSection
        .assertValues([false], "Change email & password options are shown if user has set a password")
      self.reloadDataShouldHideWarningIcon.assertValues([true])

      self.fetchAccountFieldsError.assertDidNotEmitValue()

      let shouldShowCreatePasswordFooter = self.vm.outputs.shouldShowCreatePasswordFooter()

      XCTAssertEqual(false, shouldShowCreatePasswordFooter?.0)
      XCTAssertEqual("user@example.com", shouldShowCreatePasswordFooter?.1)
    }
  }

  func testHideEmailWarningIcon_WhenEmailIsNotVerified_AndIsDeliverable() async {
    let user = GraphUser.template
      |> \.hasPassword .~ true
      |> \.isEmailVerified .~ false
      |> \.isDeliverable .~ true

    let mockService = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([false])
      self.reloadDataShouldHideEmailPasswordSection.assertValues([false])
      self.reloadDataShouldHideWarningIcon
        .assertValues([false], "Warning icon is shown if email is unverified")

      self.fetchAccountFieldsError.assertDidNotEmitValue()
    }
  }

  func testHideEmailWarningIcon_WhenEmailIsVerified_ButNotDeliverable() async {
    let user = GraphUser.template
      |> \.hasPassword .~ true
      |> \.isEmailVerified .~ true
      |> \.isDeliverable .~ false

    let mockService = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([false])
      self.reloadDataShouldHideEmailPasswordSection.assertValues([false])
      self.reloadDataShouldHideWarningIcon
        .assertValues([false], "Warning icon is shown if email is undeliverable")

      self.fetchAccountFieldsError.assertDidNotEmitValue()
    }
  }

  func testIsAppleConnectedAccount() async {
    let user = GraphUser.template
      |> \.isAppleConnected .~ true

    let mockService = MockService(fetchGraphUserResult: .success(UserEnvelope(me: user)))

    await withEnvironment(apiService: mockService) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.feature.waitForOperations()
      await self.scheduler.advance()

      self.reloadDataCurrency.assertValues([.USD])
      self.reloadDataEmail.assertValues(["user@example.com"])
      self.reloadDataIsAppleConnectedAccount.assertValues([true])
      self.reloadDataShouldHideEmailPasswordSection.assertValues([true])
      self.reloadDataShouldHideWarningIcon.assertValues([true])

      self.fetchAccountFieldsError.assertDidNotEmitValue()
    }
  }
}
