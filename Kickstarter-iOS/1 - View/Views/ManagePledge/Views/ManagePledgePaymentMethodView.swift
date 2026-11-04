import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol ManagePledgePaymentMethodViewDelegate: AnyObject {
  func managePledgePaymentMethodViewDidTapFixButton(_ view: ManagePledgePaymentMethodView)
}

final class ManagePledgePaymentMethodView: UIView {
  weak var delegate: ManagePledgePaymentMethodViewDelegate?

  // MARK: - Properties

  private lazy var cardLabelsStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var cardNumberLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var expirationDateLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var fixButton: KSRButton = {
    let button = KSRButton(style: .filledDestructive)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(Strings.Fix_payment_method(), for: .normal)
    return button
  }()

  private lazy var paymentMethodAdaptableStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var paymentMethodImageView: UIImageView = { UIImageView(frame: .zero) }()
  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var titleLabel: UILabel = { UILabel(frame: .zero) }()

  private let viewModel = ManagePledgePaymentMethodViewModel()

  // MARK: - Lifecycle

  override init(frame: CGRect) {
    super.init(frame: frame)

    self.configureViews()
    self.setupConstraints()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Configuration

  public func configure(with data: ManagePledgePaymentMethodViewData) {
    self.viewModel.configureWith(data: data)
    if let text = self.viewModel.expirationDateText { self.expirationDateLabel.text = text }
    if let text = self.viewModel.cardNumberTextShortStyle { self.cardNumberLabel.text = text }
    self.cardNumberLabel.accessibilityLabel = self.viewModel.cardNumberAccessibilityLabel
    if let hidden = self.viewModel.fixButtonHidden { self.fixButton.isHidden = hidden }
    if let name = self.viewModel.cardImageName { self.paymentMethodImageView.image = image(named: name) }
  }

  private func configureViews() {
    _ = ([self.cardNumberLabel, self.expirationDateLabel], self.cardLabelsStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([
      self.paymentMethodImageView,
      self.cardLabelsStackView
    ], self.paymentMethodAdaptableStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.titleLabel, self.paymentMethodAdaptableStackView, self.fixButton], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = (self.rootStackView, self)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = (self.cardLabelsStackView, self.paymentMethodAdaptableStackView)
      |> ksr_setCustomSpacing(Styles.grid(6))

    self.fixButton.addTarget(
      self,
      action: #selector(ManagePledgePaymentMethodView.fixButtonTapped),
      for: .touchUpInside
    )
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()
    _ = self.cardLabelsStackView
      |> cardLabelsStackViewStyle

    _ = self.expirationDateLabel
      |> expirationDateLabelStyle

    _ = self.cardNumberLabel
      |> lastFourDigitsLabelStyle

    _ = self.paymentMethodAdaptableStackView
      |> adaptableStackViewStyle(
        self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      )
      |> paymentMethodAdaptableStackViewStyle

    _ = self.paymentMethodImageView
      |> cardImageViewStyle

    _ = self.rootStackView
      |> checkoutCardStackViewStyle

    _ = self.titleLabel
      |> checkoutTitleLabelStyle
      |> \.text %~ { _ in Strings.Payment_method() }
  }

  // MARK: - Functions

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      self.paymentMethodImageView.widthAnchor.constraint(
        equalToConstant: CheckoutConstants.PaymentSource.ImageView.width
      ),
      self.fixButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Styles.grid(10)),
      self.fixButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Styles.minTouchSize.height)
    ])
  }

  @objc private func fixButtonTapped() {
    self.delegate?.managePledgePaymentMethodViewDidTapFixButton(self)
  }
}

// MARK: - Styles

private let cardLabelsStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> verticalStackViewStyle
    |> \.spacing .~ Styles.grid(1)
}

private let expirationDateLabelStyle: LabelStyle = { label in
  label
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.font .~ UIFont.ksr_caption1().bolded
    |> \.numberOfLines .~ 0
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
}

private let lastFourDigitsLabelStyle: LabelStyle = { label in
  label
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.font .~ UIFont.ksr_subhead().bolded
    |> \.numberOfLines .~ 0
    |> \.textColor .~ LegacyColors.ksr_support_700.uiColor()
}

private let paymentMethodAdaptableStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> \.spacing .~ Styles.grid(2)
}
