import KDS
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

final class PledgeStatusLabelView: UIView {
  // MARK: - Properties

  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var textView = { UITextView(frame: .zero) }()
  private lazy var badgeView = { BadgeView(frame: .zero) }()

  private let viewModel = PledgeStatusLabelViewModel()

  // MARK: - Lifecycle

  override init(frame: CGRect) {
    super.init(frame: frame)

    self.configureSubviews()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.rootStackView
      |> containerViewStyle

    applyTextViewStyle(self.textView)
  }

  private func configureSubviews() {
    _ = (self.rootStackView, self)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    self.badgeView.configure(with: Strings.Beta())
    self.badgeView.isHidden = true

    applyRootStackViewStyle(self.rootStackView)

    self.rootStackView.addArrangedSubviews(self.badgeView, self.textView)
  }

  // MARK: - Configuration

  internal func configure(with data: PledgeStatusLabelViewData) {
    self.viewModel.configure(with: data)
    if let text = self.viewModel.labelText {
      self.textView.attributedText = text
    }
    self.badgeView.isHidden = self.viewModel.badgeHidden
  }
}

// MARK: - Styles

private let containerViewStyle: ViewStyle = { (view: UIView) in
  view
    |> \.backgroundColor .~ LegacyColors.ksr_support_200.uiColor()
    |> \.layoutMargins .~ .init(all: Styles.grid(2))
    |> roundedStyle()
}

@MainActor
private func applyRootStackViewStyle(_ stackView: UIStackView) {
  stackView.backgroundColor = LegacyColors.ksr_support_200.uiColor()
  stackView.isLayoutMarginsRelativeArrangement = true
  stackView.layoutMargins = .init(all: Styles.grid(2))
  stackView.rounded()
  stackView.axis = .vertical
  stackView.alignment = .center
  stackView.spacing = Styles.grid(2)
}

@MainActor
private func applyTextViewStyle(_ textView: UITextView) {
  textView.accessibilityTraits = [.staticText]
  textView.backgroundColor = LegacyColors.ksr_support_200.uiColor()
  textView.isScrollEnabled = false
  textView.isEditable = false
  textView.isUserInteractionEnabled = true
  textView.adjustsFontForContentSizeCategory = true
  textView.textContainerInset = .zero
  textView.textContainer.lineFragmentPadding = 0
  textView.linkTextAttributes = [
    .foregroundColor: LegacyColors.ksr_create_700.uiColor()
  ]
}
