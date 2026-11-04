import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol SettingsNewslettersTopCellDelegate: AnyObject {
  func didUpdateAllNewsletters(user: User)
  func failedToUpdateAllNewsletters(_ message: String)
}

internal final class SettingsNewslettersTopCell: UITableViewCell, ValueCell {
  private let viewModel = SettingsNewsletterCellViewModel()

  @IBOutlet fileprivate var descriptionLabel: UILabel!
  @IBOutlet fileprivate var newsletterSwitch: UISwitch!
  @IBOutlet fileprivate var titleLabel: UILabel!

  @IBOutlet fileprivate var separatorViews: [UIView]!

  public weak var delegate: SettingsNewslettersTopCellDelegate?

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.newsletterSwitch].compact()

      _ = self.descriptionLabel
        |> \.text %~ { _ in Strings.Stay_up_to_date_newsletter() }

      _ = self.newsletterSwitch
        |> \.accessibilityLabel %~ { _ in Strings.profile_settings_newsletter_subscribe_all() }
        |> \.accessibilityHint %~ { _ in Strings.Stay_up_to_date_newsletter() }

      _ = self.titleLabel
        |> \.text %~ { _ in Strings.profile_settings_newsletter_subscribe_all() }
    }
  }

  func configureWith(value: User) {
    self.viewModel.configureWith(value: value)
    if let isOn = self.viewModel.subscribeToAllSwitchIsOn { self.newsletterSwitch.isOn = isOn }
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.contentView
      |> \.backgroundColor .~ LegacyColors.ksr_support_100.uiColor()

    _ = self.descriptionLabel
      |> settingsDescriptionLabelStyle

    _ = self.newsletterSwitch
      |> settingsSwitchStyle

    _ = self.separatorViews
      ||> separatorStyle

    _ = self.titleLabel
      |> settingsTitleLabelStyle
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onUserUpdated = { [weak self] in self?.delegate?.didUpdateAllNewsletters(user: $0) }
    self.viewModel.onError = { [weak self] in self?.delegate?.failedToUpdateAllNewsletters($0) }
  }

  @IBAction func newsletterSwitchTapped(_ sender: UISwitch) {
    self.viewModel.allNewslettersSwitchTapped(on: sender.isOn)
  }
}
