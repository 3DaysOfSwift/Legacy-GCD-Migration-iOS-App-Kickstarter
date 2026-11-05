import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol ProjectPamphletMainCellDelegate: VideoViewControllerDelegate {
  func projectPamphletMainCell(_ cell: ProjectPamphletMainCell, addChildController child: UIViewController)
  func projectPamphletMainCell(
    _ cell: ProjectPamphletMainCell,
    goToCreatorForProject project: any ProjectPamphletMainCellConfiguration
  )
  func projectPamphletMainCellGoToProjectNotice(_ cell: ProjectPamphletMainCell)
}

internal final class ProjectPamphletMainCell: UITableViewCell, ValueCell {
  internal weak var delegate: ProjectPamphletMainCellDelegate? {
    didSet {
      self.viewModel.delegateDidSet()
    }
  }

  fileprivate let viewModel = ProjectPamphletMainCellViewModel()

  fileprivate weak var videoController: VideoViewController?

  @IBOutlet fileprivate var backersSubtitleLabel: UILabel!
  @IBOutlet fileprivate var backersTitleLabel: UILabel!
  @IBOutlet fileprivate var blurbAndOverviewStackview: UIStackView!
  @IBOutlet fileprivate var blurbStackView: UIStackView!
  @IBOutlet fileprivate var categoryStackView: UIStackView!
  @IBOutlet fileprivate var categoryAndLocationStackView: UIStackView!
  @IBOutlet fileprivate var categoryIconImageView: UIImageView!
  @IBOutlet fileprivate var categoryNameLabel: UILabel!
  @IBOutlet fileprivate var contentStackView: UIStackView!
  @IBOutlet fileprivate var conversionLabel: UILabel!
  @IBOutlet fileprivate(set) var creatorButton: UIButton! // Made visible so it can be used as a popover target
  @IBOutlet fileprivate var creatorImageView: UIImageView!
  @IBOutlet fileprivate var creatorLabel: UILabel!
  @IBOutlet fileprivate var creatorStackView: UIStackView!
  @IBOutlet fileprivate var deadlineSubtitleLabel: UILabel!
  @IBOutlet fileprivate var deadlineTitleLabel: UILabel!
  @IBOutlet fileprivate var fundingProgressBarView: UIView!
  @IBOutlet fileprivate var fundingProgressContainerView: UIView!
  @IBOutlet fileprivate var locationImageView: UIImageView!
  @IBOutlet fileprivate var locationNameLabel: UILabel!
  @IBOutlet fileprivate var locationStackView: UIStackView!
  @IBOutlet fileprivate var pledgeSubtitleLabel: UILabel!
  @IBOutlet fileprivate var pledgedTitleLabel: UILabel!
  @IBOutlet fileprivate var projectBlurbLabel: UILabel!
  @IBOutlet fileprivate var projectImageContainerView: UIView!
  @IBOutlet fileprivate var projectNameAndCreatorStackView: UIStackView!
  @IBOutlet fileprivate var projectNameLabel: UILabel!
  @IBOutlet fileprivate var progressBarAndStatsStackView: UIStackView!
  @IBOutlet fileprivate var stateLabel: UILabel!
  @IBOutlet fileprivate var statsStackView: UIStackView!
  @IBOutlet fileprivate var backingContainerView: UIView!
  @IBOutlet fileprivate var backingContainerViewLeadingConstraint: NSLayoutConstraint!
  @IBOutlet fileprivate var backingLabel: UILabel!

  private var alertBanner = AlertBanner(frame: CGRect.zero)

  internal override func awakeFromNib() {
    super.awakeFromNib()

    // UIKit loads this cell on the main thread. NSObject declares awakeFromNib
    // nonisolated, so establish its synchronous UI boundary before touching state.
    MainActor.assumeIsolated {
      self.creatorButton.addTarget(
        self,
        action: #selector(self.creatorButtonTapped),
        for: .touchUpInside
      )

      self.alertBanner.configureWith(
        title: Strings.project_project_notices_header(),
        subtitle: Strings.project_project_notices_notice_intro(),
        buttonTitle: Strings.project_project_notices_notice_cta()
      ) { [weak self] in
        self?.alertBannerLearnMoreTapped()
      }
      self.contentStackView.insertArrangedSubview(self.alertBanner, at: 1)

      self.viewModel.awakeFromNib()
    }
  }

  internal func configureWith(value: ProjectPamphletMainCellData) {
    self.viewModel.configureWith(value: value)
  }

  internal func scrollContentOffset(_ offset: CGFloat) {
    let height = self.projectImageContainerView.bounds.height
    let translation = offset / 2

    let scale: CGFloat
    if offset < 0 {
      scale = (height + abs(offset)) / height
    } else {
      scale = max(1, 1 - 0.5 * offset / height)
    }

    self.projectImageContainerView.transform = CGAffineTransform(
      a: scale, b: 0,
      c: 0, d: scale,
      tx: 0, ty: translation
    )
  }

