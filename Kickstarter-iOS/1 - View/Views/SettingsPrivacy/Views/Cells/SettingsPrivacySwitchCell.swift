import KDS

import Prelude
import UIKit

@MainActor
protocol SettingsPrivacySwitchCellDelegate: AnyObject {
  func privacySettingsSwitchCell(
    _ cell: SettingsPrivacySwitchCell,
    didTogglePrivacySwitch on: Bool
  )
}

final class SettingsPrivacySwitchCell: UITableViewCell, ValueCell, NibLoading {
  @IBOutlet fileprivate var primaryDescriptionLabel: UILabel!
  @IBOutlet fileprivate var titleLabel: UILabel!
  @IBOutlet fileprivate var secondaryDescriptionLabel: UILabel!
  @IBOutlet fileprivate var switchButton: UISwitch!
  @IBOutlet fileprivate var separatorViews: [UIView]!

  private let viewModel = SettingsPrivacySwitchCellViewModel()

  weak var delegate: SettingsPrivacySwitchCellDelegate?

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.switchButton].compact()
    }
  }

  func configureWith(value: SettingsPrivacySwitchCellValue) {
    self.viewModel.configure(with: value.user)
    self.switchButton.isOn = self.viewModel.privacySwitchIsOn

    _ = self.titleLabel
      |> \.text .~ value.cellType.title

    _ = self.primaryDescriptionLabel
      |> \.text .~ value.cellType.primaryDescription

    _ = self.secondaryDescriptionLabel
      |> \.text .~ value.cellType.secondaryDescription

    _ = self.switchButton
      |> \.accessibilityLabel .~ value.cellType.title
      |> \.accessibilityHint .~ "\(value.cellType.primaryDescription), \(value.cellType.secondaryDescription)"
  }

  override func bindStyles() {
    super.bindViewModel()

    _ = self
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_100.uiColor()

    _ = self.titleLabel
      |> settingsTitleLabelStyle

    _ = self.primaryDescriptionLabel
      |> settingsDescriptionLabelStyle

    _ = self.secondaryDescriptionLabel
      |> settingsDescriptionLabelStyle

    _ = self.switchButton
      |> settingsSwitchStyle

    _ = self.separatorViews
      ||> settingsSeparatorStyle
  }

  @IBAction func switchToggled(_ sender: UISwitch) {
    self.delegate?.privacySettingsSwitchCell(self, didTogglePrivacySwitch: sender.isOn)
  }
}
