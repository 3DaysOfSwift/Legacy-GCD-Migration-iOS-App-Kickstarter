import Foundation
import GraphAPI
import KsApi
import ReactiveSwift

@MainActor
public protocol PledgeOverTimeUseCaseInputs {
  func paymentPlanSelected(_ paymentPlan: PledgePaymentPlansType)
}

@MainActor
public protocol PledgeOverTimeUseCaseOutputs {
  var showPledgeOverTimeUI: Signal<Bool, Never> { get }
  var pledgeOverTimeConfigData: Signal<PledgePaymentPlansAndSelectionData?, Never> { get }
  var pledgeOverTimeIsLoading: Signal<Bool, Never> { get }

  // Visible only for testing
  var buildPaymentPlanInputs: Signal<(String, String), Never> { get }
}

@MainActor
public protocol PledgeOverTimeUseCaseType {
  var inputs: PledgeOverTimeUseCaseInputs { get }
  var outputs: PledgeOverTimeUseCaseOutputs { get }
}

/**
 A component view model for Pledge Over Time in the pledge checkout flow.
 Creates one BuildPaymentPlanQuery and uses those results to create data for the UI.

 Inputs:
  - `project`: A project.
  - `pledgeTotal`: Total amount to pledge, a double.
  - `paymentPlanSelected:`: The payment plan selected by the user.

 A `project` and `pledgeTotal` are required before `showPledgeOverTimeUI` or `pledgeOverTimeIsLoading` will send.

 If `showPledgeOverTimeUI` is false, or if a server error occurs, the model will immediately send `nil` for `pledgeOverTimeConfigData`.
 Otherwise, `pledgeOverTimeConfigData` sends after the BuildPaymentPlanQuery loads. It will also send again each time `paymentPlanSelected:` is called.

 Outputs:
  - `showPledgeOverTimeUI`:  Whether the PLOT module should be shown. Sends one or more events. The PLOT module should disappear if an error occurs in the BuildPaymentPlanQuery.
  - `pledgeOverTimeConfigData`: Info needed to display the PLOT module. Sends one or more events.
  - `pledgeOverTimeIsLoading`: Whether the PLOT module is loading. Sends one or more events.
 */

