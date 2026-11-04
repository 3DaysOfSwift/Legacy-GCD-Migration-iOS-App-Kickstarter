import AlamofireImage
import CoreImage
import KDS
import KsApi

import Prelude
import UIKit

internal final class ActivityProjectStatusCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = ActivityProjectStatusViewModel()

  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var containerView: UIView!
  @IBOutlet fileprivate var fundingProgressBarView: UIView!
  @IBOutlet fileprivate var fundingProgressContainerView: UIView!
  @IBOutlet fileprivate var fundingProgressLabel: UILabel!
  @IBOutlet fileprivate var metadataBackgroundView: UIView!
  @IBOutlet fileprivate var metadataLabel: UILabel!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var projectNameLabel: UILabel!
  @IBOutlet fileprivate var textBackgroundView: UIView!

  internal func configureWith(value: Activity) {
    self.viewModel.configureWith(activity: value)
    let model = self.viewModel
    if let name = model.projectName { self.projectNameLabel.text = name }
    self.metadataBackgroundView.backgroundColor = model.metadataBackgroundColor
    self.metadataLabel.text = model.metadataText
    self.fundingProgressBarView.backgroundColor = model.fundingBarColor
    self.fundingProgressLabel.attributedText = model.percentFundedText
    if value.project != nil {
      self.projectImageView.af.cancelImageRequest()
      self.projectImageView.image = nil
      if let url = model.projectImageURL { self.projectImageView.ksr_setImageWithURL(url) }
    }
    if let progress = model.fundingProgressPercentage {
      let anchorX = progress == 0 ? 0 : 0.5 / progress
      self.fundingProgressBarView.layer.anchorPoint = CGPoint(x: CGFloat(anchorX), y: 0.5)
      self.fundingProgressBarView.transform = CGAffineTransform(scaleX: CGFloat(progress), y: 1)
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> UITableViewCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(
            top: Styles.gridHalf(7), left: Styles.grid(30), bottom: Styles.grid(2),
            right: Styles.grid(30)
          )
          : .init(
            top: Styles.gridHalf(6), left: Styles.grid(2), bottom: Styles.gridHalf(3),
            right: Styles.grid(2)
          )
      }

    self.cardView.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.containerView
      |> cardStyle()

    _ = self.fundingProgressContainerView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_300.uiColor()

    _ = self.metadataBackgroundView
      |> UIView.lens.layer.borderColor .~ LegacyColors.ksr_white.uiColor().cgColor
      |> UIView.lens.layer.borderWidth .~ 1.0
      |> UIView.lens.layoutMargins .~ .init(all: Styles.grid(1))

    _ = self.metadataLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 12)
      |> UILabel.lens.textColor .~ LegacyColors.ksr_white.uiColor()

    _ = self.projectNameLabel
      |> UILabel.lens.font .~ .ksr_title1(size: 18)
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.textBackgroundView
      |> UIView.lens.alpha .~ 0.96
      |> UIView.lens.layoutMargins .~ .init(all: Styles.grid(2))
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
  }
}
