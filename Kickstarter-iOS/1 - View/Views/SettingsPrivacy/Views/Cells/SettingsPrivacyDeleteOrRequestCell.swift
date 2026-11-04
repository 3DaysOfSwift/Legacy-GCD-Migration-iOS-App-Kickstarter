import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol SettingsPrivacyDeleteOrRequestCellDelegate: AnyObject {
  func settingsPrivacyDeleteOrRequestCellTapped(_ cell: SettingsPrivacyDeleteOrRequestCell, with url: URL)
}

internal final class SettingsPrivacyDeleteOrRequestCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = SettingsDeleteOrRequestCellViewModel()
  internal weak var delegate: SettingsPrivacyDeleteOrRequestCellDelegate?

  internal enum CellType {
    case delete
    case request
  }

  @IBOutlet fileprivate var deleteAccountButton: UIButton!
  @IBOutlet fileprivate var deleteAccountLabel: UILabel!
  @IBOutlet fileprivate var separatorView: [UIView]!

  internal override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.deleteAccountButton].compact()

      self.deleteAccountButton.addTarget(self, action: #selector(self.deleteAccountTapped), for: .touchUpInside)
    }
  }

  internal func configureWith(value: (user: User, cellType: CellType)) {
    switch value.cellType {
    case .request:
      self.deleteAccountLabel.textColor = LegacyColors.ksr_support_700.uiColor()
      self.deleteAccountLabel.text = Strings.Request_my_personal_data()
      self.deleteAccountButton.accessibilityLabel = Strings.Request_my_personal_data()
    case .delete:
      self.deleteAccountLabel.textColor = LegacyColors.ksr_alert.uiColor()
      self.deleteAccountLabel.text = Strings.Delete_my_Kickstarter_Account()
      self.deleteAccountButton.accessibilityLabel = Strings.Delete_my_Kickstarter_Account()
    }
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

    _ = self.deleteAccountLabel
      |> UILabel.lens.font .~ .ksr_body()
      |> UILabel.lens.numberOfLines .~ 2
  }

  @objc fileprivate func deleteAccountTapped() {
    guard let url = self.viewModel.policyURL() else { return }
    self.delegate?.settingsPrivacyDeleteOrRequestCellTapped(self, with: url)
  }
}
