import KDS
import KsApi

import ReactiveSwift
import UIKit

@MainActor
protocol RewardAddOnCardViewDelegate: AnyObject {
  func rewardAddOnCardView(
    _ cardView: RewardAddOnCardView,
    didSelectQuantity quantity: Int,
    rewardId: Int
  )
}

public final class RewardAddOnCardView: UIView {
  // MARK: - Properties

  weak var delegate: RewardAddOnCardViewDelegate?
  private let viewModel = RewardAddOnCardViewModel()

  private let rootStackView = UIStackView(frame: .zero)
  private let detailsStackView = UIStackView(frame: .zero)

  private let rewardImageView = UIImageView(frame: .zero)
  private let addButton = UIButton(type: .custom)
  private let amountConversionLabel = UILabel(frame: .zero)
  private let amountLabel = UILabel(frame: .zero)
  private let descriptionLabel = UILabel(frame: .zero)
  private let includedItemsSeparator: UIView = UIView(frame: .zero)
  private let includedItemsStackView = UIStackView(frame: .zero)
  private let includedItemsTitleLabel = UILabel(frame: .zero)
  private let includedItemsLabel = UILabel(frame: .zero)
  private let estimatedShippingSeparator: UIView = UIView(frame: .zero)
  private let estimatedShippingStackView = UIStackView(frame: .zero)
  private let estimatedShippingTitleLabel = UILabel(frame: .zero)
  private let estimatedShippingLabel = UILabel(frame: .zero)
  private let quantityLabel = UILabel(frame: .zero)
  private let quantityLabelContainer = UIView(frame: .zero)
  private let pillsView: PillsView = PillsView(frame: .zero)
  private var pillsViewHeightConstraint: NSLayoutConstraint?
  private let stepper: UIStepper = UIStepper(frame: .zero)
  private let stepperStackView = UIStackView(frame: .zero)
  private let rewardLocationStackView = UIStackView(frame: .zero)
  private let rewardLocationTitleLabel = UILabel(frame: .zero)
  private let rewardLocationPickupLabel = UILabel(frame: .zero)
  private let rewardTitleLabel = UILabel(frame: .zero)
  private let titleAmountStackView = UIStackView(frame: .zero)

  override init(frame: CGRect) {
    super.init(frame: frame)

    self.addButton.addTarget(
      self,
      action: #selector(RewardAddOnCardView.addButtonTapped),
      for: .touchUpInside
    )

    self.stepper.addTarget(
      self,
      action: #selector(RewardAddOnCardView.stepperValueChanged(_:)),
      for: .valueChanged
    )

    self.configureViews()
    self.setupConstraints()
    self.bindViewModel()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func layoutSubviews() {
    super.layoutSubviews()

    self.pillsViewHeightConstraint?.constant = self.pillsView.intrinsicContentSize.height
  }

  public override func bindStyles() {
    super.bindStyles()

    _ = checkoutWhiteBackgroundStyle(self)

    applyAddButtonStyle(self.addButton)

    var stackViews = [
      self.detailsStackView,
      self.titleAmountStackView,
      self.includedItemsStackView,
      self.rewardLocationStackView
    ]

    stackViews.insert(self.estimatedShippingStackView, at: 3)
    stackViews.forEach(applySectionStackViewStyle)

    applyRootStackViewStyle(self.rootStackView)
    applyDetailsStackViewStyle(self.detailsStackView)
    applyTitleAmountStackViewStyle(self.titleAmountStackView)
    _ = separatorStyle(self.includedItemsSeparator)
    applyIncludedItemsStackViewStyle(self.includedItemsStackView)
    applyIncludedItemsTitleLabel(self.includedItemsTitleLabel)
    applyIncludedItemsLabel(self.includedItemsLabel)
    _ = separatorStyle(self.estimatedShippingSeparator)
    applyIncludedItemsStackViewStyle(self.estimatedShippingStackView)
    applyEstimatedShippingTitleLabel(self.estimatedShippingTitleLabel)
    applyEstimatedShippingLabel(self.estimatedShippingLabel)
    applyDescriptionLabelStyle(self.descriptionLabel)
    applyRewardTitleLabelStyle(self.rewardTitleLabel)
    applyAmountLabelStyle(self.amountLabel)
    applyAmountConvertedLabelStyle(self.amountConversionLabel)
    applyQuantityLabelContainerStyle(self.quantityLabelContainer)
    applyQuantityLabelStyle(self.quantityLabel)
    applyStepperStyle(self.stepper)
    applyStepperStackViewStyle(self.stepperStackView)

    self.rewardLocationStackView
      .addArrangedSubviews(
        self.rewardLocationTitleLabel,
        self.rewardLocationPickupLabel
      )

    applyIncludedItemsStackViewStyle(self.rewardLocationStackView)
    applyRewardLocationTitleLabelStyle(self.rewardLocationTitleLabel)
    applySectionBodyLabelStyle(self.rewardLocationPickupLabel)
    applyRewardImageViewStyle(self.rewardImageView)
  }

  public override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onDisplay = { [weak self] display in
      guard let self else { return }
      self.amountConversionLabel.isHidden = display.conversionHidden
      self.amountConversionLabel.text = display.conversion
      self.descriptionLabel.text = display.description
      self.includedItemsStackView.isHidden = display.includedItemsHidden
      self.includedItemsLabel.attributedText = display.includedItems
      self.estimatedShippingStackView.isHidden = display.shippingHidden
      self.estimatedShippingLabel.text = display.shipping
      self.amountLabel.attributedText = display.amount
      self.pillsView.isHidden = display.pills.isEmpty
      self.configurePillsView(display.pills)
      self.rewardLocationStackView.isHidden = display.pickupHidden
      self.rewardLocationPickupLabel.text = display.pickup
      self.rewardTitleLabel.text = display.title
      self.stepper.maximumValue = display.maximum
      self.rewardImageView.isHidden = display.image == nil
      self.rewardImageView.af.cancelImageRequest()
      self.rewardImageView.image = nil
      self.rewardImageView.accessibilityLabel = display.image?.altText
      if let url = display.image?.url.flatMap(URL.init(string:)) {
        self.rewardImageView.ksr_setImageWithURL(url)
      }
    }

    self.viewModel.onQuantity = { [weak self] quantity in
      self?.addButton.isHidden = quantity > 0
      self?.quantityLabel.text = String(quantity)
      self?.stepperStackView.isHidden = quantity == 0
      self?.stepper.value = Double(quantity)
    }
    self.viewModel.onQuantitySelected = { [weak self] quantity, rewardId in
      guard let self else { return }
      self.delegate?.rewardAddOnCardView(self, didSelectQuantity: quantity, rewardId: rewardId)
    }
    self.viewModel.onSelectionFeedback = { generateSelectionFeedback() }
    self.viewModel.onWarningFeedback = { generateNotificationWarningFeedback() }


  }

