import Foundation
import GraphAPI
import ReactiveSwift

public struct ValidateCheckoutEnvelope: Decodable, Sendable {
  public let messages: [String]
}

// MARK: - GraphQL Adapters

extension ValidateCheckoutEnvelope {
  static func validated(from data: GraphAPI.ValidateCheckoutQuery.Data) throws -> ValidateCheckoutEnvelope {
    guard let envelope = self.validateCheckoutEnvelope(from: data) else {
      throw ErrorEnvelope.couldNotParseJSON
    }
    guard data.checkout?.isValidForOnSessionCheckout.valid == true else {
      throw ErrorEnvelope.validateCheckoutError(envelope.messages)
    }
    return envelope
  }

  static func envelopeProducer(from data: GraphAPI.ValidateCheckoutQuery.Data)
    -> SignalProducer<ValidateCheckoutEnvelope, ErrorEnvelope> {
    guard let envelope = ValidateCheckoutEnvelope.validateCheckoutEnvelope(from: data) else {
      return SignalProducer(error: .couldNotParseJSON)
    }

    guard data.checkout?.isValidForOnSessionCheckout.valid == true else {
      return SignalProducer(error: .validateCheckoutError(envelope.messages))
    }

    return SignalProducer(value: envelope)
  }

  /**
   Returns a minimal `ValidateCheckoutEnvelope` from a `GraphAPI.ValidateCheckoutQuery.Data`
   */
  static func validateCheckoutEnvelope(
    from data: GraphAPI.ValidateCheckoutQuery
      .Data
  ) -> ValidateCheckoutEnvelope? {
    guard let messages = data.checkout?.isValidForOnSessionCheckout.messages
    else { return nil }

    return ValidateCheckoutEnvelope(messages: messages)
  }
}
