import GraphAPI

/// Payment-plan values detached from Apollo's generated response graph.
public struct PledgePaymentPlan: Equatable, Sendable {
  public let amountIsPledgeOverTimeEligible: Bool
  public let paymentIncrements: [PledgePaymentIncrement]

  public init(amountIsPledgeOverTimeEligible: Bool, paymentIncrements: [PledgePaymentIncrement]) {
    self.amountIsPledgeOverTimeEligible = amountIsPledgeOverTimeEligible
    self.paymentIncrements = paymentIncrements
  }

  public static func from(_ data: GraphAPI.BuildPaymentPlanQuery.Data) -> PledgePaymentPlan? {
    guard let plan = data.project?.paymentPlan else { return nil }
    return PledgePaymentPlan(
      amountIsPledgeOverTimeEligible: plan.amountIsPledgeOverTimeEligible,
      paymentIncrements: (plan.paymentIncrements ?? []).compactMap {
        PledgePaymentIncrement(withGraphQLFragment: $0.fragments.paymentIncrementFragment)
      }
    )
  }
}
