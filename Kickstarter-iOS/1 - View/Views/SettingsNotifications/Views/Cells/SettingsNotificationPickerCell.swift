import KDS
import KsApi

import Prelude
import UIKit

final class SettingsNotificationPickerCell: UITableViewCell, NibLoading, ValueCell {
  @IBOutlet fileprivate var titleLabel: UILabel!
  @IBOutlet fileprivate var currentEmailFrequencyLabel: UILabel!
  @IBOutlet fileprivate var separatorView: UIView!

  private let viewModel = SettingsNotificationPickerViewModel()

  func configureWith(value: SettingsNotificationCellValue) {
    self.viewModel.configure(with: value)
    if let text = self.viewModel.frequencyValueText { self.currentEmailFrequencyLabel.text = text }

    _ = self
      |> \.accessibilityTraits .~ value.cellType.accessibilityTraits

    _ = self.titleLabel
      |> UILabel.lens.text .~ value.cellType.title
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.titleLabel
      |> settingsTitleLabelStyle

    _ = self.currentEmailFrequencyLabel
      |> UILabel.lens.font .~ .ksr_body()
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.separatorView
      |> separatorStyle
  }

}