  internal override func bindStyles() {
    super.bindStyles()

    // maintain vertical spacing in one place so that it's consistent in nested stackviews
    let verticalSpacing = Styles.grid(3)

    _ = self
      |> baseTableViewCellStyle()
      |> UITableViewCell.lens.clipsToBounds .~ true
      |> UITableViewCell.lens.accessibilityElements .~ self.subviews

    self.contentStackView.backgroundColor = LegacyColors.ksr_white.uiColor()

    let subtitleLabelStyling = UILabel.lens.font .~ .ksr_caption1(size: 13)
      <> UILabel.lens.numberOfLines .~ 1
      <> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = [self.backersSubtitleLabel, self.deadlineSubtitleLabel]
      ||> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      ||> subtitleLabelStyling

    _ = self.pledgeSubtitleLabel |> subtitleLabelStyling

    _ = [self.backersTitleLabel, self.deadlineTitleLabel, self.pledgedTitleLabel]
      ||> UILabel.lens.font .~ .ksr_headline(size: 13)
      ||> UILabel.lens.numberOfLines .~ 1
      ||> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.categoryStackView
      |> UIStackView.lens.spacing .~ Styles.grid(1)

    _ = self.categoryIconImageView
      |> UIImageView.lens.contentMode .~ .scaleAspectFit
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UIImageView.lens.image .~ Kickstarter_iOS.image(named: "category-icon")
      |> UIImageView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.categoryNameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_body(size: 12)
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    let isIpad = self.traitCollection.isRegularRegular == true
    let leftRightInsetValue: CGFloat = isIpad ? Styles.grid(16) : Styles.grid(4)

    _ = self.contentStackView
      |> UIStackView.lens.layoutMargins %~~ { _, _ in
        isIpad
          ? .init(topBottom: Styles.grid(6), leftRight: leftRightInsetValue)
          : .init(
            top: Styles.grid(4),
            left: leftRightInsetValue,
            bottom: Styles.grid(3),
            right: leftRightInsetValue
          )
      }
      |> UIStackView.lens.isLayoutMarginsRelativeArrangement .~ true
      |> UIStackView.lens.spacing .~ verticalSpacing

    _ = (self.projectNameAndCreatorStackView, self.contentStackView)
      |> ksr_setCustomSpacing(Styles.grid(4))

    _ = self.blurbAndOverviewStackview
      |> \.spacing .~ verticalSpacing

    _ = self.blurbStackView
      |> UIStackView.lens.layoutMargins .~ UIEdgeInsets(
        top: 0,
        left: 0,
        bottom: verticalSpacing, // Double spacing below blurb.
        right: 0
      )
      |> UIStackView.lens.isLayoutMarginsRelativeArrangement .~ true

    _ = self.conversionLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_caption2().italicized
      |> UILabel.lens.numberOfLines .~ 2

    _ = self.creatorImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.creatorImageView
      |> UIImageView.lens.clipsToBounds .~ true
      |> UIImageView.lens.contentMode .~ .scaleAspectFill

    _ = self.creatorLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ .ksr_headline(size: 13)
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.creatorStackView
      |> UIStackView.lens.alignment .~ .center
      |> UIStackView.lens.spacing .~ Styles.grid(1)

    _ = self.fundingProgressContainerView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_300.uiColor()

    _ = self.locationImageView
      |> UIImageView.lens.contentMode .~ .scaleAspectFit
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UIImageView.lens.image .~ Kickstarter_iOS.image(named: "location-icon")
      |> UIImageView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.locationNameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_body(size: 12)
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.locationStackView
      |> UIStackView.lens.spacing .~ Styles.grid(1)

    _ = self.projectBlurbLabel
      |> UILabel.lens.font %~~ { _, _ in
        isIpad
          ? .ksr_body(size: 18)
          : .ksr_body(size: 15)
      }
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.numberOfLines .~ 0
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.projectNameAndCreatorStackView
      |> UIStackView.lens.spacing .~ (verticalSpacing / 2)

    _ = self.projectNameLabel
      |> UILabel.lens.font %~~ { _, _ in
        isIpad
          ? .ksr_title3(size: 28)
          : .ksr_title3(size: 20)
      }
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.numberOfLines .~ 0
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.progressBarAndStatsStackView
      |> UIStackView.lens.spacing .~ verticalSpacing

    _ = self.stateLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 12)
      |> UILabel.lens.numberOfLines .~ 2

    _ = self.statsStackView
      |> UIStackView.lens.isAccessibilityElement .~ true
      |> UIStackView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.backingContainerViewLeadingConstraint
      |> \.constant .~ leftRightInsetValue

    _ = self.backingContainerView
      |> roundedStyle(cornerRadius: 2)
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_create_700.uiColor()
      |> UIView.lens.layoutMargins .~ .init(topBottom: Styles.grid(1), leftRight: Styles.gridHalf(3))

