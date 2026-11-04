import KDS

import Prelude
import UIKit

final class EmptyStateCell: UITableViewCell, ValueCell {
  private let emptyStateView = EmptyStateView(frame: .zero)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    _ = (self.emptyStateView, self.contentView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    self.separatorInset = .init(leftRight: self.frame.width / 2)
  }

  func configureWith(value: EmptyStateViewType) {
    self.emptyStateView.configure(with: value)
    self.contentView.backgroundColor = self.emptyStateView.backgroundColor
  }
}

final class EmptyStateView: UIView {
  // MARK: - Properties

  private let bodyLabel = UILabel(frame: .zero)
  private let imageView = UIImageView(frame: .zero)
  private let rootStackView = UIStackView(frame: .zero)
  private let rootVerticalStackView = UIStackView(frame: .zero)
  private let titleLabel = UILabel(frame: .zero)

  override init(frame _: CGRect) {
    super.init(frame: .zero)

    self.configureSubviews()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> checkoutBackgroundStyle

    _ = self.rootStackView
      |> \.alignment .~ .center

    _ = self.rootVerticalStackView
      |> \.alignment .~ .center
      |> \.spacing .~ Styles.grid(2)
      |> \.axis .~ .vertical
      |> \.isLayoutMarginsRelativeArrangement .~ true

    _ = self.titleLabel
      |> \.textAlignment .~ .center
      |> \.numberOfLines .~ 0
      |> \.font .~ UIFont.ksr_title3().bolded

    _ = self.bodyLabel
      |> \.textAlignment .~ .center
      |> \.numberOfLines .~ 0
      |> \.font .~ UIFont.ksr_subhead()
  }

  // MARK: - Configuration

  func configure(with type: EmptyStateViewType) {
    self.bodyLabel.text = type.bodyLabelText
    self.bodyLabel.isHidden = type.bodyLabelHidden
    self.bodyLabel.textColor = type.bodyLabelTextColor
    self.titleLabel.text = type.titleLabelText
    self.titleLabel.isHidden = type.titleLabelHidden
    self.rootVerticalStackView.layoutMargins = .init(leftRight: type.leftRightMargins)
    self.imageView.image = type.imageName.flatMap { Kickstarter_iOS.image(named: $0) }
  }

  // MARK: - Views

  func configureSubviews() {
    _ = (self.rootStackView, self)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.rootVerticalStackView], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.imageView, self.titleLabel, self.bodyLabel], self.rootVerticalStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.rootVerticalStackView.setCustomSpacing(Styles.grid(3), after: self.titleLabel)
  }

}
