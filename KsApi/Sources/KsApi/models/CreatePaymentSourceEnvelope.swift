import Foundation

public struct CreatePaymentSourceEnvelope: Decodable, Sendable {
  public var createPaymentSource: CreatePaymentSource

  public struct CreatePaymentSource: Decodable, Sendable {
    public var isSuccessful: Bool
    public var paymentSource: UserCreditCards.CreditCard
  }
}
