import KsApi

import Prelude
import Prelude_UIKit
import UIKit

@MainActor
internal protocol ProjectNotificationCellDelegate: AnyObject {
  /// Call with an error message when saving a notification fails.
  func projectNotificationCell(_ cell: ProjectNotificationCell?, notificationSaveError: String)
}

internal final class ProjectNotificationCell: UITableViewCell, ValueCell {
  fileprivate let viewModel = ProjectNotificationCellViewModel()
  internal weak var delegate: ProjectNotificationCellDelegate?

  @IBOutlet fileprivate var nameLabel: UILabel!
  @IBOutlet fileprivate var notificationSwitch: UISwitch!

  internal override func awakeFromNib() {
    super.awakeFromNib()
    // UIKit loads this view on the main thread; NSObject declares this hook nonisolated.
    MainActor.assumeIsolated {
      _ = self
        |> \.accessibilityElements .~ [self.notificationSwitch].compact()

      self.notificationSwitch.addTarget(self, action: #selector(self.notificationTapped), for: .valueChanged)
    }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()

    _ = self.nameLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.numberOfLines .~ 1
      |> UILabel.lens.lineBreakMode .~ .byTruncatingTail

    _ = self.notificationSwitch |> settingsSwitchStyle
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onName = { [weak self] name in
      self?.nameLabel.text = name
      self?.notificationSwitch.accessibilityLabel = name
    }
    self.viewModel.onSwitch = { [weak self] in self?.notificationSwitch.isOn = $0 }
    self.viewModel.onError = { [weak self] message in
      guard let self else { return }
      self.delegate?.projectNotificationCell(self, notificationSaveError: message)
    }
  }

  internal func configureWith(value: ProjectNotification) {
    self.viewModel.configureWith(notification: value)
  }

  @objc fileprivate func notificationTapped(_: UISwitch) {
    self.viewModel.notificationTapped(on: self.notificationSwitch.isOn)
  }
}
