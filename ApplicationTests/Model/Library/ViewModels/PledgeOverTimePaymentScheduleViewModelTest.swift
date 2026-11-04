@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import XCTest

@MainActor
final class PledgeOverTimePaymentScheduleViewModelTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  // MARK: Properties

  private var vm = PledgeOverTimePaymentScheduleViewModel()

  private lazy var increments = mockPaymentIncrementsForManagingBacking()
  private lazy var expectedItems = {
    self.increments.map { PLOTPaymentScheduleItem(with: $0) }
  }()

  // MARK: Test cases

  func testConfigurationBeforeLoading() {
    self.vm.configure(with: self.increments)
    XCTAssertNil(self.vm.paymentScheduleItems)
    self.vm.viewDidLoad()
    XCTAssertEqual(self.vm.paymentScheduleItems, self.expectedItems)
  }

  func testCollapseToggle_Collapsed() {
    self.vm.viewDidLoad()
    self.vm.configure(with: self.increments)
    self.vm.collapseToggle()
    self.vm.collapseToggle()

    XCTAssertTrue(self.vm.collapsed)
    XCTAssertEqual(self.vm.paymentScheduleItems, self.expectedItems)
  }

  func testCollapseToggle_Expanded() {
    self.vm.viewDidLoad()
    self.vm.configure(with: self.increments)
    self.vm.collapseToggle()

    XCTAssertFalse(self.vm.collapsed)
    XCTAssertEqual(self.vm.paymentScheduleItems, self.expectedItems)
  }
}
