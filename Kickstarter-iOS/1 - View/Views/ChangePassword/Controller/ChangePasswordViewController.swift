import Observation
import KDS
import KsApi

import Prelude
import UIKit

final class ChangePasswordViewController: UIViewController, MessageBannerViewControllerPresenting {
  private var keyboardObservation: Keyboard.Observation?
  @IBOutlet fileprivate var changePasswordLabel: UILabel!
  @IBOutlet fileprivate var confirmNewPasswordLabel: UILabel!
  @IBOutlet fileprivate var confirmNewPasswordTextField: UITextField!
  @IBOutlet fileprivate var currentPasswordLabel: UILabel!
  @IBOutlet fileprivate var currentPasswordTextField: UITextField!
  @IBOutlet fileprivate var validationErrorMessageLabel: UILabel!
  @IBOutlet fileprivate var newPasswordLabel: UILabel!
  @IBOutlet fileprivate var newPasswordTextField: UITextField!
  @IBOutlet fileprivate var scrollView: UIScrollView!
  @IBOutlet fileprivate var stackView: UIStackView!

  private var saveButtonView: LoadingBarButtonItemView!
  internal var messageBannerViewController: MessageBannerViewController?

  private let viewModel = ChangePasswordViewModel()

  internal static func instantiate() -> ChangePasswordViewController {
    return Storyboard.Settings.instantiate(ChangePasswordViewController.self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.messageBannerViewController = self.configureMessageBannerViewController(on: self)

    self.saveButtonView = LoadingBarButtonItemView.instantiate()
    self.saveButtonView.setTitle(title: Strings.Save())
    self.saveButtonView.addTarget(self, action: #selector(self.saveButtonTapped(_:)))

    let navigationBarButton = LoadingBarButtonItemView.uiBarButtonItem(for: self.saveButtonView)
    self.navigationItem.setRightBarButton(navigationBarButton, animated: false)
    self.observeSaveState()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.viewModel.viewDidAppear()
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.scrollView
      |> \.alwaysBounceVertical .~ true
      |> \.backgroundColor .~ LegacyColors.ksr_support_100.uiColor()

    _ = self.stackView
      |> \.layoutMargins .~ .init(topBottom: Styles.grid(1), leftRight: Styles.grid(2))

    _ = self
      |> settingsViewControllerStyle
      |> UIViewController.lens.title %~ { _ in
        Strings.Change_password()
      }

    _ = [self.currentPasswordLabel, self.newPasswordLabel, self.confirmNewPasswordLabel]
      ||> \.isAccessibilityElement .~ false

    _ = self.changePasswordLabel
      |> settingsDescriptionLabelStyle
      |> UILabel.lens.text %~ { _ in
        Strings.Well_ask_you_to_sign_back_into_the_Kickstarter_app_once_youve_changed_your_password()
      }

    _ = self.confirmNewPasswordLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.text %~ { _ in Strings.Confirm_password() }

    _ = settingsNewPasswordFormFieldAutoFillStyle(self.confirmNewPasswordTextField)
      |> \.accessibilityLabel .~ self.confirmNewPasswordLabel.text
      |> UITextField.lens.returnKeyType .~ .done
      |> \.attributedPlaceholder %~ { _ in
        settingsAttributedPlaceholder(Strings.login_placeholder_password())
      }

    _ = self.currentPasswordLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.text %~ { _ in Strings.Current_password() }

    _ = settingsPasswordFormFieldAutoFillStyle(self.currentPasswordTextField)
      |> \.accessibilityLabel .~ self.currentPasswordLabel.text
      |> \.attributedPlaceholder %~ { _ in
        settingsAttributedPlaceholder(Strings.login_placeholder_password())
      }

    _ = self.validationErrorMessageLabel
      |> settingsDescriptionLabelStyle

    _ = self.newPasswordLabel
      |> settingsTitleLabelStyle
      |> UILabel.lens.text %~ { _ in Strings.New_password() }

    _ = settingsNewPasswordFormFieldAutoFillStyle(self.newPasswordTextField)
      |> \.accessibilityLabel .~ self.newPasswordLabel.text
      |> \.attributedPlaceholder %~ { _ in
        settingsAttributedPlaceholder(Strings.login_placeholder_password())
      }
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.observeValidation()
    self.viewModel.onFocusCurrent = { [weak self] in self?.currentPasswordTextField.becomeFirstResponder() }
    self.viewModel.onFocusNew = { [weak self] in self?.newPasswordTextField.becomeFirstResponder() }
    self.viewModel.onFocusConfirmation = { [weak self] in self?.confirmNewPasswordTextField.becomeFirstResponder() }
    self.viewModel.onDismissKeyboard = { [weak self] in self?.dismissKeyboard() }
    self.viewModel.onFailure = { [weak self] in self?.messageBannerViewController?.showBanner(with: .error, message: $0) }
    self.viewModel.onSuccess = { [weak self] in self?.logoutAndDismiss() }
    self.viewModel.onAccessibilityFocus = { [weak self] in
      UIAccessibility.post(notification: .layoutChanged, argument: self?.validationErrorMessageLabel)
    }

    self.keyboardObservation = Keyboard.observe { [weak self] change in
        self?.scrollView.handleKeyboardVisibilityDidChange(change)
      }
  }

  private func observeValidation() {
    withObservationTracking {
      self.validationErrorMessageLabel.text = self.viewModel.validationMessage
      self.validationErrorMessageLabel.isHidden = self.viewModel.validationMessage.isEmpty
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeValidation() }
    }
  }

  private func observeSaveState() {
    withObservationTracking {
      if self.viewModel.isLoading { self.saveButtonView.startAnimating() }
      else { self.saveButtonView.stopAnimating() }
      self.saveButtonView.setIsEnabled(isEnabled: self.viewModel.saveButtonIsEnabled)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSaveState() }
    }
  }

