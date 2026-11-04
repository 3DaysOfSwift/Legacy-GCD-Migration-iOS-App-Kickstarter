import KDS

import Prelude
import Prelude_UIKit
import UIKit

internal final class LoginViewController: UIViewController {
  @IBOutlet fileprivate var emailTextField: UITextField!
  @IBOutlet fileprivate var forgotPasswordButton: UIButton!
  @IBOutlet fileprivate var formBackgroundView: UIView!
  @IBOutlet fileprivate var formDividerView: UIView!
  @IBOutlet fileprivate var loginButton: UIButton!
  @IBOutlet fileprivate var passwordTextField: UITextField!
  @IBOutlet fileprivate var rootStackView: UIStackView!
  @IBOutlet fileprivate var showHidePasswordButton: UIButton!

  internal let viewModel: LoginViewModel = LoginViewModel()

  internal static func instantiate() -> LoginViewController {
    return Storyboard.Login.instantiate(LoginViewController.self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let tap = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard))
    self.view.addGestureRecognizer(tap)

    self.emailTextField.addTarget(
      self,
      action: #selector(self.emailTextFieldDoneEditing),
      for: .editingDidEndOnExit
    )

    self.emailTextField.addTarget(
      self,
      action: #selector(self.emailTextFieldChanged(_:)),
      for: [.editingDidEndOnExit, .editingChanged]
    )

    self.passwordTextField.addTarget(
      self,
      action: #selector(self.passwordTextFieldDoneEditing),
      for: .editingDidEndOnExit
    )

    self.passwordTextField.addTarget(
      self,
      action: #selector(self.passwordTextFieldChanged(_:)),
      for: .editingChanged
    )

    self.showHidePasswordButton.addTarget(
      self,
      action: #selector(self.showHidePasswordButtonTapped),
      for: .touchUpInside
    )

    self.viewModel.viewDidLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.viewModel.viewWillAppear()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    self.viewModel.traitCollectionDidChange()
  }

  override func bindStyles() {
    _ = self |> loginControllerStyle

    self.loginButton.applyStyleConfiguration(KSRButtonStyle.green)
    self.loginButton.setTitle(Strings.login_tout_back_intent_traditional_login_button(), for: .normal)

    _ = self.forgotPasswordButton |> forgotPasswordButtonStyle

    _ = self.emailTextField |> emailFieldAutoFillStyle
      |> UITextField.lens.returnKeyType .~ .next

    _ = self.showHidePasswordButton |> showHidePasswordButtonStyle
      |> \.frame .~ CGRect(x: 0, y: 0, width: 45, height: 30)
      |> UIButton.lens.image(for: .normal) .~ image(
        named: "icon--eye",
        inBundle: Bundle.main,
        compatibleWithTraitCollection: nil
      )
      |> UIButton.lens.accessibilityValue %~ { _ in
        Strings.Show_password()
      }

    _ = self.passwordTextField |> passwordFieldAutoFillStyle
      |> UITextField.lens.returnKeyType .~ .go

    _ = self.formDividerView |> separatorStyle

    _ = self.formBackgroundView |> cardStyle()

    let isPad = self.traitCollection.userInterfaceIdiom == .pad
    applyLoginRootStackViewStyle(self.rootStackView, useLargerMargins: isPad)
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEmailFirstResponder = { [weak self] in self?.emailTextField.becomeFirstResponder() }
    self.viewModel.onFormValid = { [weak self] in self?.loginButton.isEnabled = $0 }
    self.viewModel.onPasswordFirstResponder = { [weak self] in self?.passwordTextField.becomeFirstResponder() }
    self.viewModel.onPasswordVisibility = { [weak self] in self?.updateShowHidePassword($0) }
    self.viewModel.onDismissKeyboard = { [weak self] in self?.dismissKeyboard() }
    self.viewModel.onNotification = { first, second in
      NotificationCenter.default.post(first)
      NotificationCenter.default.post(second)
    }
    self.viewModel.onLogin = { [weak self] _ in self?.viewModel.environmentLoggedIn() }
    self.viewModel.onResetPassword = { [weak self] in self?.startResetPasswordViewController() }
    self.viewModel.onError = { [weak self] in self?.present(UIAlertController.genericError($0), animated: true, completion: nil) }
    self.viewModel.onTwoFactor = { [weak self] email, password in self?.startTwoFactorViewController(email, password: password) }
  }

  fileprivate func startTwoFactorViewController(_ email: String, password: String) {
    let vc = TwoFactorViewController.configuredWith(email: email, password: password)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  fileprivate func startResetPasswordViewController() {
    let vc = ResetPasswordViewController.configuredWith(email: self.emailTextField.text)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  fileprivate func updateShowHidePassword(_ shouldShow: Bool) {
    let tintColor: UIColor = shouldShow ? LegacyColors.ksr_create_700.uiColor() : LegacyColors.ksr_support_300
      .uiColor()
    let accessibilityValue = shouldShow ? Strings.Hide_password() : Strings.Show_password()

    _ = self.showHidePasswordButton
      |> UIButton.lens.tintColor .~ tintColor
      |> UIButton.lens.accessibilityValue .~ accessibilityValue

    let currentText = self.passwordTextField ^* UITextField.lens.text

    // Note: workaround for cursor whitespace render bug
    _ = self.passwordTextField
      |> UITextField.lens.secureTextEntry .~ !shouldShow
      |> UITextField.lens.text .~ " "
      |> UITextField.lens.text .~ currentText
  }

  @IBAction
  internal func loginButtonPressed(_: UIButton) {
    self.viewModel.loginButtonPressed()
  }

  @objc internal func emailTextFieldChanged(_ textField: UITextField) {
    self.viewModel.emailChanged(textField.text)
  }

  @objc internal func emailTextFieldDoneEditing() {
    self.viewModel.emailTextFieldDoneEditing()
  }

  @objc internal func passwordTextFieldChanged(_ textField: UITextField) {
    self.viewModel.passwordChanged(textField.text)
  }

  @objc internal func passwordTextFieldDoneEditing() {
    self.viewModel.passwordTextFieldDoneEditing()
  }

  @IBAction
  internal func resetPasswordButtonPressed(_: UIButton) {
    self.viewModel.resetPasswordButtonPressed()
  }

  @objc internal func dismissKeyboard() {
    self.view.endEditing(true)
  }

  @objc func showHidePasswordButtonTapped() {
    self.viewModel.showHidePasswordButtonTapped()
  }
}
