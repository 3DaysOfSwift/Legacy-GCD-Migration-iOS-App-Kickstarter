import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import Observation

public struct ManagePledgePaymentMethodViewData: Equatable {
  public let showFixPaymentButton: Bool
  public let expirationDate: String?
  public let lastFour: String?
  public let creditCardType: CreditCardType?
  public let paymentType: PaymentType?
}

@MainActor @Observable
public final class ManagePledgePaymentMethodViewModel {
  public init() {}

  public private(set) var cardImageName: String?
  public private(set) var cardNumberAccessibilityLabel: String?
  public private(set) var cardNumberTextShortStyle: String?
  public private(set) var expirationDateText: String?
  public private(set) var fixButtonHidden: Bool?

  public func configureWith(data: ManagePledgePaymentMethodViewData) {
    if let name = imageName(for: data.paymentType, creditCardType: data.creditCardType) {
      self.cardImageName = name
    }
    self.cardNumberAccessibilityLabel = paymentMethodAccessibilityLabel(
      for: data.paymentType, cardType: data.creditCardType, lastFour: data.lastFour
    )
    if let lastFour = data.lastFour {
      self.cardNumberTextShortStyle = Strings.Ending_in_last_four(last_four: lastFour)
    }
    if let expirationDate = data.expirationDate {
      self.expirationDateText = Strings.Credit_card_expiration(
        expiration_date: formatted(dateString: String(expirationDate.dropLast(3)))
      )
    }
    self.fixButtonHidden = !data.showFixPaymentButton
  }
}

private func imageName(for paymentType: PaymentType?, creditCardType: CreditCardType?) -> String? {
  switch paymentType {
  case .creditCard:
    return creditCardType?.imageName
  case .applePay:
    return "icon--apple-pay"
  case .googlePay:
    return "icon--google-pay"
  case .bankAccount:
    return "icon--credit-card"
  case nil:
    return nil
  }
}

private func paymentMethodAccessibilityLabel(
  for paymentType: PaymentType?,
  cardType: CreditCardType?,
  lastFour: String?
) -> String {
  let paymentTypeDescription = paymentType.flatMap { paymentType in
    switch paymentType {
    case .applePay:
      return Strings.accessibility_payment_types_apple_pay()
    case .googlePay:
      return Strings.accessibility_payment_types_google_pay()
    case .bankAccount:
      return Strings.accessibility_payment_types_bank_account()
    case .creditCard:
      return nil
    }
  }

  let lastFourDescription = lastFour.map(Strings.Card_ending_in_last_four)

  return [paymentTypeDescription, cardType?.description, lastFourDescription]
    .compact()
    .joined(separator: ", ")
}

@MainActor
private func formatted(dateString: String) -> String {
  let date = toDate(dateString: dateString)
  return Format.date(
    secondsInUTC: date.timeIntervalSince1970,
    template: "MM-yyyy",
    timeZone: UTCTimeZone
  )
}

@MainActor
private func toDate(dateString: String) -> Date {
  // Always use UTC timezone here this date should be timezone agnostic
  guard let date = Format.date(
    from: dateString,
    dateFormat: "yyyy-MM",
    timeZone: UTCTimeZone
  ) else {
    fatalError("Unable to parse date format")
  }

  return date
}
