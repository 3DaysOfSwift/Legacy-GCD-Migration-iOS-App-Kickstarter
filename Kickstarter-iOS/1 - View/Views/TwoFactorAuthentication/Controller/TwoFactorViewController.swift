import Foundation
import KDS

import Prelude
import UIKit

internal final class TwoFactorViewController: UIViewController {
  fileprivate let viewModel: TwoFactorViewModel = TwoFactorViewModel()

  @IBOutlet fileprivate var codeTextField: UITextField!
  @IBOutlet fileprivate var formBackgroundView: UIView!
  @IBOutlet fileprivate var formStackView: UIStackView!
  @IBOutlet fileprivate var resendButton: UIButton!
  @IBOutlet fileprivate var submitButton: UIButton!
  @IBOutlet fileprivate var titleLabel: UILabel!

  internal override func viewDidLoad() {
    super.viewDidLoad()
    self.viewModel.viewDidLoad()
  }

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.viewModel.viewWillAppear()
  }

  internal override func bindStyles() {
    super.bindStyles()

    let isPad = self.traitCollection.isRegularRegular

    _ = self
      |> twoFactorControllerStyle
      |> UIViewController.lens.view.backgroundColor .~ LegacyColors.ksr_white.uiColor()
      |> UIViewController.lens.view.layoutMargins %~~ { _, _ in
        isPad ? .init(all: Styles.grid(20)) : .init(all: Styles.grid(3))
      }

    _ = self.codeTextField
      |> tfaCodeFieldAutoFillStyle

    _ = self.formBackgroundView
      |> cardStyle()
      |> UIView.lens.layoutMargins %~~ { _, _ in
        isPad ? .init(all: Styles.grid(10)) : .init(all: Styles.grid(3))
      }

    _ = self.formStackView
      |> UIStackView.lens.spacing .~ Styles.grid(5)

    self.resendButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
    self.resendButton.setTitle(Strings.two_factor_buttons_resend(), for: .normal)

    self.submitButton.applyStyleConfiguration(KSRButtonStyle.green)
    self.submitButton.setTitle(Strings.two_factor_buttons_submit(), for: .normal)

    _ = self.titleLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ .ksr_body()
      |> UILabel.lens.text %~ { _ in Strings.two_factor_message() }
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onFirstResponder = { [weak self] in self?.codeTextField.becomeFirstResponder() }
    self.viewModel.onFormValid = { [weak self] in self?.submitButton.isEnabled = $0 }
    self.viewModel.onLogin = { [weak self] _ in self?.viewModel.environmentLoggedIn() }
    self.viewModel.onNotification = { first, second in
      NotificationCenter.default.post(first)
      NotificationCenter.default.post(second)
    }
    self.viewModel.onError = { [weak self] in self?.showError($0) }
  }

  internal static func configuredWith(email: String, password: String) -> TwoFactorViewController {
    let vc = self.instantiate()
    vc.viewModel.email(email, password: password)
    return vc
  }

  internal static func configuredWith(facebookAccessToken token: String) -> TwoFactorViewController {
    let vc = self.instantiate()
    vc.viewModel.facebookToken(token)
    return vc
  }

  fileprivate static func instantiate() -> TwoFactorViewController {
    return Storyboard.Login.instantiate(TwoFactorViewController.self)
  }

  fileprivate func showError(_ message: String) {
    self.present(UIAlertController.genericError(message), animated: true, completion: nil)
  }

  @IBAction
  internal func codeEditingChanged(_ textField: UITextField) {
    self.viewModel.codeChanged(textField.text)
  }

  @IBAction
  internal func resendButtonPressed(_: AnyObject) {
    self.viewModel.resendPressed()
  }

  @IBAction
  internal func submitButtonPressed(_: AnyObject) {
    self.viewModel.submitPressed()
  }
}
