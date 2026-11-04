import KsApi

import Prelude
import Prelude_UIKit
import Observation
import UIKit

internal final class SettingsPrivacyRecommendationCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = SettingsRecommendationsCellViewModel()

  @IBOutlet fileprivate var recommendationsLabel: UILabel!
  @IBOutlet fileprivate var recommendationsSwitch: UISwitch!
  @IBOutlet fileprivate var separatorView: [UIView]!

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.recommendationsSwitch].compact()

      _ = self.recommendationsSwitch
        |> \.accessibilityLabel %~ { _ in Strings.Recommendations() }
    }
  }

  internal func configureWith(value: SettingsPrivacyStaticCellValue) {
    self.viewModel.configureWith(user: value.user)
    if let isOn = self.viewModel.recommendationsOn { self.recommendationsSwitch.isOn = isOn }

    _ = self.recommendationsSwitch
      |> \.accessibilityHint .~ value.cellType.description
  }

  internal override func bindStyles() {
    super.bindStyles()
    _ = self
      |> baseTableViewCellStyle()
      |> UITableViewCell.lens.contentView.layoutMargins %~~ { _, cell in
        cell.traitCollection.isRegularRegular
          ? .init(topBottom: Styles.grid(2), leftRight: Styles.grid(20))
          : .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))
      }

    _ = self.separatorView
      ||> settingsSeparatorStyle

    _ = self.recommendationsSwitch
      |> settingsSwitchStyle

    _ = self.recommendationsLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.text %~ { _ in Strings.Recommendations() }
  }

  internal override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onSaved = {
      NotificationCenter.default.post(name: .ksr_recommendationsSettingChanged, object: nil)
    }
    self.observeRecommendations()
  }

  private func observeRecommendations() {
    withObservationTracking {
      if let isOn = self.viewModel.recommendationsOn { self.recommendationsSwitch.isOn = isOn }
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeRecommendations() }
    }
  }

  @IBAction func recommendationsSwitch(_ recommendationsSwitch: UISwitch) {
    self.viewModel.recommendationsTapped(on: recommendationsSwitch.isOn)
  }
}
