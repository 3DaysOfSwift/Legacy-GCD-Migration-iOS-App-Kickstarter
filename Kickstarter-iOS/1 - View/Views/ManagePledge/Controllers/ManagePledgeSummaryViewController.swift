import Foundation
import KDS
import KsApi

import Prelude
import UIKit

private enum Layout {
  static let avatarWidth: CGFloat = 54.0
}

final class ManagePledgeSummaryViewController: UIViewController {
  // MARK: - Properties

  private lazy var backerInfoContainerStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var backerInfoStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var backerNameLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var backerNumberLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var backingDateLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var circleAvatarImageView: CircleAvatarImageView = {
    CircleAvatarImageView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var pledgeStatusLabelView: PledgeStatusLabelView = {
    PledgeStatusLabelView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var rewardReceivedViewController: ManageViewPledgeRewardReceivedViewController = {
    ManageViewPledgeRewardReceivedViewController.instantiate()
  }()

  private lazy var pledgeAmountSummaryViewController: PledgeAmountSummaryViewController = {
    PledgeAmountSummaryViewController.instantiate()
  }()

  private lazy var rootStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var totalAmountLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var totalAmountStackView: UIStackView = { UIStackView(frame: .zero) }()
  private lazy var totalLabel: UILabel = { UILabel(frame: .zero) }()

  private let viewModel = ManagePledgeSummaryViewModel()

  // MARK: - Lifecycle

  public func configureWith(_ data: ManagePledgeSummaryViewData) {
    self.viewModel.configureWith(data)
    if self.isViewLoaded { self.renderSummary() }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.configureViews()
    self.setupConstraints()

    self.viewModel.viewDidLoad()
    self.renderSummary()
  }

  // MARK: - Styles

  override func bindStyles() {
    super.bindStyles()

    _ = self.circleAvatarImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.backerInfoContainerStackView
      |> adaptableStackViewStyle(
        self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      )
      |> backerInfoContainerStackViewStyle

    _ = self.backerNameLabel
      |> backerNameLabelStyle

    _ = self.backerInfoStackView
      |> backerInfoStackViewStyle

    _ = self.rootStackView
      |> rootStackViewStyle

    _ = self.totalAmountStackView
      |> adaptableStackViewStyle(
        self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
      )

    _ = self.backerNumberLabel
      |> backerNumberLabelStyle

    _ = self.backingDateLabel
      |> backingDateLabelStyle

    _ = self.totalLabel
      |> totalLabelStyle

    _ = self.totalAmountLabel
      |> amountLabelStyle
  }

  // MARK: - View model

  private func renderSummary() {
    let model = self.viewModel
    guard let data = model.data else { return }
    if let summary = model.configurePledgeAmountSummaryViewWithData { self.pledgeAmountSummaryViewController.configureWith(summary) }
    if let status = model.configurePledgeStatusLabelViewWithProject { self.pledgeStatusLabelView.configure(with: status) }
    if let (url, placeholder) = model.backerImageURLAndPlaceholderImageName {
      self.circleAvatarImageView.af.cancelImageRequest()
      self.circleAvatarImageView.image = nil
      self.circleAvatarImageView.ksr_setImageWithURL(url, placeholderImage: image(named: placeholder))
    }
    self.rewardReceivedViewController.configureWith(data: data.rewardReceivedWithData)
    if let hidden = model.backerNameLabelHidden {
      self.backerNameLabel.isHidden = hidden
      self.circleAvatarImageView.isHidden = hidden
    }
    if let name = model.backerNameText { self.backerNameLabel.text = name }
    self.backerNumberLabel.text = model.backerNumberText
    self.backingDateLabel.text = model.backingDateText
    self.rewardReceivedViewController.view.isHidden = data.rewardReceivedViewControllerViewIsHidden
    if let amount = model.totalAmountText { self.totalAmountLabel.attributedText = amount }
  }

  // MARK: - Functions

  private func configureViews() {
    _ = (self.rootStackView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([self.circleAvatarImageView, self.backerInfoStackView], self.backerInfoContainerStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.backerNameLabel, self.backerNumberLabel, self.backingDateLabel], self.backerInfoStackView)
      |> ksr_addArrangedSubviewsToStackView()

    _ = ([self.totalLabel, self.totalAmountLabel], self.totalAmountStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.addChild(self.rewardReceivedViewController)
    self.addChild(self.pledgeAmountSummaryViewController)

    let arrangedSubviews = [
      self.backerInfoContainerStackView,
      self.pledgeStatusLabelView,
      self.rewardReceivedViewController.view,
      self.pledgeAmountSummaryViewController.view,
      self.totalAmountStackView
    ]
    .compact()

    _ = (arrangedSubviews, self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.pledgeAmountSummaryViewController.didMove(toParent: self)
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      self.circleAvatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarWidth),
      self.circleAvatarImageView.heightAnchor.constraint(equalTo: self.circleAvatarImageView.widthAnchor)
    ])
  }
}

// MARK: - Styles

private let amountLabelStyle: LabelStyle = { label in
  label
    |> checkoutLabelStyle
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.textAlignment .~ NSTextAlignment.right
    |> \.isAccessibilityElement .~ true
    |> \.minimumScaleFactor .~ 0.75
}

private let backerInfoContainerStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> \.spacing .~ Styles.grid(3)
}

private let backerNameLabelStyle: LabelStyle = { label in
  label
    |> checkoutLabelStyle
    |> \.font .~ .ksr_headline()
    |> \.lineBreakMode .~ .byWordWrapping
    |> \.numberOfLines .~ 0
}

private let backerInfoStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> verticalStackViewStyle
    |> \.spacing .~ Styles.gridHalf(1)
}

private let backerNumberLabelStyle: LabelStyle = { label in
  label
    |> checkoutLabelStyle
    |> \.textColor .~ LegacyColors.ksr_support_700.uiColor()
    |> \.font .~ UIFont.ksr_footnote()
    |> \.adjustsFontForContentSizeCategory .~ true
}

private let backingDateLabelStyle: LabelStyle = { label in
  label
    |> checkoutLabelStyle
    |> \.font .~ UIFont.ksr_footnote()
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.numberOfLines .~ 0
}

private let rootStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> checkoutStackViewStyle
    |> \.spacing .~ Styles.grid(3)
}

private let totalLabelStyle: LabelStyle = { label in
  label
    |> checkoutLabelStyle
    |> \.textColor .~ LegacyColors.ksr_black.uiColor()
    |> \.font .~ UIFont.ksr_subhead().bolded
    |> \.adjustsFontForContentSizeCategory .~ true
    |> \.text %~ { _ in Strings.Total() }
}
