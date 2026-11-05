import Foundation
import GraphAPI

public struct CreateCheckoutEnvelope: Decodable, Sendable {
  public var checkout: Checkout

  public struct Checkout: Decodable, Sendable {
    public var id: String
    public var paymentUrl: String
    public var backingId: String
  }
}

// MARK: - GraphQL Adapters

extension CreateCheckoutEnvelope {
  static func from(_ data: GraphAPI.CreateCheckoutMutation.Data) -> CreateCheckoutEnvelope? {
    guard let id = data.createCheckout?.checkout?.id,
          let paymentUrl = data.createCheckout?.checkout?.paymentUrl,
          let backingId = data.createCheckout?.checkout?.backing.id else {
      return nil
    }

    return CreateCheckoutEnvelope(checkout: Checkout(id: id, paymentUrl: paymentUrl, backingId: backingId))
  }

}
