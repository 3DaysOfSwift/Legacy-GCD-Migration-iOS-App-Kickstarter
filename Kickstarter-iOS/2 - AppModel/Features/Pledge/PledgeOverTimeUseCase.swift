import Foundation
import KsApi
import Observation
import Prelude

@MainActor
@Observable
public final class PledgeOverTimeUseCase {
  public private(set) var showPledgeOverTimeUI = false
  public private(set) var pledgeOverTimeIsLoading = false
  public private(set) var pledgeOverTimeConfigData: PledgePaymentPlansAndSelectionData?
  var onShow: ((Bool) -> Void)?
  var onLoading: ((Bool) -> Void)?
  var onConfig: ((PledgePaymentPlansAndSelectionData?) -> Void)?
  var onRequest: ((String, String) -> Void)?
  private let feature: PledgeFeature
  private let route = UUID()
  private var project: Project?
  private var total: Double?
  private var context: PledgeViewContext?
  private var selectedPlan: PledgePaymentPlansType?
  private var latestPlan: PledgePaymentPlansAndSelectionData?
  private var emittedConfig = false
  private var lastConfigWasNil = false
  private var lastLoading: Bool?
  private var planRevision = UUID()
  @ObservationIgnored private var planTask: Task<Void, Never>?

  init(feature: PledgeFeature = AppModel.shared.pledgeFeature) { self.feature = feature }

  func updateProject(_ project: Project) {
    self.project = project
    self.publishAvailability()
    self.requestPlan()
  }
  func updateTotal(_ total: Double) {
    guard self.total != total else { return }
    self.total = total
    self.requestPlan()
  }
  func updateContext(_ context: PledgeViewContext) {
    self.context = context
    self.publishAvailability()
  }
  func paymentPlanSelected(_ plan: PledgePaymentPlansType) {
    self.selectedPlan = plan
    if var latest = self.latestPlan {
      latest.selectedPlan = plan
      self.publishConfig(latest)
    }
  }

  private func publishAvailability() {
    guard let project = self.project, let context = self.context else { return }
    let enabled = project.isPledgeOverTimeAllowed == true && context.isAny(of: .pledge, .editPledgeOverTime)
    self.showPledgeOverTimeUI = enabled
    self.onShow?(enabled)
    self.publishLoading(enabled)
    if !enabled { self.publishConfig(nil) }
  }

  private func requestPlan() {
    guard let project = self.project, let total = self.total else { return }
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let amount = formatter.string(from: NSNumber(value: total)) ?? ""
    self.onRequest?(project.slug, amount)
    self.planTask?.cancel()
    let revision = UUID()
    self.planRevision = revision
    let command = self.feature.requestPaymentPlan(route: self.route, slug: project.slug, amount: amount)
    self.planTask = Task { [weak self] in
      do {
        let plan = try await command.value
        try Task.checkCancellation()
        guard let self, self.planRevision == revision else { return }
        self.publishLoading(false)
        guard let plan else { self.publishConfig(nil); return }
        let preselected = project.personalization.backing?.paymentIncrements.isEmpty == false
        let defaultPlan: PledgePaymentPlansType = preselected && plan.amountIsPledgeOverTimeEligible
          ? .pledgeOverTime : .pledgeInFull
        let data = PledgePaymentPlansAndSelectionData(
          selectedPlan: defaultPlan, increments: plan.paymentIncrements,
          ineligible: !plan.amountIsPledgeOverTimeEligible, project: project
        )
        self.latestPlan = data
        self.publishConfig(data)
        if let selected = self.selectedPlan {
          var changed = data
          changed.selectedPlan = selected
          self.publishConfig(changed)
        }
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), let self, self.planRevision == revision else { return }
        self.showPledgeOverTimeUI = false
        self.onShow?(false)
        self.publishConfig(nil)
        self.publishLoading(false)
      }
    }
  }

  private func publishLoading(_ loading: Bool) {
    self.pledgeOverTimeIsLoading = loading
    guard self.lastLoading != loading else { return }
    self.lastLoading = loading
    self.onLoading?(loading)
  }
  private func publishConfig(_ data: PledgePaymentPlansAndSelectionData?) {
    guard !(self.emittedConfig && self.lastConfigWasNil && data == nil) else { return }
    self.emittedConfig = true
    self.lastConfigWasNil = data == nil
    self.pledgeOverTimeConfigData = data
    self.onConfig?(data)
  }
  func waitForPlan() async { await self.planTask?.value }
  deinit {
    self.planTask?.cancel()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.releaseRead(route: route) }
  }
}
