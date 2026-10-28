import GraphAPI
@testable import KsApi
@testable import Library
import ReactiveSwift

@MainActor
public class MockStripeIntentService: StripeIntentServiceType {
  public private(set) var setupIntentRequests: Int = 0
  public private(set) var paymentIntentRequests: Int = 0

  public let paymentsFeature: PaymentsFeature
  public init() {
    let session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    self.paymentsFeature = PaymentsFeature(sessionFeature: session, makeProvider: {
      precondition(AppEnvironment.current.apiService is MockService)
      return AsyncPaymentsProvider(service: AppEnvironment.current.apiService)
    })
  }

  public func createPaymentIntent(
    for projectId: String,
    backingId: String,
    checkoutId: String,
    pledgeTotal: Double
  ) -> SignalProducer<PaymentIntentEnvelope, ErrorEnvelope> {
    assert(
      AppEnvironment.current.apiService is MockService,
      "AppEnvironment.current.apiService should be a MockService when used in test."
    )

    self.paymentIntentRequests += 1

    return self.paymentsFeature.intentResult(projectID: projectId, backingID: backingId, checkoutID: checkoutId, total: pledgeTotal)
  }

  public func createSetupIntent(
    for projectId: String?,
    context: GraphAPI.StripeIntentContextTypes
  ) -> SignalProducer<ClientSecretEnvelope, ErrorEnvelope> {
    assert(
      AppEnvironment.current.apiService is MockService,
      "AppEnvironment.current.apiService should be a MockService when used in test."
    )

    self.setupIntentRequests += 1

    return self.paymentsFeature.setupResult(projectID: projectId, context: context)
  }
}
