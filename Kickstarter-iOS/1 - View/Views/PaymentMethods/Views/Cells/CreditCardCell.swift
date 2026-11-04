import KsApi

import Prelude
import UIKit

internal final class CreditCardCell: UITableViewCell, ValueCell {
  private let viewModel = CreditCardCellViewModel()

  @IBOutlet fileprivate var stackView: UIStackView!
  @IBOutlet fileprivate var cardImageView: UIImageView!
  @IBOutlet fileprivate var cardNumberLabel: UILabel!
  @IBOutlet fileprivate var expirationDateLabel: UILabel!

  public func configureWith(value card: UserCreditCards.CreditCard) {
    let display = self.viewModel.configureWith(creditCard: card)
    self.cardNumberLabel.accessibilityLabel = display.accessibilityLabel
    self.cardNumberLabel.text = display.number
    self.expirationDateLabel.text = display.expiration
    self.cardImageView.image = display.image
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.stackView
      |> \.isLayoutMarginsRelativeArrangement .~ true
      |> \.layoutMargins .~ .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))

    _ = self.cardImageView
      |> \.contentMode .~ .scaleAspectFit

    _ = self.cardNumberLabel
      |> settingsTitleLabelStyle
      |> \.lineBreakMode .~ .byTruncatingMiddle

    _ = self.expirationDateLabel
      |> settingsDescriptionLabelStyle
  }

}
