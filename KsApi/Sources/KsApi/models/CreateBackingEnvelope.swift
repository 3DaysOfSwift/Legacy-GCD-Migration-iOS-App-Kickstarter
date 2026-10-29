import Foundation

public struct CreateBackingEnvelope: Decodable, Sendable {
  public var createBacking: CreateBacking

  public struct CreateBacking: Decodable, Sendable {
    public var checkout: Checkout
  }
}
