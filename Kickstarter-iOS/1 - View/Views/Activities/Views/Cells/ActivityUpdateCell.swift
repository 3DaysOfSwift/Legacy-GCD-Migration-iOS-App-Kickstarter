import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol ActivityUpdateCellDelegate: AnyObject {
  /// Call with the activity value when navigating to the activity's project.
  func activityUpdateCellTappedProjectImage(activity: Activity)
}

internal final class ActivityUpdateCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = ActivityUpdateViewModel()
  internal weak var delegate: ActivityUpdateCellDelegate?

  @IBOutlet fileprivate var bodyLabel: UILabel!
  @IBOutlet fileprivate var cardView: UIView!
  @IBOutlet fileprivate var containerView: UIView!
  @IBOutlet fileprivate var projectImageButton: UIButton!
  @IBOutlet fileprivate var projectImageView: UIImageView!
  @IBOutlet fileprivate var projectNameLabel: UILabel!
  @IBOutlet fileprivate var titleLabel: UILabel!
  @IBOutlet fileprivate var updateSequenceLabel: UILabel!

  internal func configureWith(value: Activity) {
    self.viewModel.configureWith(activity: value)
    if let text = self.viewModel.cellAccessibilityLabel { self.accessibilityLabel = text }
    if let name = self.viewModel.projectName {
      self.projectNameLabel.text = name
      self.projectImageButton.accessibilityLabel = name
    }
    self.projectImageButton.accessibilityHint = Strings.dashboard_tout_accessibility_hint_opens_project()
    self.updateSequenceLabel.attributedText = self.viewModel.sequenceTitle
    if let title = self.viewModel.title { self.titleLabel.text = title }
    if let body = self.viewModel.body { self.bodyLabel.text = body }
    if value.project != nil {
      self.projectImageView.af.cancelImageRequest()
      self.projectImageView.image = nil
      if let url = self.viewModel.projectImageURL { self.projectImageView.af.setImage(withURL: url) }
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> feedTableViewCellStyle
      |> UITableViewCell.lens.accessibilityTraits .~ UIAccessibilityTraits.button

    _ = self.cardView
      |> cardStyle()

    _ = self.containerView
      |> UIView.lens.layoutMargins .~ .init(all: Styles.grid(2))

    self.containerView.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.bodyLabel
      |> UILabel.lens.font .~ .ksr_subhead()
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.projectImageView
      |> ignoresInvertColorsImageViewStyle

    _ = self.projectNameLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 14)
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.titleLabel
      |> UILabel.lens.font .~ .ksr_title1(size: 22)
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
  }

  @IBAction internal func tappedProjectImage() {
    if let activity = self.viewModel.activity {
      self.delegate?.activityUpdateCellTappedProjectImage(activity: activity)
    }
  }
}
