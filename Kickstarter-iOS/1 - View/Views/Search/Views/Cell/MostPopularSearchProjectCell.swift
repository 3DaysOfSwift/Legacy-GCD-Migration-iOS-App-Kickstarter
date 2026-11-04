import KDS
import KsApi

import Prelude
import Prelude_UIKit
import UIKit

internal final class MostPopularSearchProjectCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = MostPopularSearchProjectCellViewModel()

  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var metadataBackgroundView: UIView!
  @IBOutlet fileprivate var metadataIconImageView: UIImageView!
  @IBOutlet fileprivate var metadataLabel: UILabel!
  @IBOutlet fileprivate var percentFundedLabel: UILabel!
  @IBOutlet fileprivate var progressBarView: UIView!
  @IBOutlet fileprivate var progressStaticView: UIView!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var projectInfoOverlayView: UIView!
  @IBOutlet fileprivate var projectInfoStackView: UIStackView!
  @IBOutlet fileprivate var projectNameLabel: UILabel!
  @IBOutlet fileprivate var separateView: UIView!
  @IBOutlet fileprivate var statsStackView: UIStackView!

  internal func configureWith(value: any BackerDashboardProjectCellViewModel.ProjectCellModel) {
    self.viewModel.configureWith(project: value)
    self.renderProject()
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> MostPopularSearchProjectCell.lens.backgroundColor .~ .clear
      |> MostPopularSearchProjectCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(2), leftRight: Styles.grid(20))
          : .init(topBottom: Styles.grid(2), leftRight: Styles.grid(2))
      }

    _ = self.cardView
      |> cardStyle()

    _ = self.statsStackView
      |> UIStackView.lens.spacing .~ Styles.grid(6)

    _ = self.projectImageView
      |> UIImageView.lens.contentMode .~ .scaleAspectFill
      |> UIImageView.lens.clipsToBounds .~ true

    _ = self.projectInfoOverlayView
      |> UIView.lens.backgroundColor .~ Colors.Background.Surface.primary.uiColor(opacity: 0.95)
      |> UIView.lens.layoutMargins %~~ { _, label in
        label.traitCollection.isRegularRegular
          ? .init(all: Styles.grid(6))
          : .init(all: Styles.grid(2))
      }

    _ = self.metadataBackgroundView
      |> UIView.lens.layer.borderColor .~ LegacyColors.ksr_white.uiColor().cgColor
      |> UIView.lens.layer.borderWidth .~ 1.0

    _ = self.metadataLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_white.uiColor()
      |> UILabel.lens.font .~ .ksr_headline(size: 12)

    _ = self.metadataIconImageView
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.percentFundedLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 14)

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.projectInfoStackView
      |> UIStackView.lens.spacing .~ Styles.grid(2)

    _ = self.projectNameLabel
      |> UILabel.lens.font %~~ { _, label in
        label.traitCollection.isRegularRegular
          ? UIFont.ksr_title2()
          : UIFont.ksr_title1(size: 18)
      }
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.numberOfLines .~ 2
      |> UILabel.lens.lineBreakMode .~ .byTruncatingTail

    _ = self.separateView
      |> separatorStyle

    _ = self.progressStaticView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_black.uiColor()
      |> UIView.lens.alpha .~ 0.15
  }

  private func renderProject() {
    let model = self.viewModel
    self.metadataBackgroundView.backgroundColor = model.progressBarColor
    self.metadataLabel.text = model.metadataText
    self.percentFundedLabel.attributedText = model.percentFundedText
    self.progressBarView.backgroundColor = model.progressBarColor
    self.projectImageView.af.cancelImageRequest()
    self.projectImageView.image = nil
    if let url = model.projectImageUrl { self.projectImageView.ksr_setImageWithURL(url) }
    self.projectNameLabel.attributedText = model.projectName
    self.statsStackView.isHidden = model.prelaunchProject
    self.progressBarView.isHidden = model.prelaunchProject
    self.metadataIconImageView.isHidden = model.prelaunchProject
    let progress = model.progress
    let anchorX = progress == 0 ? 0 : 0.5 / progress
    self.progressBarView.layer.anchorPoint = CGPoint(x: CGFloat(max(anchorX, 0.5)), y: 0.5)
    self.progressBarView.transform = CGAffineTransform(scaleX: CGFloat(min(progress, 1.0)), y: 1.0)
  }
}