  // MARK: - Functions

  private func logoutAndDismiss() {
    AppEnvironment.logout()
    PushNotificationDialog.resetAllContexts()

    NotificationCenter.default.post(.init(name: .ksr_sessionEnded))

    self.dismiss(animated: true, completion: nil)
  }

  private func dismissKeyboard() {
    [self.newPasswordTextField, self.confirmNewPasswordTextField, self.currentPasswordTextField]
      .forEach { $0?.resignFirstResponder() }
  }

  // MARK: - Actions

  @IBAction func currentPasswordTextDidChange(_ sender: UITextField) {
    guard let text = sender.text else {
      return
    }

    self.viewModel.currentPasswordFieldTextChanged(text: text)
  }

  @IBAction func currentPasswordDidEndEditing(_ sender: UITextField) {
    guard let currentPassword = sender.text else {
      return
    }

    self.viewModel.currentPasswordFieldTextChanged(text: currentPassword)
  }

  @IBAction func currentPasswordDidReturn(_ sender: UITextField) {
    guard let currentPassword = sender.text else {
      return
    }

    self.viewModel.currentPasswordFieldDidReturn(currentPassword: currentPassword)
  }

  @IBAction func newPasswordTextDidChange(_ sender: UITextField) {
    guard let text = sender.text else {
      return
    }

    self.viewModel.newPasswordFieldTextChanged(text: text)
  }

  @IBAction func newPasswordDidEndEditing(_ sender: UITextField) {
    guard let newPassword = sender.text else {
      return
    }

    self.viewModel.newPasswordFieldTextChanged(text: newPassword)
  }

  @IBAction func newPasswordDidReturn(_ sender: UITextField) {
    guard let newPassword = sender.text else {
      return
    }

    self.viewModel.newPasswordFieldDidReturn(newPassword: newPassword)
  }

  @IBAction func confirmNewPasswordTextDidChange(_ sender: UITextField) {
    guard let text = sender.text else {
      return
    }

    self.viewModel.newPasswordConfirmationFieldTextChanged(text: text)
  }

  @IBAction func confirmNewPasswordDidEndEditing(_ sender: UITextField) {
    guard let newPasswordConfirmed = sender.text else {
      return
    }

    self.viewModel
      .newPasswordConfirmationFieldTextChanged(text: newPasswordConfirmed)
  }

  @IBAction func confirmNewPasswordDidReturn(_ sender: UITextField) {
    guard let newPasswordConfirmed = sender.text else {
      return
    }

    self.viewModel
      .newPasswordConfirmationFieldDidReturn(newPasswordConfirmed: newPasswordConfirmed)
  }

  @IBAction func saveButtonTapped(_: Any) {
    self.viewModel.saveButtonTapped()
  }
}
