import KDS

import Prelude
import UIKit

internal final class DiscoveryExpandableRowCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = DiscoveryExpandableRowCellViewModel()

  @IBOutlet fileprivate var filterTitleLabel: UILabel!
  @IBOutlet fileprivate var projectsCountLabel: UILabel!

  internal func configureWith(value: (row: ExpandableRow, categoryId: Int?)) {
    self.viewModel.configureWith(row: value.0, categoryId: value.1)
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> discoveryFilterRowMarginStyle
      |> UITableViewCell.lens.accessibilityTraits .~ UIAccessibilityTraits.button

    _ = self.projectsCountLabel
      |> UILabel.lens.isAccessibilityElement .~ false
      |> UILabel.lens.textColor .~ LegacyColors.ksr_create_700.uiColor()
      |> UILabel.lens.font %~~ { _, label in
        label.traitCollection.isRegularRegular
          ? UIFont.ksr_headline(size: 13)
          : UIFont.ksr_headline(size: 11)
      }
  }

  internal func willDisplay() {
    guard let display = self.viewModel.willDisplay() else { return }
    self.accessibilityLabel = display.accessibilityLabel
    self.accessibilityHint = display.accessibilityHint
    self.filterTitleLabel.text = display.title
    self.projectsCountLabel.text = display.count
    self.projectsCountLabel.isHidden = display.countHidden
    self.projectsCountLabel.alpha = display.countAlpha
    _ = self.filterTitleLabel
      |> discoveryFilterLabelStyle(categoryId: display.categoryId, isSelected: display.row.isExpanded)
      |> discoveryFilterLabelFontStyle(isSelected: display.row.isExpanded)
  }
}
