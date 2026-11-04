
import Observation
import Prelude
import Prelude_UIKit
import UIKit

internal final class ResetPasswordViewController: UIViewController {
  @IBOutlet private var emailTextFieldBackgroundView: UIView!
  @IBOutlet private var emailTextField: UITextField!
  @IBOutlet private var resetPasswordButton: UIButton!
  @IBOutlet private var rootStackView: UIStackView!

  fileprivate let viewModel = ResetPasswordViewModel()

  internal static func configuredWith(email: String?) -> ResetPasswordViewController {
    let vc = Storyboard.Login.instantiate(ResetPasswordViewController.self)
    if let email = email {
      vc.viewModel.emailChanged(email)
    }
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.emailTextField.text = self.viewModel.email
    self.emailTextField.becomeFirstResponder()
    self.viewModel.viewDidLoad()
  }

  override func bindStyles() {
    _ = self |> resetPasswordControllerStyle
    _ = self.emailTextField |> emailFieldStyle
    _ = self.emailTextFieldBackgroundView |> cardStyle()
    _ = self.resetPasswordButton |> resetPasswordButtonStyle

    let isPad = self.traitCollection.userInterfaceIdiom == .pad
    applyLoginRootStackViewStyle(self.rootStackView, useLargerMargins: isPad)
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.observeValidity()
    self.viewModel.onResetSuccess = { [weak self] message in
      self?.present(UIAlertController.alert(
        message: message,
        handler: { _ in self?.viewModel.confirmResetButtonPressed() }
      ), animated: true, completion: nil)
    }
    self.viewModel.onReturnToLogin = { [weak self] in
      _ = self?.navigationController?.popViewController(animated: true)
    }
    self.viewModel.onError = { [weak self] message in
      self?.present(UIAlertController.genericError(message), animated: true, completion: nil)
    }
  }

  private func observeValidity() {
    withObservationTracking {
      self.resetPasswordButton.isEnabled = self.viewModel.formIsValid
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeValidity() }
    }
  }

  @IBAction
  internal func emailTextFieldEditingChanged(_ textfield: UITextField) {
    self.viewModel.emailChanged(textfield.text)
  }

  @IBAction
  internal func resetPasswordPressed(_: UIButton) {
    self.emailTextField.resignFirstResponder()
    self.viewModel.resetButtonPressed()
  }
}
