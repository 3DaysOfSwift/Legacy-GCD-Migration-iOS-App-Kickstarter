@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import UIKit
import XCTest

@MainActor
internal final class BackingCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  fileprivate let vm: BackingCellViewModel = BackingCellViewModel()

  private let backingInfoButtonIsHidden = BackingRecorder<Bool>()
  fileprivate let delivery = BackingRecorder<String>()
  fileprivate let pledged = BackingRecorder<String>()
  fileprivate let reward = BackingRecorder<String>()
  fileprivate let rootStackViewAlignment = BackingRecorder<UIStackView.Alignment>()

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onDisplay = { [weak self] display in
      self?.backingInfoButtonIsHidden.values.append(display.isBackingInfoHidden)
      self?.pledged.values.append(display.pledged)
      self?.reward.values.append(display.reward)
      self?.delivery.values.append(display.delivery)
      self?.rootStackViewAlignment.values.append(display.alignment)
    }
  }

  func testOutputs() {
    let reward = .template |> Reward.lens.estimatedDeliveryOn .~ Date().timeIntervalSince1970
    let backing = .template |> Backing.lens.reward .~ reward

    self.backingInfoButtonIsHidden.assertValueCount(0)
    self.pledged.assertValueCount(0)

    self.vm.configureWith(backing: backing, project: Project.template, isFromBacking: true)

    self.backingInfoButtonIsHidden.assertValues([true])
    self.pledged.assertValueCount(1)
    self.reward.assertValues([(backing.reward?.description)!])
    self.delivery.assertValues([
      Strings.backing_info_estimated_delivery_date(
        delivery_date:
        Format.date(
          secondsInUTC: reward.estimatedDeliveryOn!, template: DateFormatter.monthYear, timeZone: UTCTimeZone
        )
      )
    ], "Emits the estimated delivery date")

    self.rootStackViewAlignment.assertValues([UIStackView.Alignment.leading])
  }

  func testRootStackViewAlignment() {
    let reward = .template |> Reward.lens.estimatedDeliveryOn .~ Date().timeIntervalSince1970
    let backing = .template |> Backing.lens.reward .~ reward

    withEnvironment(isVoiceOverRunning: { true }) {
      self.vm.configureWith(backing: backing, project: Project.template, isFromBacking: true)

      self.rootStackViewAlignment.assertValues([UIStackView.Alignment.fill])
    }
  }

  func testShowBackingInfoButton() {
    let reward = .template |> Reward.lens.estimatedDeliveryOn .~ Date().timeIntervalSince1970
    let backing = .template |> Backing.lens.reward .~ reward

    self.backingInfoButtonIsHidden.assertValueCount(0)

    self.vm.configureWith(backing: backing, project: Project.template, isFromBacking: false)

    self.backingInfoButtonIsHidden.assertValues([false])
  }
}

private final class BackingRecorder<Value: Equatable> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
