@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class PledgeAmountSummaryViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let vm = PledgeAmountSummaryViewModel()

  private let bonusAmountText = SummaryRecorder<String>()
  private let bonusAmountStackViewIsHidden = SummaryRecorder<Bool>()
  private let pledgeAmountText = SummaryRecorder<String>()
  private let shippingAmountText = SummaryRecorder<String>()
  private let shippingLocationStackViewIsHidden = SummaryRecorder<Bool>()
  private let shippingLocationText = SummaryRecorder<String>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onDisplay = { [weak self] display in
      guard let self else { return }
      if let value = display.bonus { self.bonusAmountText.record(value.string) }
      self.bonusAmountStackViewIsHidden.record(display.bonusHidden)
      if let value = display.pledge { self.pledgeAmountText.record(value.string) }
      if let value = display.shipping { self.shippingAmountText.record(value.string) }
      self.shippingLocationStackViewIsHidden.record(display.shippingHidden)
      if let value = display.location { self.shippingLocationText.record(value) }
    }
  }

  func testTextOutputsEmitTheCorrectValue_US_ProjectCountryCode() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 5,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 23,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.bonusAmountText.assertValue("+$5.00")
    self.pledgeAmountText.assertValue("$23.00")
    self.shippingAmountText.assertValue("+$7.00")
    self.shippingLocationText.assertValue("Shipping: United States")
  }

  func testTextOutputsEmitTheCorrectValue_NonUS_ProjectCountryCode() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 5,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "Mexico",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.mx.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 23,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.bonusAmountText.assertValue("+ MX$ 5.00")
    self.pledgeAmountText.assertValue(" MX$ 23.00")
    self.shippingAmountText.assertValue("+ MX$ 7.00")
    self.shippingLocationText.assertValue("Shipping: Mexico")
  }

  func testTextOutputsEmitTheCorrectValue_ZeroShippingAmount() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.pledgeAmountText.assertValue("$30.00")
    self.shippingAmountText.assertValue("+$0.00")
    self.shippingLocationText.assertValue("Shipping: United States")
  }

  func testShippingLocationStackViewIsHidden_isTrue_WhenLocationNameIsNil() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.shippingLocationStackViewIsHidden.assertValue(true)
  }

  func testShippingLocationStackViewIsHidden_isTrue_WhenShippingAmountIsHidden() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: true,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.shippingLocationStackViewIsHidden.assertValue(true)
  }

  func testShippingLocationStackViewIsHidden_isFalse_WhenLocationNameIsNotNil() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.shippingLocationStackViewIsHidden.assertValue(false)
  }

  func testShippingLocationStackViewIsHidden_isTrue_WhenRewardIsLocalPickup() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: true
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.shippingLocationStackViewIsHidden.assertValue(true)
  }

  func testShippingLocationStackViewIsHidden_isFalse_WhenRewardIsNotLocalPickup() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: "United States",
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.shippingLocationStackViewIsHidden.assertValue(false)
  }

  func testBonusAmountStackViewIsHidden_isTrue_WhenIsNoReward() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 1,
      bonusAmountHidden: false,
      isNoReward: true,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 0,
      shippingAmount: 0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.bonusAmountStackViewIsHidden.assertValue(true)
  }

  func testBonusAmountStackViewIsHidden_isFalse_WhenIsNotNoReward() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 0,
      bonusAmountHidden: false,
      isNoReward: false,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 30,
      shippingAmount: 7.0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.bonusAmountStackViewIsHidden.assertValue(false)
  }

  func testBonusAmountStackViewIsHidden_isTrue_WhenBonusAmountHidden() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 1,
      bonusAmountHidden: true,
      isNoReward: true,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 0,
      shippingAmount: 0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.bonusAmountStackViewIsHidden.assertValue(true)
  }

  func testPledgeAmountText_NoReward_NonUS_ProjectCurrencyCode() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 2,
      bonusAmountHidden: false,
      isNoReward: true,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.es.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 0,
      shippingAmount: 0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.pledgeAmountText.assertValues(["€2.00"], "Bonus amount is used as pledge total for No Reward type")
  }

  func testPledgeAmountText_NoReward_US_ProjectCurrencyCode() {
    let data = PledgeAmountSummaryViewData(
      bonusAmount: 2,
      bonusAmountHidden: false,
      isNoReward: true,
      locationName: nil,
      omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode,
      pledgedOn: 1_568_666_243.0,
      rewardMinimum: 0,
      shippingAmount: 0,
      shippingAmountHidden: false,
      rewardIsLocalPickup: false
    )

    self.vm.configureWith(data)
    self.vm.viewDidLoad()

    self.pledgeAmountText.assertValues(["$2.00"], "Bonus amount is used as pledge total for No Reward type")
  }
}

private final class SummaryRecorder<Value: Equatable> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values, [expected], file: file, line: line) }
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(self.values, expected, message, file: file, line: line) }
}
