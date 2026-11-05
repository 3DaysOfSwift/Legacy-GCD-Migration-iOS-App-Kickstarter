@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class PledgeExpandableRewardsHeaderViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  internal let vm = PledgeExpandableRewardsHeaderViewModel()

  private let loadRewardsIntoDataSource = Recorder<[PledgeExpandableRewardsHeaderItem]>()
  private let expandRewards = Recorder<Bool>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onRewards = { [weak self] in self?.loadRewardsIntoDataSource.record($0) }
    self.vm.onExpansion = { [weak self] in self?.expandRewards.record($0) }
  }

  func testLoadRewardsIntoDataSource() {
    self.loadRewardsIntoDataSource.assertDidNotEmitValue()

    let reward1 = Reward.template
      |> Reward.lens.id .~ Int(1)
      |> Reward.lens.title .~ "Reward 1"
      |> Reward.lens.estimatedDeliveryOn .~ 1_475_361_315
      |> Reward.lens.minimum .~ 60

    let reward2 = Reward.template
      |> Reward.lens.id .~ Int(2)
      |> Reward.lens.title .~ "Reward 2"
      |> Reward.lens.estimatedDeliveryOn .~ 1_475_461_315
      |> Reward.lens.minimum .~ 20

    let reward3 = Reward.template
      |> Reward.lens.id .~ Int(3)
      |> Reward.lens.title .~ "Reward 3"
      |> Reward.lens.estimatedDeliveryOn .~ 1_475_561_315
      |> Reward.lens.minimum .~ 40

    let data = PledgeExpandableRewardsHeaderViewData(
      rewards: [reward1, reward2, reward3],
      selectedQuantities: [reward1.id: 1, reward2.id: 2, reward3.id: 3],
      currencyCode: Project.Country.us.currencyCode,
      omitCurrencyCode: false
    )

    self.vm.configure(with: data)
    self.vm.viewDidLoad()

    self.loadRewardsIntoDataSource.assertValueCount(1)

    guard let itemData = self.loadRewardsIntoDataSource.lastValue else {
      XCTFail("Should have data")
      return
    }

    XCTAssertEqual(itemData.count, 4)

    XCTAssertEqual(itemData[0].data.text, "Estimated delivery October 2016")
    XCTAssertEqual(itemData[0].data.amount.string, " US$ 220")
    XCTAssertEqual(itemData[0].isHeader, true)
    XCTAssertEqual(itemData[0].isReward, false)

    XCTAssertEqual(itemData[1].data.text, "Reward 1")
    XCTAssertEqual(itemData[1].data.amount.string, "US$ 60")
    XCTAssertEqual(itemData[1].isHeader, false)
    XCTAssertEqual(itemData[1].isReward, true)

    XCTAssertEqual(itemData[2].data.text, "2 x Reward 2")
    XCTAssertEqual(itemData[2].data.amount.string, "US$ 40")
    XCTAssertEqual(itemData[2].isHeader, false)
    XCTAssertEqual(itemData[2].isReward, true)

    XCTAssertEqual(itemData[3].data.text, "3 x Reward 3")
    XCTAssertEqual(itemData[3].data.amount.string, "US$ 120")
    XCTAssertEqual(itemData[3].isHeader, false)
    XCTAssertEqual(itemData[3].isReward, true)
  }

  func testConfigurationAfterViewLoadsAndMissingDeliveryDate() {
    self.vm.viewDidLoad()
    let noDate = Reward.template |> Reward.lens.estimatedDeliveryOn .~ nil
    let data = PledgeExpandableRewardsHeaderViewData(
      rewards: [noDate], selectedQuantities: [:], currencyCode: "USD", omitCurrencyCode: false
    )
    self.vm.configure(with: data)
    self.loadRewardsIntoDataSource.assertDidNotEmitValue()
    let dated = Reward.template |> Reward.lens.estimatedDeliveryOn .~ 1_475_361_315
    self.vm.configure(with: .init(
      rewards: [dated], selectedQuantities: [:], currencyCode: "USD", omitCurrencyCode: false
    ))
    self.loadRewardsIntoDataSource.assertValueCount(1)
  }

  func testExpandRewards() {
    self.expandRewards.assertDidNotEmitValue()

    let data = PledgeExpandableRewardsHeaderViewData(
      rewards: [.template, .template, .template],
      selectedQuantities: [:],
      currencyCode: Project.Country.us.currencyCode,
      omitCurrencyCode: false
    )

    self.vm.configure(with: data)
    self.vm.viewDidLoad()

    self.expandRewards.assertDidNotEmitValue()

    self.vm.expandButtonTapped()

    self.expandRewards.assertValues([true])

    self.vm.expandButtonTapped()

    self.expandRewards.assertValues([true, false])

    self.vm.expandButtonTapped()

    self.expandRewards.assertValues([true, false, true])
  }
}

private final class Recorder<Value> {
  private var values: [Value] = []
  var lastValue: Value? { self.values.last }
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
