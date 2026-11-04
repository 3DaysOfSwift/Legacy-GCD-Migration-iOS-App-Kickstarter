import KDS
import KsApi

import Prelude
import UIKit

internal final class ProjectPamphletSubpageCell: UITableViewCell, ValueCell {
  @IBOutlet private var countContainerView: UIView!
  @IBOutlet private var countLabel: UILabel!
  @IBOutlet private var rootStackView: UIStackView!
  @IBOutlet private var separatorView: UIView!
  @IBOutlet private var subpageLabel: UILabel!
  @IBOutlet private var topSeparatorView: UIView!

  private let viewModel = ProjectPamphletSubpageCellViewModel()

  internal func configureWith(value subpage: ProjectPamphletSubpage) {
    self.viewModel.configureWith(subpage: subpage)
    self.topSeparatorView.isHidden = self.viewModel.topSeparatorViewHidden
    self.separatorView.isHidden = self.viewModel.separatorViewHidden
    if subpage.isComments || subpage.isUpdates {
      self.countLabel.text = self.viewModel.countLabelText
      self.countLabel.textColor = LegacyColors.ksr_support_700.uiColor()
      self.countLabel.backgroundColor = LegacyColors.ksr_support_100.uiColor()
      self.countContainerView.backgroundColor = LegacyColors.ksr_support_100.uiColor()
      self.countContainerView.layer.borderColor = UIColor.clear.cgColor
      self.subpageLabel.text = self.viewModel.labelText
      self.subpageLabel.textColor = LegacyColors.ksr_support_700.uiColor()
    }
    self.setNeedsLayout()
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()
      |> ProjectPamphletSubpageCell.lens.accessibilityTraits .~ UIAccessibilityTraits.button
      |> ProjectPamphletSubpageCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.gridHalf(5), leftRight: Styles.grid(16))
          : .init(topBottom: Styles.gridHalf(5), leftRight: Styles.gridHalf(7))
      }

    _ = self.countContainerView
      |> UIView.lens.layoutMargins .~ .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))
      |> UIView.lens.layer.borderWidth .~ 1

    _ = self.countLabel
      |> UILabel.lens.font .~ .ksr_headline(size: 13)
      |> UIView.lens.contentHuggingPriority(for: .horizontal) .~ UILayoutPriority.required
      |> UIView.lens.contentCompressionResistancePriority(for: .horizontal) .~ UILayoutPriority.required

    _ = self.rootStackView
      |> UIStackView.lens.spacing .~ Styles.grid(1)
      |> UIStackView.lens.alignment .~ .center
      |> UIStackView.lens.distribution .~ .fill

    _ = [self.separatorView, self.topSeparatorView]
      ||> separatorStyle

    _ = self.subpageLabel
      |> UILabel.lens.numberOfLines .~ 2
      |> UILabel.lens.font .~ .ksr_body(size: 14)
      |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
      |> UIView.lens.contentHuggingPriority(for: .horizontal) .~ UILayoutPriority.defaultLow
      |> UIView.lens.contentCompressionResistancePriority(for: .horizontal) .~ UILayoutPriority.defaultLow

    self.setNeedsLayout()
  }

}
