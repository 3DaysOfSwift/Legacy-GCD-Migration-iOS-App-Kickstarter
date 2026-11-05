import Foundation
import GraphAPI

extension UpdateBackingEnvelope {
  /**
   Map `GraphAPI.UpdateBackingMutation.Data` to a `UpdateBackingEnvelope`, otherwise return `nil`
   */
  static func from(_ data: GraphAPI.UpdateBackingMutation.Data) -> UpdateBackingEnvelope? {
    guard let checkout = Checkout.from(data.updateBacking?.checkout?.fragments.checkoutFragment) else {
      return nil
    }

    return UpdateBackingEnvelope(updateBacking: UpdateBacking(checkout: checkout))
  }

}
