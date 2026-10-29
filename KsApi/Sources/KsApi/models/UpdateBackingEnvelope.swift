import Foundation

public struct UpdateBackingEnvelope: Decodable, Sendable {
  public var updateBacking: UpdateBacking

  public struct UpdateBacking: Decodable, Sendable {
    public var checkout: Checkout
  }
}
