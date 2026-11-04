@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import XCTest

@MainActor
final class PledgePaymentPlansViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  // MARK: Properties

  private var vm: PledgePaymentPlansViewModel = PledgePaymentPlansViewModel()

  private var reloadPaymentPlansPlanType = PlanRecorder<PledgePaymentPlansType>()
  private var notifyDelegatePaymentPlanSelected = PlanRecorder<PledgePaymentPlansType>()
  private var notifyDelegateTermsOfUseTapped = PlanRecorder<HelpType>()
  private var isLoading = PlanRecorder<Bool>()

  private let selectionData = PledgePaymentPlansAndSelectionData(
    selectedPlan: .pledgeInFull,
    project: Project.template
  )

  // MARK: Lifecycle

  override func setUp() async throws {
    try await super.setUp()

    self.vm.onPlanSelected = { [weak self] in self?.notifyDelegatePaymentPlanSelected.record($0) }
    self.vm.onReload = { [weak self] in self?.reloadPaymentPlansPlanType.record($0.selectedPlan) }
    self.vm.onTerms = { [weak self] in self?.notifyDelegateTermsOfUseTapped.record($0) }
    self.vm.onLoading = { [weak self] in self?.isLoading.record($0) }
  }

  // MARK: Test cases

  func testPaymenPlans_DefaultState() {
    withEnvironment {
      self.vm.viewDidLoad()

      self.reloadPaymentPlansPlanType.assertDidNotEmitValue()
      self.notifyDelegatePaymentPlanSelected.assertDidNotEmitValue()
    }
  }

  func testPaymenPlans_WithConfigureData() {
    withEnvironment {
      self.vm.viewDidLoad()

      self.vm.configure(with: self.selectionData)
      self.reloadPaymentPlansPlanType.assertValues([.pledgeInFull])
      self.notifyDelegatePaymentPlanSelected.assertDidNotEmitValue()
    }
  }

  func testPaymenPlans_PledgeInFullSelected() {
    withEnvironment {
      self.vm.viewDidLoad()

      self.vm.configure(with: self.selectionData)
      self.reloadPaymentPlansPlanType.assertValues([.pledgeInFull])
      self.vm.didSelectPlanType(.pledgeInFull)
      self.reloadPaymentPlansPlanType.assertValues([.pledgeInFull, .pledgeInFull])
      self.notifyDelegatePaymentPlanSelected.assertValues([.pledgeInFull])
    }
  }

  func testPaymenPlans_PledgeOverTimeSelected() {
    withEnvironment {
      self.vm.viewDidLoad()

      self.vm.configure(with: self.selectionData)
      self.reloadPaymentPlansPlanType.assertValues([.pledgeInFull])
      self.vm.didSelectPlanType(.pledgeOverTime)
      self.reloadPaymentPlansPlanType.assertValues([.pledgeInFull, .pledgeOverTime])
      self.notifyDelegatePaymentPlanSelected.assertValues([.pledgeOverTime])
    }
  }

  func testPaymenPlans_TermsOfUseTapped() {
    self.vm.viewDidLoad()

    self.vm.configure(with: self.selectionData)
    self.vm.didTapTermsOfUse(with: .terms)

    self.notifyDelegateTermsOfUseTapped.assertValues([HelpType.terms])
  }

  func testIsLoading_startsOnViewDidLoad_stopsWhenConfigDataIsSet() {
    self.isLoading.assertDidNotEmitValue()

    self.vm.viewDidLoad()
    self.isLoading.assertValues([true])

    self.vm.configure(with: self.selectionData)
    self.isLoading.assertValues([true, false])
  }

  func testIsLoading_sendsFalse_ifDataIsSetBeforeViewDidLoad() {
    self.isLoading.assertDidNotEmitValue()

    self.vm.configure(with: self.selectionData)
    self.isLoading.assertValues([false])

    self.vm.viewDidLoad()

    self.isLoading.assertValues([false])
  }
}

private final class PlanRecorder<Value: Equatable> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, file: file, line: line)
  }
}
