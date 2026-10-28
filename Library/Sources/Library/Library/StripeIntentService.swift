import Foundation
import GraphAPI
import KsApi
import ReactiveSwift

@MainActor
public protocol StripeIntentServiceType {
  var paymentsFeature: PaymentsFeature { get }
  func createPaymentIntent(
    for projectId: String,
    backingId: String,
    checkoutId: String,
    pledgeTotal: Double
  ) -> SignalProducer<PaymentIntentEnvelope, ErrorEnvelope>
  func createSetupIntent(
    for projectId: String?,
    context: GraphAPI.StripeIntentContextTypes
  ) -> SignalProducer<ClientSecretEnvelope, ErrorEnvelope>
}

/// This is the module that creates either a Stripe payment intent or a setup intent.
@MainActor
public class StripeIntentService: StripeIntentServiceType {
  public let paymentsFeature: PaymentsFeature
  public init(paymentsFeature: PaymentsFeature = AppModel.shared.paymentsFeature) {
    self.paymentsFeature = paymentsFeature
  }

  /**
   Returns a signal producer that emits a `PaymentIntentEnvelope` or `ErrorEnvelope` value representing whether or not a payment intent was created and returned successfully.
   The returned producer emits once and completes.

   - parameter for: The types to register that we will request permissions for.
   - parameters:
     - projectId: The GraphID of a project
     - checkoutId: The GraphID returned from our CreateCheckout mutation.
     - backingId: The current Backing ID used by the backend to reverse payments and rescue checkouts.
     - pledgeTotal: The final pledge total of the current pledge
   */

  public func createPaymentIntent(
    for projectId: String,
    backingId: String,
    checkoutId: String,
    pledgeTotal: Double
  ) -> SignalProducer<PaymentIntentEnvelope, ErrorEnvelope> {
    self.paymentsFeature.intentResult(projectID: projectId, backingID: backingId, checkoutID: checkoutId, total: pledgeTotal)
  }

  /**
   Returns a signal producer that contains a `ClientSecretEnvelope` or `ErrorEnvelope`  representing whether or not a setup intent was created and returned successfully.
   The returned producer emits once and completes.

   - parameter for: The types to register that we will request permissions for.
   - parameters:
     - projectId: The optional GraphID of a project
     - context: The context for which this intent is being created
   */

  public func createSetupIntent(
    for projectId: String?,
    context: GraphAPI.StripeIntentContextTypes
  ) -> SignalProducer<ClientSecretEnvelope, ErrorEnvelope> {
    self.paymentsFeature.setupResult(projectID: projectId, context: context)
  }
}
