@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import XCTest

@MainActor
final class PledgePaymentPlansOptionViewModelTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  // MARK: Properties

  private var vm: PledgePaymentPlansOptionViewModel = PledgePaymentPlansOptionViewModel()

  private var selectionIndicatorImageName = OptionRecorder<String>()
  private var titleText = OptionRecorder<String>()
  private var subtitleText = OptionRecorder<String>()
  private var subtitleLabelHidden = OptionRecorder<Bool>()
  private var notifyDelegatePaymentPlanOptionSelected = OptionRecorder<PledgePaymentPlansType>()
  private var plotSelectedStackViewHidden = OptionRecorder<Bool>()
  private var paymentIncrements = OptionRecorder<[PledgePaymentIncrementFormatted]>()
  private var ineligibleBadgeHidden = OptionRecorder<Bool>()
  private var ineligibleBadgeText = OptionRecorder<String>()

  // MARK: Const

  private let pledgeInFullTitle = Strings.Pledge_in_full()
  private let pledgeOverTimeTitle = Strings.Pledge_Over_Time()
  private let pledgeOverTimeSubtitle = Strings
    .You_will_be_charged_for_your_pledge_over_four_payments_collapsed_description()
  private let pledgeOverTimeFullSubtitle =
    """
    \(
      Strings
        .You_will_be_charged_for_your_pledge_over_four_payments_collapsed_description()
    )

    \(Strings.The_first_charge_will_occur_when_the_project_ends_successfully())
    """
  private let selectedImageName = "icon-payment-method-selected"
  private let unselectedImageName = "icon-payment-method-unselected"

  // MARK: Lifecycle

  override func setUp() async throws {
    try await super.setUp()
    self.vm.onSelected = { [weak self] in self?.notifyDelegatePaymentPlanOptionSelected.record($0) }
  }

  private func configureWith(data: PledgePaymentPlanOptionData) {
    let display = self.vm.configureWith(data: data)
    self.selectionIndicatorImageName.record(display.selectionImage)
    self.titleText.record(display.title)
    self.subtitleText.record(display.subtitle)
    self.subtitleLabelHidden.record(display.subtitleHidden)
    self.plotSelectedStackViewHidden.record(display.plotHidden)
    if let increments = display.increments { self.paymentIncrements.record(increments) }
    self.ineligibleBadgeHidden.record(display.ineligibleHidden)
    if let text = display.ineligibleText { self.ineligibleBadgeText.record(text) }
  }

  // MARK: Test cases

  func testPaymentPlanOption_PledgeinFull_Selected() {
    let data = PledgePaymentPlanOptionData(
      ineligible: false,
      type: .pledgeInFull,
      selectedType: .pledgeInFull,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )
    self.configureWith(data: data)

    self.titleText.assertValue(self.pledgeInFullTitle)
    self.subtitleText.assertValue("")
    self.subtitleLabelHidden.assertValue(true)
    self.plotSelectedStackViewHidden.assertValue(true)
    self.selectionIndicatorImageName.assertValue(self.selectedImageName)
    self.paymentIncrements.assertValues([])
    self.ineligibleBadgeHidden.assertValue(true)
    self.ineligibleBadgeText.assertDidNotEmitValue()
  }

  func testPaymentPlanOption_PledgeinFull_Unselected() {
    let data = PledgePaymentPlanOptionData(
      ineligible: false,
      type: .pledgeInFull,
      selectedType: .pledgeOverTime,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )
    self.configureWith(data: data)

    self.titleText.assertValue(self.pledgeInFullTitle)
    self.subtitleText.assertValue("")
    self.subtitleLabelHidden.assertValue(true)
    self.plotSelectedStackViewHidden.assertValue(true)
    self.selectionIndicatorImageName.assertValue(self.unselectedImageName)
    self.paymentIncrements.assertValues([])
    self.ineligibleBadgeHidden.assertValue(true)
    self.ineligibleBadgeText.assertDidNotEmitValue()
  }

  func testPaymentPlanOption_PledgeOverTime_Selected() {
    let increments = mockPaymentIncrements()
    let project = Project.template
    let incrementsFormatted = paymentIncrementsFormatted(from: increments)
    let data = PledgePaymentPlanOptionData(
      ineligible: false,
      type: .pledgeOverTime,
      selectedType: .pledgeOverTime,
      paymentIncrements: increments,
      project: project
    )

    self.configureWith(data: data)

    self.titleText.assertValue(self.pledgeOverTimeTitle)
    self.subtitleText.assertValue(self.pledgeOverTimeFullSubtitle)
    self.subtitleLabelHidden.assertValue(false)
    self.plotSelectedStackViewHidden.assertValue(false)

    self.selectionIndicatorImageName.assertValue(self.selectedImageName)
    self.paymentIncrements.assertValues([incrementsFormatted])
    self.ineligibleBadgeHidden.assertValue(true)
    self.ineligibleBadgeText.assertDidNotEmitValue()
  }

  func testPaymentPlanOption_PledgeOverTime_Unselected() {
    let data = PledgePaymentPlanOptionData(
      ineligible: false,
      type: .pledgeOverTime,
      selectedType: .pledgeInFull,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )
    self.configureWith(data: data)

    self.titleText.assertValue(self.pledgeOverTimeTitle)
    self.subtitleText.assertValue(self.pledgeOverTimeSubtitle)
    self.subtitleLabelHidden.assertValue(false)
    self.plotSelectedStackViewHidden.assertValue(true)
    self.selectionIndicatorImageName.assertValue(self.unselectedImageName)
    self.paymentIncrements.assertValues([])
    self.ineligibleBadgeHidden.assertValue(true)
    self.ineligibleBadgeText.assertDidNotEmitValue()
  }

  func testSelectingLaterProvidesInstallmentsOnlyOnce() throws {
    let data = PledgePaymentPlanOptionData(
      ineligible: false, type: .pledgeOverTime, selectedType: .pledgeInFull,
      paymentIncrements: mockPaymentIncrements(), project: Project.template
    )
    XCTAssertNil(self.vm.configureWith(data: data).increments)
    let selected = try XCTUnwrap(self.vm.refreshSelectedType(.pledgeOverTime))
    XCTAssertEqual(selected.increments?.count, data.paymentIncrements.count)
    XCTAssertNil(self.vm.refreshSelectedType(.pledgeOverTime)?.increments)
    XCTAssertTrue(try XCTUnwrap(self.vm.refreshSelectedType(.pledgeInFull)).plotHidden)
  }

  func testPaymentPlanOption_OptionTapped() {
    let data = PledgePaymentPlanOptionData(
      ineligible: false,
      type: .pledgeOverTime,
      selectedType: .pledgeInFull,
      paymentIncrements: mockPaymentIncrements(),
      project: Project.template
    )
    self.configureWith(data: data)
    self.vm.optionTapped()
    self.notifyDelegatePaymentPlanOptionSelected.assertValue(.pledgeOverTime)
  }

  func testPaymentPlanOption_PledgeOverTime_Ineligible() {
    let project = Project.template
    let thresholdAmountString = "$125"
    let ineligibleText = Strings.Available_for_pledges_over(amount: thresholdAmountString)

    let data = PledgePaymentPlanOptionData(
      ineligible: true,
      type: .pledgeOverTime,
      selectedType: .pledgeInFull,
      paymentIncrements: [],
      project: project
    )

    self.configureWith(data: data)

    self.titleText.assertValue(self.pledgeOverTimeTitle)
    self.ineligibleBadgeHidden.assertValue(false)
    self.ineligibleBadgeText.assertValue(ineligibleText)
  }
}

@MainActor
private func paymentIncrementsFormatted(from increments: [PledgePaymentIncrement])
  -> [PledgePaymentIncrementFormatted] {
  increments.enumerated().map {
    PledgePaymentIncrementFormatted(from: $1, index: $0)
  }
}

private final class OptionRecorder<Value: Equatable> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, [expected], file: file, line: line)
  }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, file: file, line: line)
  }
}
