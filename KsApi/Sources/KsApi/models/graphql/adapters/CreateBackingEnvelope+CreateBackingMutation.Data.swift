import Foundation
import GraphAPI

extension CreateBackingEnvelope {
  static func from(_ data: GraphAPI.CreateBackingMutation.Data) -> CreateBackingEnvelope? {
    guard let checkout = Checkout.from(data.createBacking?.checkout?.fragments.checkoutFragment) else {
      return nil
    }

    return CreateBackingEnvelope(createBacking: CreateBacking(checkout: checkout))
  }

}
