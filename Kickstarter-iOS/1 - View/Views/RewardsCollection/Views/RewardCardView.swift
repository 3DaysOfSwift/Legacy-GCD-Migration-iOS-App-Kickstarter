import KDS
import KsApi

import UIKit

@MainActor
protocol RewardCardViewDelegate: AnyObject {
  func rewardCardView(_ rewardCardView: RewardCardView, didTapWithRewardId rewardId: Int)
}

public final class RewardCardView: UIView {
  // MARK: - Properties

  weak var delegate: RewardCardViewDelegate?
  private let viewModel = RewardCardViewModel()

  private let rootStackView: UIStackView = UIStackView(frame: .zero)

  private let detailsStackView: UIStackView = UIStackView(frame: .zero)

  private let rewardImageView = UIImageView(frame: .zero)
  private let rewardBadgeView = BadgeView(frame: .zero)
  private let descriptionLabel = UILabel(frame: .zero)
  private let descriptionStackView = UIStackView(frame: .zero)
  private let estimatedDeliveryStackView = UIStackView(frame: .zero)
  private let estimatedDeliveryTitleLabel = UILabel(frame: .zero)
  private let estimatedDeliveryDateLabel = UILabel(frame: .zero)
  private let includedItemsStackView = UIStackView(frame: .zero)
  private let includedItemsTitleLabel = UILabel(frame: .zero)
  private let minimumPriceConversionLabel = UILabel(frame: .zero)
  private let minimumPriceLabel = UILabel(frame: .zero)
  private let pillsView: PillsView = PillsView(frame: .zero)
  private var pillsViewHeightConstraint: NSLayoutConstraint?
  private let priceStackView = UIStackView(frame: .zero)
  private let rewardLocationStackView = UIStackView(frame: .zero)
  private let rewardLocationTitleLabel = UILabel(frame: .zero)
  private let rewardLocationPickupLabel = UILabel(frame: .zero)
  private let rewardTitleLabel = UILabel(frame: .zero)
  private let titleStackView = UIStackView(frame: .zero)

  private let estimatedShippingStackView = UIStackView(frame: .zero)
  private let estimatedShippingTitleLabel = UILabel(frame: .zero)
  private let estimatedShippingLabel = UILabel(frame: .zero)

  override init(frame: CGRect) {
    super.init(frame: frame)

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

    let stackViews = [
      self.detailsStackView,
      self.priceStackView,
      self.descriptionStackView,
      self.includedItemsStackView,
      self.estimatedShippingStackView,
      self.estimatedDeliveryStackView,
      self.rewardLocationStackView
    ]

    stackViews.forEach(applySectionStackViewStyle)
    applyRootStackViewStyle(self.rootStackView)
    applyDetailsStackViewStyle(self.detailsStackView)
    applyPriceStackViewStyle(self.priceStackView)
    applyIncludedItemsStackViewStyle(self.includedItemsStackView)
    applyIncludedItemsTitleLabelStyle(self.includedItemsTitleLabel)

    self.includedItemsStackView.subviews
      .dropFirst()
      .compactMap { $0 as? UILabel }
      .forEach { label in
        applyBaseRewardLabelStyle(label)
        applySectionBodyLabelStyle(label)
      }

    applyBaseRewardLabelStyle(self.descriptionLabel)
    applySectionBodyLabelStyle(self.descriptionLabel)
    applyIncludedItemsStackViewStyle(self.estimatedDeliveryStackView)
    applyEstimatedDeliveryTitleLabelStyle(self.estimatedDeliveryTitleLabel)
    applyBaseRewardLabelStyle(self.estimatedDeliveryDateLabel)
    applySectionBodyLabelStyle(self.estimatedDeliveryDateLabel)

    self.estimatedDeliveryStackView.subviews
      .dropFirst()
      .compactMap { $0 as? UILabel }
      .forEach { label in
        applyBaseRewardLabelStyle(label)
        applySectionBodyLabelStyle(label)
      }

    applyIncludedItemsStackViewStyle(self.estimatedShippingStackView)
    applyEstimatedShippingTitleLabelStyle(self.estimatedShippingTitleLabel)
    applyBaseRewardLabelStyle(self.estimatedShippingLabel)
    applySectionBodyLabelStyle(self.estimatedShippingLabel)

    self.estimatedShippingStackView.subviews
      .dropFirst()
      .compactMap { $0 as? UILabel }
      .forEach { label in
        applyBaseRewardLabelStyle(label)
        applySectionBodyLabelStyle(label)
      }

    applyIncludedItemsStackViewStyle(self.rewardLocationStackView)
    applyRewardLocationTitleLabelStyle(self.rewardLocationTitleLabel)
    applyBaseRewardLabelStyle(self.rewardLocationPickupLabel)
    applySectionBodyLabelStyle(self.rewardLocationPickupLabel)

    self.rewardLocationStackView.subviews
      .dropFirst()
      .compactMap { $0 as? UILabel }
      .forEach { label in
        applyBaseRewardLabelStyle(label)
        applySectionBodyLabelStyle(label)
      }

    applyBaseRewardLabelStyle(self.rewardTitleLabel)
    applyRewardTitleLabelStyle(self.rewardTitleLabel)
    applyBaseRewardLabelStyle(self.minimumPriceLabel)
    applyMinimumPriceLabelStyle(self.minimumPriceLabel)
    applyBaseRewardLabelStyle(self.minimumPriceConversionLabel)
    applyMinimumPriceConversionLabelStyle(self.minimumPriceConversionLabel)
    applyPillsViewStyle(self.pillsView)
    applyRewardImageViewStyle(self.rewardImageView)
  }