    _ = self.backingLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_white.uiColor()
      |> UILabel.lens.font .~ .ksr_headline(size: 12)
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .backersSubtitleLabelText(value): self.backersSubtitleLabel.text = value
      case let .backersTitleLabelText(value): self.backersTitleLabel.text = value
      case let .projectUnsuccessfulLabelTextColor(value): self.backersTitleLabel.textColor = value; self.deadlineTitleLabel.textColor = value
      case let .categoryNameLabelText(value): self.categoryNameLabel.text = value
      case let .conversionLabelHidden(value): self.conversionLabel.isHidden = value
      case let .conversionLabelText(value): self.conversionLabel.text = value
      case let .creatorLabelText(value): self.creatorButton.accessibilityLabel = value; self.creatorLabel.text = value
      case let .deadlineSubtitleLabelText(value): self.deadlineSubtitleLabel.text = value
      case let .deadlineTitleLabelText(value): self.deadlineTitleLabel.text = value
      case let .fundingProgressBarViewBackgroundColor(value): self.fundingProgressBarView.backgroundColor = value
      case let .locationNameLabelText(value): self.locationNameLabel.text = value
      case let .locationStackViewHidden(value): self.locationStackView.isHidden = value
      case let .pledgedSubtitleLabelText(value): self.pledgeSubtitleLabel.text = value
      case let .pledgedTitleLabelTextColor(value): self.pledgeSubtitleLabel.textColor = value; self.pledgedTitleLabel.textColor = value
      case let .pledgedTitleLabelText(value): self.pledgedTitleLabel.text = value
      case let .projectBlurbLabelText(value): self.projectBlurbLabel.text = value
      case let .projectNameLabelText(value): self.projectNameLabel.text = value
      case let .projectStateLabelText(value): self.stateLabel.text = value
      case let .projectStateLabelTextColor(value): self.stateLabel.textColor = value
      case let .stateLabelHidden(value): self.stateLabel.isHidden = value
      case let .statsStackViewAccessibilityLabel(value): self.statsStackView.accessibilityLabel = value
      case let .backingLabelHidden(value): self.backingContainerView.isHidden = value
      case let .isPrelaunchProject(value): self.progressBarAndStatsStackView.isHidden = value
      case let .prelaunchProjectBackingText(value): self.backingLabel.text = value
      case let .projectNoticeBannerHidden(value): self.alertBanner.isHidden = value
      case let .configureVideoPlayerController(project): self.configureVideoPlayerController(forProject: project)
      case let .creatorImageUrl(url):
        self.creatorImageView.image = nil
        if let url { self.creatorImageView.af.setImage(withURL: url) }
      case let .notifyDelegateToGoToCreator(project): self.delegate?.projectPamphletMainCell(self, goToCreatorForProject: project)
      case .notifyDelegateToGoToProjectNotice: self.delegate?.projectPamphletMainCellGoToProjectNotice(self)
      case let .opacityForViews(alpha):
        UIView.animate(withDuration: alpha == 0 ? 0 : 0.3, delay: 0, options: .curveEaseOut) {
          self.creatorStackView.alpha = alpha
          self.statsStackView.alpha = alpha
          self.blurbAndOverviewStackview.alpha = alpha
        }
      case let .progressPercentage(progress):
        let anchorX = progress == 0 ? 0 : 0.5 / progress
        self.fundingProgressBarView.layer.anchorPoint = CGPoint(x: CGFloat(anchorX), y: 0.5)
        self.fundingProgressBarView.transform = CGAffineTransform(scaleX: CGFloat(progress), y: 1)
      case .projectImageUrl: break
      }
    }
  }

  fileprivate func configureVideoPlayerController(
    forProject project: any ProjectPamphletMainCellConfiguration
  ) {
    let vc = VideoViewController.configuredWith(project: project)
    vc.delegate = self
    vc.view.translatesAutoresizingMaskIntoConstraints = false
    self.projectImageContainerView.addSubview(vc.view)

    NSLayoutConstraint.activate([
      vc.view.topAnchor.constraint(equalTo: self.projectImageContainerView.topAnchor),
      vc.view.leadingAnchor.constraint(equalTo: self.projectImageContainerView.leadingAnchor),
      vc.view.bottomAnchor.constraint(equalTo: self.projectImageContainerView.bottomAnchor),
      vc.view.trailingAnchor.constraint(equalTo: self.projectImageContainerView.trailingAnchor)
    ])

    self.delegate?.projectPamphletMainCell(self, addChildController: vc)
    self.videoController = vc
    self.videoController?.playbackDelegate = vc
  }

  private func alertBannerLearnMoreTapped() {
    self.viewModel.projectNoticeLearnMoreTapped()
  }

  @objc fileprivate func creatorButtonTapped() {
    self.viewModel.creatorButtonTapped()
  }
}

extension ProjectPamphletMainCell: VideoViewControllerDelegate {
  internal func videoViewControllerDidFinish(_ controller: VideoViewController) {
    self.delegate?.videoViewControllerDidFinish(controller)
    self.viewModel.videoDidFinish()
  }

  internal func videoViewControllerDidStart(_ controller: VideoViewController) {
    self.delegate?.videoViewControllerDidStart(controller)
    self.viewModel.videoDidStart()
  }
}

extension ProjectPamphletMainCell: AudioVideoViewControllerPlaybackDelegate {
  func pauseAudioVideoPlayback() {
    self.videoController?.playbackDelegate?.pauseAudioVideoPlayback()
  }
}
