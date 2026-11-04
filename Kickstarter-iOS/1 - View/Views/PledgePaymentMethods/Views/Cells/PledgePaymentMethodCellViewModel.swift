import KDS
import KsApi
import UIKit

public typealias PledgePaymentMethodCellData = (
  card: UserCreditCards.CreditCard,
  isEnabled: Bool,
  isSelected: Bool,
  projectCountry: String,
  isErroredPaymentMethod: Bool
)

@MainActor
public final class PledgePaymentMethodCellViewModel {
  struct Display {
    let cardImageAlpha: CGFloat
    let cardImageName: String
    let cardNumberAccessibilityLabel: String
    let cardNumberTextShortStyle: String
    let checkmarkImageHidden: Bool
    let checkmarkImageName: String
    let expirationDateText: String
    let lastFourLabelTextColor: UIColor
    let selectionStyle: UITableViewCell.SelectionStyle
    let unavailableCardLabelHidden: Bool
    let unavailableCardText: String?
  }
  private var cardID: String?
  private var selectedID: String?
  public init() {}

  func configureWith(value: PledgePaymentMethodCellData) -> Display {
    let card = value.card
    self.cardID = card.id
    let number = Strings.Card_ending_in_last_four(last_four: card.lastFour)
    let unavailable = !value.isEnabled || value.isErroredPaymentMethod
    let explanation: String?
    if !value.isEnabled {
      explanation = Strings.You_cant_use_this_credit_card_to_back_a_project_from_project_country(
        project_country: value.projectCountry
      )
    } else if value.isErroredPaymentMethod { explanation = Strings.Retry_or_select_another_method() }
    else { explanation = nil }
    return Display(
      cardImageAlpha: value.isEnabled ? 1 : 0.5,
      cardImageName: card.imageName,
      cardNumberAccessibilityLabel: [card.type?.description, number].compactMap { $0 }.joined(separator: ", "),
      cardNumberTextShortStyle: "•••• \(card.lastFour)",
      checkmarkImageHidden: !value.isEnabled,
      checkmarkImageName: Self.checkmark(self.selectedID.map { $0 == card.id } ?? value.isSelected),
      expirationDateText: Strings.Credit_card_expiration(expiration_date: card.expirationDate()),
      lastFourLabelTextColor: value.isEnabled ? LegacyColors.ksr_support_700.uiColor() : LegacyColors.ksr_support_400.uiColor(),
      selectionStyle: value.isEnabled ? .default : .none,
      unavailableCardLabelHidden: !unavailable,
      unavailableCardText: explanation
    )
  }

  func setSelectedCardId(_ id: String) -> String? {
    self.selectedID = id
    guard let cardID = self.cardID else { return nil }
    return Self.checkmark(cardID == id)
  }

  private static func checkmark(_ selected: Bool) -> String {
    selected ? "icon-payment-method-selected" : "icon-payment-method-unselected"
  }
}
