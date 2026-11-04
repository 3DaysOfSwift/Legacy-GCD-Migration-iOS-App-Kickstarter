import Foundation
import KDS
import KsApi

import Prelude
import UIKit

internal final class BackerDashboardProjectCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = BackerDashboardProjectCellViewModel()

  private lazy var cardView: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var mainContentContainerView: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var metadataBackgroundView: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var metadataIconImageView: UIImageView = {
    UIImageView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var metadataLabel: UILabel = {
    UILabel(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var percentFundedLabel: UILabel = {
    UILabel(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var projectNameLabel: UILabel = {
    UILabel(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var projectImageView: UIImageView = {
    UIImageView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var progressStaticView: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var progressBarView: UIView = {
    UIView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var savedIconImageView: UIImageView = {
    UIImageView(frame: .zero)
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  internal func configureWith(value: any BackerDashboardProjectCellViewModel.ProjectCellModel) {
    self.viewModel.configureWith(project: value)
  }

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    self.configureViews()
    self.bindViewModel()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configureViews() {
    self.contentView.addSubview(self.cardView)
    self.cardView.constrainViewToMargins(in: self.contentView)

    self.configureProjectImageViews()
    self.configureMetadataViews()
    self.configureMainContentViews()
  }

  private func configureProjectImageViews() {
    self.cardView.addSubview(self.projectImageView)
    self.cardView.addSubview(self.savedIconImageView)

    self.projectImageView.setContentHuggingPriority(.required, for: .horizontal)
    self.projectImageView.setContentCompressionResistancePriority(.required, for: .vertical)

    self.savedIconImageView.image = Kickstarter_iOS.image(named: "icon--heart-circle")

    NSLayoutConstraint.activate([
      self.projectImageView.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor),
      self.projectImageView.topAnchor.constraint(equalTo: self.cardView.topAnchor),
      self.projectImageView.heightAnchor.constraint(equalToConstant: 84),
      self.projectImageView.widthAnchor.constraint(
        equalTo: self.projectImageView.heightAnchor,
        multiplier: 16.0 / 9.0
      ),
      self.projectImageView.bottomAnchor.constraint(lessThanOrEqualTo: self.cardView.bottomAnchor),

      self.savedIconImageView.topAnchor.constraint(
        equalTo: self.projectImageView.topAnchor,
        constant: Spacing.unit_02
      ),
      self.savedIconImageView.trailingAnchor.constraint(
        equalTo: self.projectImageView.trailingAnchor,
        constant: -Spacing.unit_02
      ),
      self.savedIconImageView.heightAnchor.constraint(equalToConstant: 17),
      self.savedIconImageView.widthAnchor.constraint(equalToConstant: 17)
    ])
  }

  private func configureMetadataViews() {
    let metadataStackView = UIStackView()
    metadataStackView.translatesAutoresizingMaskIntoConstraints = false
    metadataStackView.addArrangedSubviews(self.metadataIconImageView, self.metadataLabel)
    metadataStackView.spacing = Spacing.unit_02
    metadataStackView.alignment = .center
    metadataStackView.isLayoutMarginsRelativeArrangement = true
    metadataStackView.layoutMargins = UIEdgeInsets(leftRight: Spacing.unit_01)

    self.cardView.addSubview(self.metadataBackgroundView)
    self.cardView.addSubview(metadataStackView)

    self.metadataIconImageView.image = Kickstarter_iOS.image(named: "timer-icon")
    self.metadataLabel.numberOfLines = 0

    NSLayoutConstraint.activate([
      self.metadataBackgroundView.leadingAnchor.constraint(
        equalTo: self.cardView.leadingAnchor,
        constant: Spacing.unit_02
      ),
      self.metadataBackgroundView.bottomAnchor.constraint(
        equalTo: self.cardView.bottomAnchor,
        constant: -Spacing.unit_02
      ),
      self.metadataBackgroundView.trailingAnchor
        .constraint(lessThanOrEqualTo: self.projectImageView.trailingAnchor),

      self.metadataIconImageView.widthAnchor.constraint(equalToConstant: 14),
      self.metadataIconImageView.heightAnchor.constraint(equalToConstant: 14)
    ])

    metadataStackView.constrainViewToMargins(in: self.metadataBackgroundView)
  }

  private func configureMainContentViews() {
    self.cardView.addSubview(self.mainContentContainerView)

    self.mainContentContainerView.addSubview(self.projectNameLabel)
    self.mainContentContainerView.addSubview(self.percentFundedLabel)
    self.mainContentContainerView.addSubview(self.progressStaticView)
    self.mainContentContainerView.addSubview(self.progressBarView)

    self.projectNameLabel.numberOfLines =
      self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 3 : 2

    self.percentFundedLabel.setContentCompressionResistancePriority(.required, for: .vertical)

    NSLayoutConstraint.activate([
      self.mainContentContainerView.leadingAnchor.constraint(
        equalTo: self.projectImageView.trailingAnchor,
        constant: Spacing.unit_03
      ),
      self.mainContentContainerView.topAnchor.constraint(
        equalTo: self.cardView.topAnchor,
        constant: Spacing.unit_02
      ),
      self.mainContentContainerView.trailingAnchor.constraint(
        equalTo: self.cardView.trailingAnchor,
        constant: -Spacing.unit_03
      ),
      self.mainContentContainerView.bottomAnchor.constraint(
        equalTo: self.cardView.bottomAnchor,
        constant: -Spacing.unit_02
      ),

      self.projectNameLabel.leadingAnchor.constraint(equalTo: self.mainContentContainerView.leadingAnchor),
      self.projectNameLabel.topAnchor.constraint(equalTo: self.mainContentContainerView.topAnchor),
      self.projectNameLabel.trailingAnchor.constraint(equalTo: self.mainContentContainerView.trailingAnchor),
      self.projectNameLabel.bottomAnchor.constraint(lessThanOrEqualTo: self.percentFundedLabel.topAnchor),

      self.percentFundedLabel.trailingAnchor
        .constraint(equalTo: self.mainContentContainerView.trailingAnchor),
      self.percentFundedLabel.bottomAnchor.constraint(equalTo: self.mainContentContainerView.bottomAnchor),

      self.progressStaticView.heightAnchor.constraint(equalToConstant: 3),
      self.progressStaticView.leadingAnchor.constraint(equalTo: self.mainContentContainerView.leadingAnchor),
      self.progressStaticView.centerYAnchor.constraint(equalTo: self.percentFundedLabel.centerYAnchor),
      self.progressStaticView.trailingAnchor.constraint(
        equalTo: self.percentFundedLabel.leadingAnchor,
        constant: -Spacing.unit_06
      )
    ])

    self.progressBarView.constrainViewToEdges(in: self.progressStaticView)
  }

  internal override func bindViewModel() {
    self.viewModel.onChange = { [weak self] in self?.renderProject() }
  }

  private func renderProject() {
    guard let state = self.viewModel.state else { return }
    self.metadataBackgroundView.backgroundColor = state.metadataBackgroundColor
    self.metadataLabel.text = state.metadataText
    self.metadataIconImageView.isHidden = state.metadataIconIsHidden
    self.percentFundedLabel.attributedText = state.percentFundedText
    self.projectNameLabel.attributedText = state.projectTitleText
    self.projectImageView.af.cancelImageRequest()
    self.projectImageView.image = nil
    if let url = state.photoURL { self.projectImageView.ksr_setImageWithURL(url) }
    self.progressBarView.backgroundColor = state.progressBarColor
    self.progressBarView.isHidden = state.prelaunchProject
    self.progressStaticView.isHidden = state.prelaunchProject
    self.percentFundedLabel.isHidden = state.prelaunchProject
    self.savedIconImageView.isHidden = state.savedIconIsHidden
    let anchorX = state.progress == 0 ? 0 : 0.5 / state.progress
    self.progressBarView.layer.anchorPoint = CGPoint(x: CGFloat(max(anchorX, 0.5)), y: 0.5)
    self.progressBarView.transform = CGAffineTransform(scaleX: CGFloat(min(state.progress, 1.0)), y: 1)
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> UITableViewCell.lens.isAccessibilityElement .~ true
      |> UITableViewCell.lens.accessibilityHint %~ { _ in Strings.Opens_project() }
      |> UITableViewCell.lens.accessibilityTraits .~ UIAccessibilityTraits.button
      |> UITableViewCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(2), leftRight: Styles.grid(20))
          : .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))
      }

    _ = self.cardView
      |> cardStyle()

    _ = self.metadataBackgroundView
      |> UIView.lens.layer.borderColor .~ LegacyColors.ksr_white.uiColor().cgColor
      |> UIView.lens.layer.borderWidth .~ 1.0

    _ = self.metadataLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_white.uiColor()
      |> UILabel.lens.font .~ .ksr_headline(size: 12)

    _ = self.metadataIconImageView
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.percentFundedLabel
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.projectNameLabel
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.progressStaticView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UIView.lens.alpha .~ 0.15

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.savedIconImageView
      |> UIImageView.lens.tintColor .~ .init(white: 1.0, alpha: 0.99)
  }
}