  // MARK: - Private Helpers

  private func configureViews() {
    self.addSubview(self.rootStackView)
    self.rootStackView.constrainViewToEdges(in: self)
    self.rootStackView.addArrangedSubviews(self.rewardImageView, self.detailsStackView)

    self.rewardImageView.isHidden = true

    self.detailsStackView.addArrangedSubviews(
      self.rewardTitleLabel,
      self.titleAmountStackView,
      self.descriptionLabel,
      self.estimatedShippingStackView,
      self.includedItemsStackView,
      self.rewardLocationStackView,
      self.pillsView,
      self.addButton,
      self.stepperStackView
    )

    self.titleAmountStackView.addArrangedSubviews(
      self.rewardTitleLabel,
      self.amountLabel,
      self.amountConversionLabel
    )

    self.includedItemsStackView.addArrangedSubviews(
      self.includedItemsSeparator,
      self.includedItemsTitleLabel,
      self.includedItemsLabel
    )

    self.estimatedShippingStackView.addArrangedSubviews(
      self.estimatedShippingSeparator,
      self.estimatedShippingTitleLabel,
      self.estimatedShippingLabel
    )

    self.quantityLabelContainer.addSubview(self.quantityLabel)
    self.quantityLabel.constrainViewToMargins(in: self.quantityLabelContainer)

    self.stepperStackView.addArrangedSubviews(
      self.stepper,
      UIView(),
      self.quantityLabelContainer
    )
  }

  private func setupConstraints() {
    self.detailsStackView.translatesAutoresizingMaskIntoConstraints = false

    let pillsViewHeightConstraint = self.pillsView.heightAnchor.constraint(equalToConstant: 0)
    self.pillsViewHeightConstraint = pillsViewHeightConstraint

    let pillCollectionViewConstraints = [
      self.addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Styles.minTouchSize.height),
      self.stepperStackView.heightAnchor.constraint(equalTo: self.addButton.heightAnchor),
      self.includedItemsSeparator.heightAnchor.constraint(equalToConstant: 1),
      pillsViewHeightConstraint
    ]

    NSLayoutConstraint.activate(pillCollectionViewConstraints)

