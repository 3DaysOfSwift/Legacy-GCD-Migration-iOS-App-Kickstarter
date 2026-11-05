import AlamofireImage
import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol DiscoveryPostcardCellDelegate: AnyObject {
  /// Called when the heart/save button is tapped
  func discoveryPostcardCellProjectSaveAlert()

  /// Called when logged out user taps heart/save button
  func discoveryPostcardCellGoToLoginTout()
}

internal final class DiscoveryPostcardCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = DiscoveryPostcardViewModel()
  private let watchProjectViewModel = WatchProjectViewModel()
  internal weak var delegate: DiscoveryPostcardCellDelegate?

  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var backgroundGradientView: GradientView!
  @IBOutlet fileprivate var backersSubtitleLabel: UILabel!
  @IBOutlet fileprivate var backersTitleLabel: UILabel!
  @IBOutlet fileprivate var deadlineSubtitleLabel: UILabel!
  @IBOutlet fileprivate var deadlineTitleLabel: UILabel!
  @IBOutlet fileprivate var fundingProgressBarView: UIView!
  @IBOutlet fileprivate var fundingProgressContainerView: UIView!
  @IBOutlet fileprivate var fundingSubtitleLabel: UILabel!
  @IBOutlet fileprivate var fundingTitleLabel: UILabel!
  @IBOutlet fileprivate var locationImageView: UIImageView!
  @IBOutlet fileprivate var locationLabel: UILabel!
  @IBOutlet fileprivate var locationStackView: UIStackView!
  @IBOutlet fileprivate var metadataIconImageView: UIImageView!
  @IBOutlet fileprivate var metadataLabel: UILabel!
  @IBOutlet fileprivate var metadataStackView: UIStackView!
  @IBOutlet fileprivate var metadataView: UIView!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var projectNameAndBlurbLabel: UILabel!
  @IBOutlet fileprivate var projectStateSubtitleLabel: UILabel!
  @IBOutlet fileprivate var projectCategoriesStackView: UIStackView!
  @IBOutlet fileprivate var projectStateTitleLabel: UILabel!
  @IBOutlet fileprivate var projectStateStackView: UIStackView!
  @IBOutlet fileprivate var projectStatsStackView: UIStackView!
  @IBOutlet fileprivate var saveButton: UIButton!
  @IBOutlet fileprivate var socialAvatarImageView: UIImageView!
  @IBOutlet fileprivate var socialLabel: UILabel!
  @IBOutlet fileprivate var socialStackView: UIStackView!
  @IBOutlet fileprivate var projectStatsSocialLocationStackView: UIStackView!

  fileprivate weak var projectCategoryView: DiscoveryProjectCategoryView!
  fileprivate weak var projectIsStaffPickView: DiscoveryProjectCategoryView!

  private var projectSavedObserver: MainActorNotificationObservation?
  private var sessionEndedObserver: MainActorNotificationObservation?
  private var sessionStartedObserver: MainActorNotificationObservation?

  internal override func awakeFromNib() {
    // UIKit nib loading is synchronous on the main thread.
    MainActor.assumeIsolated {
      if let categoryView = DiscoveryProjectCategoryView.fromNib(nib: Nib.DiscoveryProjectCategoryView) {
        self.projectCategoryView = categoryView

        self.projectCategoryView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.projectCategoryView.setContentHuggingPriority(.required, for: .horizontal)

        self.projectCategoriesStackView.addArrangedSubview(self.projectCategoryView)
      }

      if let staffPickView = DiscoveryProjectCategoryView.fromNib(nib: Nib.DiscoveryProjectCategoryView) {
        self.projectIsStaffPickView = staffPickView

        self.projectIsStaffPickView.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.projectIsStaffPickView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        self.projectCategoriesStackView.addArrangedSubview(self.projectIsStaffPickView)
      }

      self.saveButton.addTarget(self, action: #selector(self.saveButtonTapped(_:)), for: .touchUpInside)

      self.saveButton.addTarget(self, action: #selector(self.saveButtonPressed(_:)), for: .touchDown)

      self.sessionStartedObserver = MainActorNotificationObservation(name: .ksr_sessionStarted) { [weak self] _ in
        self?.watchProjectViewModel.userSessionStarted()
      }

      self.sessionEndedObserver = MainActorNotificationObservation(name: .ksr_sessionEnded) { [weak self] _ in
        self?.watchProjectViewModel.userSessionEnded()
      }

      self.projectSavedObserver = MainActorNotificationObservation(name: .ksr_projectSaved) { [weak self] notification in
        self?.watchProjectViewModel.projectFromNotification(
          project: notification.userInfo?["project"] as? Project
        )
      }

      self.watchProjectViewModel.awakeFromNib()
    }

    super.awakeFromNib()
  }

  internal override func bindStyles() {
    super.bindStyles()

    self.backgroundGradientView.startPoint = .zero
    self.backgroundGradientView.endPoint = CGPoint(x: 0, y: 1)
    let gradient: [(UIColor?, Float)] = [
      (UIColor.init(white: 0.0, alpha: 0.5), 0),
      (UIColor.init(white: 0.0, alpha: 0.0), 1)
    ]
    self.backgroundGradientView.setGradient(gradient)

    _ = self
      |> baseTableViewCellStyle()
      // Future: the top should adjust to grid(4) when there is metadata present.
      |> DiscoveryPostcardCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(4), leftRight: Styles.grid(30))
          : .init(topBottom: Styles.grid(3), leftRight: Styles.grid(2))
      }
      |> DiscoveryPostcardCell.lens.accessibilityHint %~ { _ in
        Strings.dashboard_tout_accessibility_hint_opens_project()
      }

    _ = [self.backersTitleLabel, self.deadlineTitleLabel]
      ||> postcardStatsTitleStyle

    _ = [self.backersSubtitleLabel, self.deadlineSubtitleLabel, self.fundingSubtitleLabel]
      ||> postcardStatsSubtitleStyle

    _ = [
      self.backersTitleLabel, self.backersSubtitleLabel, self.deadlineTitleLabel,
      self.deadlineSubtitleLabel
    ]
      ||> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.backersSubtitleLabel
      |> UILabel.lens.text %~ { _ in Strings.discovery_baseball_card_stats_backers() }

    _ = self.fundingTitleLabel
      |> postcardStatsTitleStyle
      |> UILabel.lens.textColor .~ LegacyColors.ksr_create_700.uiColor()

    _ = self.fundingSubtitleLabel
      |> UILabel.lens.text %~ { _ in Strings.discovery_baseball_card_stats_funded() }
      |> UILabel.lens.textColor .~ LegacyColors.ksr_create_700.uiColor()

    _ = self.cardView
      |> cardStyle()

    _ = self.fundingProgressContainerView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_300.uiColor()

    _ = self.fundingProgressBarView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_create_700.uiColor()

    _ = self.metadataIconImageView
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.metadataLabel
      |> postcardMetadataLabelStyle

    _ = self.metadataStackView
      |> postcardMetadataStackViewStyle

    _ = self.metadataView
      |> cardStyle()
      |> \.layoutMargins .~ .init(all: Styles.grid(1))

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.projectStatsSocialLocationStackView
      |> UIStackView.lens.spacing .~ Styles.grid(3)
      |> UIStackView.lens.layoutMargins .~ .init(topBottom: Styles.grid(4), leftRight: Styles.grid(3))
      |> UIStackView.lens.isLayoutMarginsRelativeArrangement .~ true

    _ = self.projectNameAndBlurbLabel
      |> UILabel.lens.numberOfLines .~ 3
      |> UILabel.lens.lineBreakMode .~ .byTruncatingTail
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.projectStateSubtitleLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_body(size: 13)
      |> UILabel.lens.numberOfLines .~ 1
      |> UILabel.lens.lineBreakMode .~ .byTruncatingTail

    _ = self.projectStateTitleLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 14)

    _ = self.projectStateStackView
      |> UIStackView.lens.spacing .~ Styles.grid(1)

    _ = self.projectStatsStackView
      |> UIStackView.lens.spacing .~ Styles.grid(4)

    styleDiscoverySaveButton(self.saveButton)

    _ = self.socialAvatarImageView
      |> UIImageView.lens.layer.shouldRasterize .~ true

    _ = self.socialAvatarImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.socialLabel
      |> UILabel.lens.numberOfLines .~ 2
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_headline(size: 13.0)

    _ = self.socialStackView
      |> UIStackView.lens.alignment .~ .center
      |> UIStackView.lens.spacing .~ Styles.grid(1)

    _ = self.locationStackView
      |> locationStackViewStyle

    _ = self.locationLabel
      |> locationLabelStyle

    _ = self.locationImageView
      |> locationImageViewStyle
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.watchProjectViewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .selected(value): self.saveButton.isSelected = value
      case .impact: generateImpactFeedback()
      case .success: generateNotificationSuccessFeedback()
      case .selection: generateSelectionFeedback()
      case .savedAlert: self.delegate?.discoveryPostcardCellProjectSaveAlert()
      case .login: self.delegate?.discoveryPostcardCellGoToLoginTout()
      case let .notification(notification): NotificationCenter.default.post(notification)
      case .project: break
      }
    }

    self.projectIsStaffPickView.configureWith(name: Strings.Projects_We_Love(), imageNameString: "icon--small-k")
    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .backersTitleLabelText(value): self.backersTitleLabel.text = value
      case let .backersSubtitleLabelText(value): self.backersSubtitleLabel.text = value
      case let .deadlineSubtitleLabelText(value): self.deadlineSubtitleLabel.text = value
      case let .deadlineTitleLabelText(value): self.deadlineTitleLabel.text = value
      case let .fundingProgressContainerViewHidden(value): self.fundingProgressContainerView.isHidden = value
      case let .fundingProgressBarViewHidden(value): self.fundingProgressBarView.isHidden = value
      case let .percentFundedTitleLabelText(value): self.fundingTitleLabel.text = value
      case let .locationLabelText(value): self.locationLabel.text = value
      case let .locationStackViewHidden(value): self.locationStackView.isHidden = value
      case let .metadataLabelText(value): self.metadataLabel.text = value
      case let .metadataTextColor(value): self.metadataLabel.textColor = value
      case let .metadataIconImageViewTintColor(value): self.metadataIconImageView.tintColor = value
      case let .metadataViewHidden(value): self.metadataView.isHidden = value
      case let .projectNameAndBlurbLabelText(value): self.projectNameAndBlurbLabel.attributedText = value
      case let .projectStateSubtitleLabelText(value): self.projectStateSubtitleLabel.text = value
      case let .projectStateTitleLabelColor(value): self.projectStateTitleLabel.textColor = value
      case let .projectStateTitleLabelText(value): self.projectStateTitleLabel.text = value
      case let .projectStateStackViewHidden(value): self.projectStateStackView.isHidden = value
      case let .projectStatsStackViewHidden(value): self.projectStatsStackView.isHidden = value
      case let .socialLabelText(value): self.socialLabel.text = value
      case let .socialStackViewHidden(value): self.socialStackView.isHidden = value
      case let .projectIsStaffPickLabelHidden(value): self.projectIsStaffPickView.isHidden = value
      case let .projectCategoryViewHidden(value): self.projectCategoryView.isHidden = value
      case let .projectCategoryStackViewHidden(value): self.projectCategoriesStackView.isHidden = value
      case let .cellAccessibilityLabel(value): self.accessibilityLabel = value
      case let .cellAccessibilityValue(value): self.accessibilityValue = value
      case let .projectCategoryName(name): self.projectCategoryView.configureWith(name: name, imageNameString: "icon--compass")
      case let .metadataIcon(icon): self.metadataIconImageView.image = icon
      case let .progressPercentage(progress):
        let anchorX = progress == 0 ? 0 : 0.5 / progress
        self.fundingProgressBarView.layer.anchorPoint = CGPoint(x: CGFloat(anchorX), y: 0.5)
        self.fundingProgressBarView.transform = CGAffineTransform(scaleX: CGFloat(progress), y: 1.0)
      case let .projectImageURL(url):
        self.projectImageView.af.cancelImageRequest()
        self.projectImageView.image = nil
        if let url { self.projectImageView.ksr_setImageWithURL(url) }
      case let .socialImageURL(url):
        self.socialAvatarImageView.af.cancelImageRequest()
        self.socialAvatarImageView.image = nil
        if let url { self.socialAvatarImageView.ksr_setRoundedImageWith(url) }
      case .projectStateIconHidden: break
      }
    }
  }

  internal func configureWith(value: DiscoveryProjectCellRowValue) {
    self.viewModel.configure(with: value)

    self.watchProjectViewModel.configure(with: (
      value.project,
      KSRAnalytics.PageContext.discovery,
      value.params
    ))
  }

  internal override func layoutSubviews() {
    super.layoutSubviews()

    // Resolve descendant geometry now, while UIKit owns this layout pass.
    self.contentView.layoutIfNeeded()
    self.cardView.layer.shadowPath = UIBezierPath(rect: self.cardView.bounds).cgPath
    self.metadataView.layer.shadowPath = UIBezierPath(rect: self.metadataView.bounds).cgPath
  }

  @objc fileprivate func saveButtonPressed(_: UIButton) {
    self.watchProjectViewModel.saveButtonTouched()
  }

  @objc fileprivate func saveButtonTapped(_ button: UIButton) {
    self.watchProjectViewModel.saveButtonTapped(selected: button.isSelected)
  }
}

// MARK: - Styles

@MainActor
private let locationStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> \.alignment .~ .center
    |> \.distribution .~ .fill
    |> \.spacing .~ Styles.grid(1)
}

@MainActor
private let locationLabelStyle: LabelStyle = { label in
  label
    |> \.font .~ .ksr_footnote()
    |> \.textColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.lineBreakMode .~ .byTruncatingTail
    |> \.numberOfLines .~ 1
}

@MainActor
private let locationImageViewStyle: ImageViewStyle = { imageView in
  imageView
    |> UIImageView.lens.image .~ Kickstarter_iOS.image(named: "location-icon")
    |> \.tintColor .~ LegacyColors.ksr_support_400.uiColor()
    |> \.contentMode .~ .scaleAspectFit
}
