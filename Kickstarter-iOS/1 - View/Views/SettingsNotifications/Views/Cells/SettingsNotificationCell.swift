import KDS
import KsApi

import Prelude
import UIKit

@MainActor
protocol SettingsNotificationCellDelegate: AnyObject {
  func settingsNotificationCell(_ cell: SettingsNotificationCell, didFailToUpdateUser errorMessage: String)
  func settingsNotificationCell(_ cell: SettingsNotificationCell, didUpdateUser user: User)
}

final class SettingsNotificationCell: UITableViewCell, NibLoading, ValueCell {
  @IBOutlet fileprivate var arrowImageView: UIImageView!
  @IBOutlet fileprivate var emailNotificationsButton: UIButton!
  @IBOutlet fileprivate var projectCountLabel: UILabel!
  @IBOutlet fileprivate var pushNotificationsButton: UIButton!
  @IBOutlet fileprivate var stackView: UIStackView!
  @IBOutlet fileprivate var titleLabel: UILabel!

  weak var delegate: SettingsNotificationCellDelegate?

  private let viewModel = SettingsNotificationCellViewModel()
  private lazy var tapGesture: UITapGestureRecognizer = {
    UITapGestureRecognizer(target: self, action: #selector(self.cellBackgroundTapped))
  }()

  private var notificationType: SettingsNotificationCellType?

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  func configureWith(value cellValue: SettingsNotificationCellValue) {
    self.notificationType = cellValue.cellType

    self.viewModel.configure(with: cellValue)

    let accessibilityElementsHidden = cellValue.cellType.accessibilityElementsHidden

    _ = self
      |> \.accessibilityTraits .~ cellValue.cellType.accessibilityTraits

    _ = self.stackView
      |> \.accessibilityElements .~ (
        accessibilityElementsHidden
          ? [self.emailNotificationsButton, self.pushNotificationsButton].compact()
          : []
      )

    _ = self.titleLabel
      |> UILabel.lens.text .~ cellValue.cellType.title
      |> \.accessibilityElementsHidden .~ cellValue.cellType.accessibilityElementsHidden

    _ = self.arrowImageView
      |> UIImageView.lens.isHidden .~ cellValue.cellType.shouldHideArrowView
      |> UIImageView.lens.tintColor .~ LegacyColors.ksr_support_400.uiColor()

    _ = self.projectCountLabel
      |> UILabel.lens.isHidden .~ cellValue.cellType.projectCountLabelHidden
      |> \.accessibilityElementsHidden .~ accessibilityElementsHidden
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableViewCellStyle()

    _ = self.titleLabel
      |> settingsTitleLabelStyle

    _ = self.projectCountLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_400.uiColor()
      |> UILabel.lens.font .~ .ksr_body()

    _ = self.emailNotificationsButton |> notificationButtonStyle
      |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(
        named: "email-icon",
        tintColor: LegacyColors.ksr_support_400.uiColor(),
        inBundle: Bundle.main
      )
      |> UIButton.lens.image(for: .highlighted) .~ Kickstarter_iOS.image(
        named: "email-icon",
        tintColor: LegacyColors.ksr_support_300.uiColor(),
        inBundle: Bundle.main
      )
      |> UIButton.lens.image(for: .selected) .~ Kickstarter_iOS.image(
        named: "email-icon",
        tintColor: LegacyColors.ksr_create_700.uiColor(),
        inBundle: Bundle.main
      )

    _ = self.pushNotificationsButton
      |> notificationButtonStyle
      |> UIButton.lens.image(for: .normal) .~ Kickstarter_iOS.image(
        named: "mobile-icon",
        tintColor: LegacyColors.ksr_support_400.uiColor(),
        inBundle: Bundle.main
      )
      |> UIButton.lens.image(for: .highlighted) .~ Kickstarter_iOS.image(
        named: "mobile-icon",
        tintColor: LegacyColors.ksr_support_300.uiColor(),
        inBundle: Bundle.main
      )
      |> UIButton.lens.image(for: .selected) .~ Kickstarter_iOS.image(
        named: "mobile-icon",
        tintColor: LegacyColors.ksr_create_700.uiColor(),
        inBundle: Bundle.main
      )
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onChange = { [weak self] in self?.renderNotificationState() }
    self.viewModel.onUserUpdated = { [weak self] user in
      guard let self else { return }
      self.delegate?.settingsNotificationCell(self, didUpdateUser: user)
    }
    self.viewModel.onError = { [weak self] error in
      guard let self else { return }
      self.delegate?.settingsNotificationCell(self, didFailToUpdateUser: error)
    }
  }

  private func renderNotificationState() {
    guard let type = self.viewModel.cellType else { return }
    if let enabled = self.viewModel.emailEnabled {
      self.emailNotificationsButton.isSelected = enabled
      self.emailNotificationsButton.accessibilityLabel = enabled
        ? Strings.Notification_email_notification_on(notification: type.title)
        : Strings.Notification_email_notification_off(notification: type.title)
    }
    if let enabled = self.viewModel.pushEnabled {
      self.pushNotificationsButton.isSelected = enabled
      self.pushNotificationsButton.accessibilityLabel = enabled
        ? Strings.Notification_push_notification_on(notification: type.title)
        : Strings.Notification_push_notification_off(notification: type.title)
    }
    self.emailNotificationsButton.isHidden = !type.shouldShowEmailNotificationButton
    self.pushNotificationsButton.isHidden = !type.shouldShowPushNotificationButton
    self.projectCountLabel.text = self.viewModel.projectCountText
    if type.shouldShowEmailNotificationButton || type.shouldShowPushNotificationButton {
      self.addGestureRecognizer(self.tapGesture)
    } else {
      self.removeGestureRecognizer(self.tapGesture)
    }
  }

  @IBAction func emailNotificationsButtonTapped(_ sender: UIButton) {
    self.viewModel.didTapEmailNotificationsButton(selected: sender.isSelected)
  }

  @IBAction func pushNotificationsButtonTapped(_ sender: UIButton) {
    self.viewModel.didTapPushNotificationsButton(selected: sender.isSelected)
  }

  @IBAction func cellBackgroundTapped(_: Any) {
    let sizeTransform = CGAffineTransform(scaleX: 1.2, y: 1.2)
    let animationDuration: TimeInterval = 0.15

    UIView.animate(withDuration: animationDuration, animations: { [weak self] in
      self?.pushNotificationsButton.transform = sizeTransform
    }, completion: { [weak self] _ in
      guard let _self = self else { return }

      _self.identityAnimation(for: _self.pushNotificationsButton)
    })

    UIView.animate(
      withDuration: animationDuration,
      delay: 0.1,
      options: .curveEaseInOut,
      animations: { [weak self] in
        self?.emailNotificationsButton.transform = sizeTransform
      }, completion: { [weak self] _ in
        guard let _self = self else { return }

        _self.identityAnimation(for: _self.emailNotificationsButton)
      }
    )
  }

  private func identityAnimation(for button: UIButton, duration: TimeInterval = 0.15) {
    UIView.animate(withDuration: duration, animations: {
      button.transform = .identity
    }, completion: nil)
  }
}
