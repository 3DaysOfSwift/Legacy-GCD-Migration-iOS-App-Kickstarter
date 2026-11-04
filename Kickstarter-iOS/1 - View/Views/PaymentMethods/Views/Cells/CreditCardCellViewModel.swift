import KsApi
import UIKit

@MainActor
public final class CreditCardCellViewModel {
  struct Display {
    let image: UIImage?
    let accessibilityLabel: String
    let number: String
    let expiration: String
  }
  public init() {}

  func configureWith(creditCard card: UserCreditCards.CreditCard) -> Display {
    let number = Strings.Card_ending_in_last_four(last_four: card.lastFour)
    return Display(
      image: image(named: card.imageName),
      accessibilityLabel: [card.type?.description, number].compactMap { $0 }.joined(separator: ", "),
      number: number,
      expiration: Strings.Credit_card_expiration(expiration_date: card.expirationDate())
    )
  }
}
