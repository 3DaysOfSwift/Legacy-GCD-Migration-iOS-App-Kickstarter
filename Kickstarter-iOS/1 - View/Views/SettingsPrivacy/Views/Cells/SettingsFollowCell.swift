import KsApi

import Prelude
import Prelude_UIKit
import UIKit

@MainActor
internal protocol SettingsFollowCellDelegate: AnyObject {
  /// Called when follow switch is switched off
  func settingsFollowCellDidDisableFollowing(_ cell: SettingsFollowCell)
  func settingsFollowCellDidUpdate(user: User)
}

internal final class SettingsFollowCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = SettingsFollowCellViewModel()
  internal weak var delegate: SettingsFollowCellDelegate?

  @IBOutlet fileprivate var followingLabel: UILabel!
  @IBOutlet fileprivate var followStackView: UIStackView!
  @IBOutlet fileprivate var followingSwitch: UISwitch!
  @IBOutlet fileprivate var separatorView: [UIView]!

  override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.followingSwitch].compact()

      _ = self.followingSwitch
        |> \.accessibilityLabel %~ { _ in Strings.Following() }
    }
  }

  internal func configureWith(value: SettingsPrivacyStaticCellValue) {
    self.viewModel.configureWith(user: value.user)
    if value.user.social != nil, let isOn = self.viewModel.followingPrivacyOn {
      self.followingSwitch.isOn = isOn
    }

    _ = self.followingSwitch
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

    _ = self.followingSwitch
      |> settingsSwitchStyle

    _ = self.followingLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.text %~ { _ in Strings.Following() }
      |> UILabel.lens.numberOfLines .~ 1
  }

  func toggleOn(animated: Bool = true) {
    self.followingSwitch.setOn(true, animated: animated)
  }

  @IBAction func followingPrivacySwitchTapped(_ followingPrivacySwitch: UISwitch) {
    if followingPrivacySwitch.isOn {
      if let user = self.viewModel.followTapped(on: true) {
        self.delegate?.settingsFollowCellDidUpdate(user: user)
      }
    } else {
      self.delegate?.settingsFollowCellDidDisableFollowing(self)
    }
  }
}