@MainActor
public final class PledgeOverTimeUseCase: PledgeOverTimeUseCaseType, PledgeOverTimeUseCaseInputs,
  PledgeOverTimeUseCaseOutputs
{
  init(
    project: Signal<Project, Never>,
    pledgeTotal: Signal<Double, Never>,
    context: Signal<PledgeViewContext, Never>,
    feature: PledgeFeature = AppModel.shared.pledgeFeature
  ) {
    self.feature = feature
    let route = self.route
    let pledgeOverTimeUIEnabled = Signal.combineLatest(project, context)
      .map { project, context -> Bool in
        project.isPledgeOverTimeAllowed == true && context.isAny(of: .pledge, .editPledgeOverTime)
      }

    let planRequests: Signal<(Project, String), Never> = Signal.combineLatest(
      project,
      // just re-evaluate if the total is changed
      pledgeTotal.skipRepeats()
    )
    .map {
      (project: Project, pledgeTotal: Double) -> (
        Project,
        String
      ) in
      let amountFormatter = NumberFormatter()
      amountFormatter.minimumFractionDigits = 2
      amountFormatter.maximumFractionDigits = 2
      let amount = amountFormatter.string(from: NSNumber(value: pledgeTotal)) ?? ""

      return (project, amount)
    }

    self.buildPaymentPlanInputs = planRequests.map { ($0.0.slug, $0.1) }

    let pledgeOverTimeQuery =
      planRequests
      .switchMap {
        (
          paymentPlanInputs: (project: Project, amount: String)
        ) -> SignalProducer<
          Signal<(Project, PledgePaymentPlan?), ErrorEnvelope>.Event,
          Never
        > in
        feature.paymentPlanResult(
          route: route, slug: paymentPlanInputs.project.slug,
          amount: paymentPlanInputs.amount
        )
        // Keep each result paired with its request's project. A new project must
        // never receive eligibility or installments retained from the previous one.
        .map { (paymentPlanInputs.project, $0) }
        .materialize()
      }

    self.showPledgeOverTimeUI = Signal.merge(
      // Hide PLOT if the feature flag is off on either client or server
      pledgeOverTimeUIEnabled,
      // Hide PLOT if an error occurs
      pledgeOverTimeQuery.errors().map(value: false)
    )

    self.pledgeOverTimeIsLoading = Signal.merge(
      pledgeOverTimeUIEnabled,
      pledgeOverTimeQuery.values().map(value: false),
      pledgeOverTimeQuery.errors().map(value: false)
    )
    .skipRepeats()

    // Send an empty config when the view model is initialized
    let emptyConfigData: Signal<PledgePaymentPlansAndSelectionData?, Never> = self
      .showPledgeOverTimeUI
      .filter { $0 == false }
      .mapConst(nil)

    // Send a config once the query loads, defaulting to .pledgeInFull
    let configDataAfterQueryLoads: Signal<PledgePaymentPlansAndSelectionData?, Never> =
      pledgeOverTimeQuery
      .values()
      .map {
        (
          project: Project,
          pledgeOverTimeApiValues: PledgePaymentPlan?
        ) -> PledgePaymentPlansAndSelectionData? in

        // Wrap the value in `nil` to ensure the Signal emits consistently,
        // even when the API request fails or Pledge Over Time is disabled.
        guard let paymentPlan = pledgeOverTimeApiValues else { return nil }

        let isPledgeOverTimePreSelected =
          project.personalization.backing?.paymentIncrements.isEmpty == false
        let isPledgeOverTimeEligible = paymentPlan.amountIsPledgeOverTimeEligible

        // Retain PLOT pre-selection only if the new pledge amount meets the eligibility threshold (amountIsPledgeOverTimeEligible)
        let defaultPlan =
          isPledgeOverTimePreSelected && isPledgeOverTimeEligible
          ? PledgePaymentPlansType.pledgeOverTime : PledgePaymentPlansType.pledgeInFull

        return PledgePaymentPlansAndSelectionData(
          selectedPlan: defaultPlan,
          increments: paymentPlan.paymentIncrements,
          ineligible: !paymentPlan.amountIsPledgeOverTimeEligible,
          project: project
        )
      }

    // Send an updated config after changing the plan
    let configDataAfterChangingPlan: Signal<PledgePaymentPlansAndSelectionData?, Never> =
      Signal
      .combineLatest(configDataAfterQueryLoads.skipNil(), self.paymentPlanSelectedProperty.signal)
      .map { data, selectedPlan in
        PledgePaymentPlansAndSelectionData(
          selectedPlan: selectedPlan,
          increments: data.paymentIncrements,
          ineligible: data.ineligible,
          project: data.project
        )
      }

    self.pledgeOverTimeConfigData = Signal.merge(
      emptyConfigData,
      configDataAfterQueryLoads,
      configDataAfterChangingPlan
    )
    .skipRepeats { a, b in
      if a.isNil && b.isNil {
        return true
      }

      return false
    }
  }

  private let feature: PledgeFeature
  private let route = UUID()
  deinit {
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.releaseRead(route: route) }
  }

  public let showPledgeOverTimeUI: Signal<Bool, Never>
  public let pledgeOverTimeConfigData: Signal<PledgePaymentPlansAndSelectionData?, Never>
  public let pledgeOverTimeIsLoading: Signal<Bool, Never>
  public let buildPaymentPlanInputs: Signal<(String, String), Never>

  public var outputs: PledgeOverTimeUseCaseOutputs { return self }
  public var inputs: PledgeOverTimeUseCaseInputs { return self }

  // MARK: - Inputs

  private let paymentPlanSelectedProperty = MutableProperty<PledgePaymentPlansType>(.pledgeInFull)
  public func paymentPlanSelected(_ paymentPlan: PledgePaymentPlansType) {
    self.paymentPlanSelectedProperty.value = paymentPlan
  }

  // MARK: - Outputs
}