  public override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onDisplay = { [weak self] display in
      guard let self else { return }
      self.minimumPriceConversionLabel.isHidden = display.conversionText == nil
      if let text = display.conversionText { self.minimumPriceConversionLabel.text = text }
      self.descriptionLabel.text = display.description
      self.estimatedShippingStackView.isHidden = display.shippingHidden
      if let text = display.shippingText { self.estimatedShippingLabel.text = text }
      self.estimatedDeliveryStackView.isHidden = display.deliveryHidden
      if let text = display.deliveryText { self.estimatedDeliveryDateLabel.text = text }
      self.rewardLocationStackView.isHidden = display.pickupHidden
      if let text = display.pickupText { self.rewardLocationPickupLabel.text = text }
      self.includedItemsStackView.isHidden = display.items.isEmpty
      self.minimumPriceLabel.text = display.minimumText
      self.pillsView.isHidden = display.pills.isEmpty
      self.rewardTitleLabel.isHidden = display.titleHidden
      self.rewardTitleLabel.attributedText = display.title
      self.rewardImageView.isHidden = display.image == nil
      self.load(items: display.items)
      self.isUserInteractionEnabled = display.interactionEnabled
      self.configurePillsView(display.pills)
      if let image = display.image {
        self.rewardImageView.af.cancelImageRequest()
        self.rewardImageView.image = nil
        self.rewardImageView.accessibilityLabel = image.altText
        if let url = image.url, let imageURL = URL(string: url) {
          self.rewardImageView.ksr_setImageWithURL(imageURL)
        }
      }
      if let badge = display.badge {
        self.rewardBadgeView.configure(with: badge.text, image: badge.image, style: badge.badgeStyle)
        self.rewardBadgeView.isHidden = false
      } else {
        self.rewardBadgeView.isHidden = true
      }
    }
    self.viewModel.onRewardSelected = { [weak self] rewardID in
      guard let self else { return }
      self.delegate?.rewardCardView(self, didTapWithRewardId: rewardID)
    }
  }

  // MARK: - Private Helpers

  private func configureViews() {
    self.addSubview(self.rootStackView)
    self.rootStackView.constrainViewToEdges(in: self)
    self.rootStackView.addArrangedSubviews(self.rewardImageView, self.detailsStackView)

    self.addSubview(self.rewardBadgeView)

    self.rewardImageView.isHidden = true

    self.detailsStackView.addArrangedSubviews(
      self.titleStackView,
      self.rewardTitleLabel,
      self.descriptionStackView,
      self.includedItemsStackView,
      self.estimatedShippingStackView,
      self.estimatedDeliveryStackView,
      self.rewardLocationStackView,
      self.pillsView
    )

    self.priceStackView.addArrangedSubviews(
      self.minimumPriceLabel,
      self.minimumPriceConversionLabel
    )

    self.includedItemsStackView.addArrangedSubview(self.includedItemsTitleLabel)

    self.estimatedShippingStackView.addArrangedSubviews(
      self.estimatedShippingTitleLabel,
      self.estimatedShippingLabel
    )

    self.estimatedDeliveryStackView.addArrangedSubviews(
      self.estimatedDeliveryTitleLabel,
      self.estimatedDeliveryDateLabel
    )

    self.rewardLocationStackView.addArrangedSubviews(
      self.rewardLocationTitleLabel,
      self.rewardLocationPickupLabel
    )

    self.descriptionStackView.addArrangedSubview(self.descriptionLabel)
    self.titleStackView.addArrangedSubview(self.priceStackView)

    let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.rewardCardTapped))
    self.addGestureRecognizer(tapGestureRecognizer)
  }

  private func setupConstraints() {
    self.detailsStackView.translatesAutoresizingMaskIntoConstraints = false

    let pillsViewHeightConstraint = self.pillsView.heightAnchor.constraint(equalToConstant: 0)
    self.pillsViewHeightConstraint = pillsViewHeightConstraint

    NSLayoutConstraint.activate([pillsViewHeightConstraint])

    let aspectRatio: CGFloat = 1.5
    let constratint = self.rewardImageView.heightAnchor.constraint(
      equalTo: self.rewardImageView.widthAnchor,
      multiplier: 1.0 / aspectRatio
    )
    constratint.priority = UILayoutPriority(rawValue: 999)
    constratint.isActive = true

    self.rewardBadgeView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      self.rewardBadgeView.bottomAnchor.constraint(
        equalTo: self.detailsStackView.topAnchor,
        constant: Styles.grid(2)
      ),
      self.rewardBadgeView.leadingAnchor.constraint(
        equalTo: self.leadingAnchor,
        constant: Styles.grid(3)
      )
    ])
  }

  private func configurePillsView(_ pills: [RewardCardPillData]) {
    let pillData = pills.map { rewardCardPillData -> PillData in
      PillData(
        backgroundColor: rewardCardPillData.backgroundColor,
        font: UIFont.ksr_footnote().bolded,
        margins: UIEdgeInsets(topBottom: Styles.gridHalf(2), leftRight: Styles.gridHalf(3)),
        text: rewardCardPillData.text,
        textColor: rewardCardPillData.textColor,
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

  fileprivate func load(items: [String]) {
    self.includedItemsStackView.subviews
      .forEach { $0.removeFromSuperview() }

    let includedItemViews = items.map { item -> UIView in
      let label = UILabel()
      applyBaseRewardLabelStyle(label)
      applySectionBodyLabelStyle(label)
      label.text = item
      return label
    }

    let separatedItemViews = includedItemViews.dropLast().map { view -> [UIView] in
      let separator = UIView()
      _ = separatorStyle(separator)
      separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

      return [view, separator]
    }
    .flatMap { $0 }

    let allItemViews = [self.includedItemsTitleLabel]
      + separatedItemViews
      + [includedItemViews.last].compact()

    self.includedItemsStackView.addArrangedSubviews(allItemViews)
  }

  // MARK: - Configuration

  internal func configure(with data: RewardCardViewData) {
    self.viewModel.configure(with: data)
  }

  // MARK: - Selectors

  @objc func rewardCardTapped() {
    self.viewModel.rewardCardTapped()
  }
}

// MARK: - Styles

@MainActor
private func applyBaseRewardLabelStyle(_ label: UILabel) {
  label.numberOfLines = 0
  label.textAlignment = .left
  label.lineBreakMode = .byWordWrapping
}

@MainActor
private func applySectionTitleLabelStyle(_ label: UILabel) {
  label.font = .ksr_headline()
}

@MainActor
private func applyIncludedItemsTitleLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  applySectionTitleLabelStyle(label)
  label.text = Strings.project_view_pledge_includes()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyEstimatedDeliveryTitleLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  applySectionTitleLabelStyle(label)
  label.text = Strings.Estimated_delivery()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyEstimatedShippingTitleLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  applySectionTitleLabelStyle(label)
  label.text = Strings.Estimated_Shipping()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyRewardLocationTitleLabelStyle(_ label: UILabel) {
  applyBaseRewardLabelStyle(label)
  applySectionTitleLabelStyle(label)
  label.text = Strings.Reward_location()
  label.textColor = LegacyColors.ksr_support_400.uiColor()
}

@MainActor
private func applyPillsViewStyle(_ view: PillsView) {
  view.backgroundColor = view.backgroundColor
}

@MainActor
private func applySectionStackViewStyle(_ stackView: UIStackView) {
  stackView.axis = .vertical
  stackView.spacing = Styles.grid(1)
}

@MainActor
private func applyDetailsStackViewStyle(_ stackView: UIStackView) {
  stackView.spacing = Styles.grid(3)
  stackView.isLayoutMarginsRelativeArrangement = true
  stackView.layoutMargins = .init(all: Styles.grid(3))
}

@MainActor
private func applyPriceStackViewStyle(_ stackView: UIStackView) {
  stackView.spacing = Styles.gridHalf(1)
}

@MainActor
private func applySectionBodyLabelStyle(_ label: UILabel) {
  label.textColor = LegacyColors.ksr_support_700.uiColor()
  label.font = UIFont.ksr_body()
}

@MainActor
private func applyIncludedItemsStackViewStyle(_ stackView: UIStackView) {
  stackView.spacing = Styles.grid(2)
}

@MainActor
private func applyRewardTitleLabelStyle(_ label: UILabel) {
  label.textColor = LegacyColors.ksr_support_700.uiColor()
  label.font = UIFont.ksr_title2().bolded
}

@MainActor
private func applyMinimumPriceLabelStyle(_ label: UILabel) {
  label.textColor = LegacyColors.ksr_create_700.uiColor()
  label.font = UIFont.ksr_title3().bolded
}

@MainActor
private func applyMinimumPriceConversionLabelStyle(_ label: UILabel) {
  label.textColor = LegacyColors.ksr_create_700.uiColor()
  label.font = UIFont.ksr_caption1().bolded
}

@MainActor
private func applyRewardImageViewStyle(_ imageView: UIImageView) {
  imageView.contentMode = .scaleAspectFill
  imageView.clipsToBounds = true
}

// MARK: - UICollectionViewDelegate

extension RewardCardView: UICollectionViewDelegate {
  public func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt _: IndexPath
  ) {
    guard let pillCell = cell as? PillCell else { return }

    pillCell.label.preferredMaxLayoutWidth = collectionView.bounds.width
  }
}

@MainActor
private func applyRootStackViewStyle(_ stackView: UIStackView) {
  stackView.axis = .vertical
  stackView.backgroundColor = Colors.Background.Surface.primary.uiColor()
  stackView.rounded(with: Styles.grid(3))
}
