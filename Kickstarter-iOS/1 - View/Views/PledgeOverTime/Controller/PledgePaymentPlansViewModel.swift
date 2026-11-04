import Foundation
import KsApi
import Observation

public enum PledgePaymentPlansType: Equatable {
  case pledgeInFull
  case pledgeOverTime
}

public struct PledgePaymentPlansAndSelectionData {
  public var ineligible: Bool
  public var paymentIncrements: [PledgePaymentIncrement]
  public var project: Project
  public var selectedPlan: PledgePaymentPlansType

  public init(
    selectedPlan: PledgePaymentPlansType,
    increments paymentIncrements: [PledgePaymentIncrement] = [],
    ineligible: Bool = false,
    project: Project
  ) {
    self.ineligible = ineligible
    self.paymentIncrements = paymentIncrements
    self.project = project
    self.selectedPlan = selectedPlan
  }

  public var isPledgeOverTime: Bool {
    self.selectedPlan == .pledgeOverTime
  }
}

@MainActor
@Observable
public final class PledgePaymentPlansViewModel {
  public private(set) var isLoading = true
  var onLoading: ((Bool) -> Void)?
  var onReload: ((PledgePaymentPlansAndSelectionData) -> Void)?
  var onPlanSelected: ((PledgePaymentPlansType) -> Void)?
  var onTerms: ((HelpType) -> Void)?
  private var configuration: PledgePaymentPlansAndSelectionData?
  private var hasLoaded = false
  private var previousSelection: PledgePaymentPlansType?
  public init() {}

  public func viewDidLoad() {
    self.hasLoaded = true
    if let configuration = self.configuration { self.onReload?(configuration) }
    else { self.isLoading = true; self.onLoading?(true) }
  }

  public func configure(with value: PledgePaymentPlansAndSelectionData) {
    self.configuration = value
    self.isLoading = false
    self.onLoading?(false)
    if self.hasLoaded { self.onReload?(value) }
  }

  public func didSelectPlanType(_ planType: PledgePaymentPlansType) {
    if self.hasLoaded, var configuration = self.configuration {
      configuration.selectedPlan = planType
      self.onReload?(configuration)
    }
    if self.previousSelection != planType {
      self.previousSelection = planType
      self.onPlanSelected?(planType)
    }
  }

  public func didTapTermsOfUse(with helpType: HelpType) { self.onTerms?(helpType) }
}
