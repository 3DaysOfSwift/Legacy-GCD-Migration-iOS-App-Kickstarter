import KDS

import Prelude
import UIKit

final class PledgeExpandableHeaderRewardCell: UITableViewCell, ValueCell {
  // MARK: - Properties

  private lazy var amountLabel: UILabel = UILabel(frame: .zero)
  private lazy var rootStackView: UIStackView = UIStackView(frame: .zero)
  private lazy var titleLabel: UILabel = UILabel(frame: .zero)

  // MARK: - Lifecycle

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.configureViews()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> \.selectionStyle .~ .none
      |> \.separatorInset .~ .init(leftRight: CheckoutConstants.PledgeView.Inset.leftRight)

    _ = self.amountLabel
      |> UILabel.lens.contentHuggingPriority(for: .horizontal) .~ .required
      |> \.adjustsFontForContentSizeCategory .~ true

    _ = self.rootStackView
      |> rootStackViewStyle(self.traitCollection.preferredContentSizeCategory > .accessibilityLarge)

    _ = self.titleLabel
      |> titleLabelStyle
  }

  // MARK: - Configuration

  func configureWith(value: PledgeSummaryRewardCellData) {
    self.amountLabel.attributedText = value.amount
    self.titleLabel.text = value.text
    self.titleLabel.setNeedsLayout()

    self.contentView.layoutIfNeeded()
  }

  private func configureViews() {
    _ = (self.rootStackView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.titleLabel, self.amountLabel], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()
  }
}

// MARK: - Styles

private let titleLabelStyle: LabelStyle = { label in
  label
    |> \.font .~ UIFont.ksr_subhead().bolded
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.numberOfLines .~ 0
}

private func rootStackViewStyle(_ isAccessibilityCategory: Bool) -> (StackViewStyle) {
  let alignment: UIStackView.Alignment = (isAccessibilityCategory ? .leading : .top)
  let axis: NSLayoutConstraint.Axis = (isAccessibilityCategory ? .vertical : .horizontal)
  let distribution: UIStackView.Distribution = (isAccessibilityCategory ? .equalSpacing : .fill)
  let spacing: CGFloat = (isAccessibilityCategory ? Styles.grid(1) : 0)

  return { (stackView: UIStackView) in
    stackView
      |> \.insetsLayoutMarginsFromSafeArea .~ false
      |> \.alignment .~ alignment
      |> \.axis .~ axis
      |> \.distribution .~ distribution
      |> \.spacing .~ spacing
      |> \.isLayoutMarginsRelativeArrangement .~ true
      |> \.layoutMargins .~ .init(
        topBottom: Styles.grid(3),
        leftRight: CheckoutConstants.PledgeView.Inset.leftRight
      )
  }
}
