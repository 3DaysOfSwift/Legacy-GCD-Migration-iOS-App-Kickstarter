@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class PledgeOverTimePaymentScheduleViewModelTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  // MARK: Properties

  private var vm: PledgeOverTimePaymentScheduleViewModelType = PledgeOverTimePaymentScheduleViewModel()

  private var collapsed = TestObserver<Bool, Never>()
  private var paymentScheduleItems = TestObserver<[PLOTPaymentScheduleItem], Never>()

  private lazy var increments = mockPaymentIncrementsForManagingBacking()
  private lazy var expectedItems = {
    self.increments.map { PLOTPaymentScheduleItem(with: $0) }
  }()

  // MARK: Lifecycle

  override func setUp() async throws {
    try await super.setUp()

    self.vm.outputs.collapsed
      .observe(self.collapsed.observer)

    self.vm.outputs.paymentScheduleItems
      .observe(self.paymentScheduleItems.observer)
  }

  // MARK: Test cases

  func testCollapseToggle_Collapsed() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.configure(with: self.increments)
    self.vm.inputs.collapseToggle()
    self.vm.inputs.collapseToggle()

    self.collapsed.assertValues([false, true])
    self.paymentScheduleItems.assertValue(self.expectedItems)
  }

  func testCollapseToggle_Expanded() {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.configure(with: self.increments)
    self.vm.inputs.collapseToggle()

    self.collapsed.assertValues([false])
    self.paymentScheduleItems.assertValue(self.expectedItems)
  }
}
