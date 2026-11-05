@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class PledgeViewCTAContainerViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  let vm = PledgeViewCTAContainerViewModel()
  private let applePayButtonIsHidden = Recorder<Bool>()
  private let continueButtonIsHidden = Recorder<Bool>()
  private let notifyDelegateApplePayButtonTapped = Recorder<Void>()
  private let notifyDelegateOpenHelpType = Recorder<HelpType>()
  private let notifyDelegateSubmitButtonTapped = Recorder<Void>()
  private let notifyDelegateToGoToLoginSignup = Recorder<Void>()
  private let submitButtonIsEnabled = Recorder<Bool>()
  private let submitButtonIsHidden = Recorder<Bool>()
  private let submitButtonTitle = Recorder<String>()

  internal override func setUp() async throws {
    try await super.setUp()

    self.vm.onApplePay = { [weak self] in self?.notifyDelegateApplePayButtonTapped.record(()) }
    self.vm.onContinue = { [weak self] in self?.notifyDelegateToGoToLoginSignup.record(()) }
    self.vm.onSubmit = { [weak self] in self?.notifyDelegateSubmitButtonTapped.record(()) }
    self.vm.onHelp = { [weak self] in self?.notifyDelegateOpenHelpType.record($0) }
  }

  private func configureWith(value: PledgeViewCTAContainerViewData) {
    let display = self.vm.configureWith(value: value)
    self.applePayButtonIsHidden.record(display.applePayButtonIsHidden)
    self.continueButtonIsHidden.record(display.continueButtonIsHidden)
    self.submitButtonIsHidden.record(display.submitButtonIsHidden)
    self.submitButtonIsEnabled.record(display.submitButtonIsEnabled)
    self.submitButtonTitle.record(display.submitButtonTitle)
  }

  func testPledgeView_UserLoggedOut() {
    let context = PledgeViewContext.pledge

    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: false,
      isEnabled: true,
      context: context,
      willRetryPaymentMethod: false
    )

    self.submitButtonIsHidden.assertDidNotEmitValue()
    self.applePayButtonIsHidden.assertDidNotEmitValue()
    self.continueButtonIsHidden.assertDidNotEmitValue()
    self.submitButtonIsEnabled.assertDidNotEmitValue()

    self.configureWith(value: pledgeData)

    self.submitButtonIsHidden.assertValues([true])
    self.applePayButtonIsHidden.assertValues([true])
    self.continueButtonIsHidden.assertValues([false])
    self.submitButtonIsEnabled.assertValues([true])
  }

  func testPledgeView_UserLoggedIn() {
    let context = PledgeViewContext.pledge

    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: true,
      isEnabled: true,
      context: context,
      willRetryPaymentMethod: false
    )

    self.submitButtonIsHidden.assertDidNotEmitValue()
    self.applePayButtonIsHidden.assertDidNotEmitValue()
    self.continueButtonIsHidden.assertDidNotEmitValue()
    self.submitButtonIsEnabled.assertDidNotEmitValue()

    self.configureWith(value: pledgeData)

    self.submitButtonIsHidden.assertValues([false])
    self.applePayButtonIsHidden.assertValues([false])
    self.continueButtonIsHidden.assertValues([true])
    self.submitButtonIsEnabled.assertValues([true])
    self.submitButtonTitle.assertValues(["Pledge"])
  }

  func testPledgeView_UpdateContext() {
    let context = PledgeViewContext.update

    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: true,
      isEnabled: true,
      context: context,
      willRetryPaymentMethod: false
    )

    self.submitButtonIsHidden.assertDidNotEmitValue()
    self.applePayButtonIsHidden.assertDidNotEmitValue()
    self.continueButtonIsHidden.assertDidNotEmitValue()
    self.submitButtonIsEnabled.assertDidNotEmitValue()

    self.configureWith(value: pledgeData)

    self.submitButtonIsHidden.assertValues([false])
    self.applePayButtonIsHidden.assertValues([true])
    self.continueButtonIsHidden.assertValues([true])
    self.submitButtonIsEnabled.assertValues([true])
    self.submitButtonTitle.assertValues(["Confirm"])
  }

  func testPledgeView_ChangePaymentMethodContext() {
    let context = PledgeViewContext.changePaymentMethod

    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: true,
      isEnabled: true,
      context: context,
      willRetryPaymentMethod: false
    )

    self.submitButtonIsHidden.assertDidNotEmitValue()
    self.applePayButtonIsHidden.assertDidNotEmitValue()
    self.continueButtonIsHidden.assertDidNotEmitValue()
    self.submitButtonIsEnabled.assertDidNotEmitValue()

    self.configureWith(value: pledgeData)

    self.submitButtonIsHidden.assertValues([false])
    self.applePayButtonIsHidden.assertValues([false])
    self.continueButtonIsHidden.assertValues([true])
    self.submitButtonIsEnabled.assertValues([true])
    self.submitButtonTitle.assertValues(["Confirm"])
  }

  func testPledgeView_FixPaymentMethodContext_RetryingPaymentMethod() {
    let context = PledgeViewContext.fixPaymentMethod

    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: true,
      isEnabled: true,
      context: context,
      willRetryPaymentMethod: true
    )

    self.submitButtonIsHidden.assertDidNotEmitValue()
    self.applePayButtonIsHidden.assertDidNotEmitValue()
    self.continueButtonIsHidden.assertDidNotEmitValue()
    self.submitButtonIsEnabled.assertDidNotEmitValue()

    self.configureWith(value: pledgeData)

    self.submitButtonIsHidden.assertValues([false])
    self.applePayButtonIsHidden.assertValues([false])
    self.continueButtonIsHidden.assertValues([true])
    self.submitButtonIsEnabled.assertValues([true])
    self.submitButtonTitle.assertValues(["Retry"])
  }

  func testContinueButtonTapped() {
    let pledgeData = PledgeViewCTAContainerViewData(
      project: .template,
      total: 12,
      isLoggedIn: false,
      isEnabled: true,
      context: .pledge,
      willRetryPaymentMethod: false
    )

    self.configureWith(value: pledgeData)

    self.notifyDelegateToGoToLoginSignup.assertDidNotEmitValue()

    self.vm.continueButtonTapped()

    self.notifyDelegateToGoToLoginSignup.assertValueCount(1)
  }

  func testApplePayButtonTapped() {
    self.notifyDelegateApplePayButtonTapped.assertDidNotEmitValue()

    self.vm.applePayButtonTapped()

    self.notifyDelegateApplePayButtonTapped.assertValueCount(1)
  }

  func testNotifyDelegateOpenHelpType() {
    let baseUrl = AppEnvironment.current.apiService.serverConfig.webBaseUrl
    let allCases = HelpType.allCases.filter { $0 != .contact }

    let allHelpTypeUrls = allCases.map { $0.url(withBaseUrl: baseUrl) }.compact()

    allHelpTypeUrls.forEach { self.vm.tapped($0) }

    self.notifyDelegateOpenHelpType.assertValues(allCases)
  }

  func testSubmitButtonTapped() {
    self.notifyDelegateSubmitButtonTapped.assertDidNotEmitValue()

    self.vm.submitButtonTapped()

    self.notifyDelegateSubmitButtonTapped.assertValueCount(1)
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, file: file, line: line)
  }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable {
    XCTAssertEqual(self.values, expected, file: file, line: line)
  }
}