    let aspectRatio: CGFloat = 1.5
    let rewardImageViewConstraint = self.rewardImageView.heightAnchor.constraint(
      equalTo: self.rewardImageView.widthAnchor,
      multiplier: 1.0 / aspectRatio
    )
    rewardImageViewConstraint.priority = UILayoutPriority(rawValue: 999)
    rewardImageViewConstraint.isActive = true
  }

  private func configurePillsView(_ pills: [String]) {
    let pillData = pills.map { text -> PillData in
      PillData(
        backgroundColor: LegacyColors.Tags.Warn.background.uiColor(),
        font: UIFont.ksr_footnote().bolded,
        margins: UIEdgeInsets(topBottom: Styles.gridHalf(2), leftRight: Styles.gridHalf(3)),
        text: text,
        textColor: LegacyColors.Tags.Warn.foreground.uiColor(),
        imageName: nil
      )
    }

    let data = PillsViewData(
      interimLineSpacing: Styles.grid(1),
      interimPillSpacing: Styles.grid(1),
      margins: .zero,
      pills: pillData
    )

    self.pillsView.configure(with: data)
  }

  // MARK: - Configuration

  internal func configure(with data: RewardAddOnCardViewData) {
    self.viewModel.configure(with: data)

    self.layoutIfNeeded()
  }

  // MARK: - Actions

  @objc func addButtonTapped() {
    self.viewModel.addButtonTapped()
  }

  @objc func stepperValueChanged(_ stepper: UIStepper) {
    self.viewModel.stepperValueChanged(stepper.value)
  }
}

// MARK: - Styles

@MainActor
private func applyIncludedItemsTitleLabel(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.font = .ksr_callout().weighted(.semibold)
  label.text = Strings.project_view_pledge_includes()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyEstimatedShippingTitleLabel(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.font = .ksr_callout().weighted(.semibold)
  label.text = Strings.Estimated_Shipping()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyEstimatedShippingLabel(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.font = .ksr_callout()
}

@MainActor
private func applyIncludedItemsLabel(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.font = .ksr_callout()
}

@MainActor
private func applyBaseRewardLabelStyle(_ label: UILabel) {
  label.numberOfLines = 0
  label.textAlignment = .left
  label.lineBreakMode = .byWordWrapping
}

@MainActor
private func applyDetailsStackViewStyle(_ stackView: UIStackView) {
  stackView.isLayoutMarginsRelativeArrangement = true
  stackView.layoutMargins = .init(all: Styles.grid(3))
  stackView.spacing = Styles.grid(3)
}

@MainActor
private func applyIncludedItemsStackViewStyle(_ stackView: UIStackView) {
  stackView.spacing = Styles.grid(2)
}

@MainActor
private func applyAmountLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.textColor = LegacyColors.ksr_create_700.uiColor()
  label.font = UIFont.ksr_title3().bolded
}

@MainActor
private func applyAmountConvertedLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.textColor = LegacyColors.ksr_support_400.uiColor()
  label.font = UIFont.ksr_footnote().weighted(.medium)
}

@MainActor
private func applyDescriptionLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.textColor = LegacyColors.ksr_support_700.uiColor()
  label.font = UIFont.ksr_body()
}

@MainActor
private func applyTitleAmountStackViewStyle(_ stackView: UIStackView) {
  stackView.axis = .vertical
  stackView.spacing = Styles.gridHalf(1)
}

@MainActor
private func applyRewardTitleLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.textColor = LegacyColors.ksr_support_700.uiColor()
  label.font = UIFont.ksr_title3().bolded
}

@MainActor
private func applySectionStackViewStyle(_ stackView: UIStackView) {
  stackView.axis = .vertical
  stackView.spacing = Styles.grid(1)
}

@MainActor
private func applySectionBodyLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  label.textColor = LegacyColors.ksr_support_700.uiColor()
  label.font = UIFont.ksr_body()
}

@MainActor
private func applyRootStackViewStyle(_ stackView: UIStackView) {
  stackView.axis = .vertical
}

@MainActor
private func applyRewardImageViewStyle(_ imageView: UIImageView) {
  imageView.contentMode = .scaleAspectFill
  imageView.clipsToBounds = true
}

@MainActor
private func applyQuantityLabelContainerStyle(_ view: UIView) {
  _ = checkoutRoundedCornersStyle(view)
  view.layoutMargins = .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))
  view.layer.borderColor = LegacyColors.ksr_support_300.uiColor().cgColor
  view.layer.borderWidth = 1
}

@MainActor
private func applyQuantityLabelStyle(_ label: UILabel) {
  label.font = UIFont.ksr_headline().monospaced
}

@MainActor
private func applyStepperStyle(_ stepper: UIStepper) {
  _ = checkoutStepperStyle(stepper)
  stepper.setDecrementImage(image(named: "stepper-decrement-normal-grey"), for: .normal)
  stepper.setIncrementImage(image(named: "stepper-increment-normal-grey"), for: .normal)
}

@MainActor
private func applyStepperStackViewStyle(_ stackView: UIStackView) {
  stackView.alignment = .center
}

@MainActor
private func applyAddButtonStyle(_ button: UIButton) {
  button.applyStyleConfiguration(KSRButtonStyle.filled)
  button.setTitle(Strings.Add(), for: .normal)
}

@MainActor
private func applyRewardLocationTitleLabelStyle(_ label: UILabel) {
  applySectionBodyLabelStyle(label)
  label.text = Strings.Reward_location()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
  label.font = .ksr_headline()
}
