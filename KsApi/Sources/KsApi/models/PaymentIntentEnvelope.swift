import Foundation
import GraphAPI

public struct PaymentIntentEnvelope: Decodable, Sendable {
  public let clientSecret: String
}

// MARK: - GraphQL Adapters

extension PaymentIntentEnvelope {
  /**
   Returns a minimal `PaymentIntentEnvelope` from a `CreatePaymentIntentMutation.Data`
   */
  static func clientSecretEnvelope(
    from data: GraphAPI.CreatePaymentIntentMutation
      .Data
  ) -> PaymentIntentEnvelope? {
    guard let clientSecret = data.createPaymentIntent?.clientSecret
    else { return nil }

    return PaymentIntentEnvelope(clientSecret: clientSecret)
  }
}
