import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol SettingsNewslettersCellDelegate: AnyObject {
  func didUpdate(user: User)
  func failedToUpdateUser(_ message: String)
  func shouldShowOptInAlert(_ newsletterName: String)
}

internal final class SettingsNewslettersCell: UITableViewCell, ValueCell {
  private let viewModel = SettingsNewsletterCellViewModel()

  @IBOutlet fileprivate var newslettersDescriptionLabel: UILabel!
  @IBOutlet fileprivate var newslettersLabel: UILabel!
  @IBOutlet fileprivate var newslettersSwitch: UISwitch!
  @IBOutlet fileprivate var separatorViews: [UIView]!

  public weak var delegate: SettingsNewslettersCellDelegate?

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.newslettersSwitch].compact()
    }
  }

  func configureWith(value: (newsletter: Newsletter, user: User)) {
    self.viewModel.configureWith(value: value)
    if let isOn = self.viewModel.switchIsOn { self.newslettersSwitch.isOn = isOn }

    _ = self.newslettersSwitch
      |> \.accessibilityLabel .~ value.newsletter.displayableName
      |> \.accessibilityHint .~ value.newsletter.displayableDescription

    _ = self.newslettersLabel
      |> \.text .~ value.newsletter.displayableName

    _ = self.newslettersDescriptionLabel
      |> \.text .~ value.newsletter.displayableDescription
  }

  override func bindStyles() {
    _ = self.contentView
      |> \.backgroundColor .~ LegacyColors.ksr_support_100.uiColor()

    _ = self.separatorViews
      ||> separatorStyle

    _ = self.newslettersDescriptionLabel
      |> settingsDescriptionLabelStyle

    _ = self.newslettersLabel
      |> settingsTitleLabelStyle

    _ = self.newslettersSwitch
      |> settingsSwitchStyle
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onOptIn = { [weak self] in self?.delegate?.shouldShowOptInAlert($0) }
    self.viewModel.onError = { [weak self] in self?.delegate?.failedToUpdateUser($0) }
    self.viewModel.onUserUpdated = { [weak self] in self?.delegate?.didUpdate(user: $0) }
  }

  @IBAction func newslettersSwitchTapped(_ sender: UISwitch) {
    self.viewModel.newslettersSwitchTapped(on: sender.isOn)
  }
}
