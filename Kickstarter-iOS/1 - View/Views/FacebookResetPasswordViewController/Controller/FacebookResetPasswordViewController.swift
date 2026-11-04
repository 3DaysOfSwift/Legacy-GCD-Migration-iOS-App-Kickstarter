import Observation
import Foundation
import KDS

import Prelude
import ReactiveSwift
import UIKit

public final class FacebookResetPasswordViewController: UIViewController {
  // MARK: - Properties

  private lazy var contextLabel = { UILabel(frame: .zero) }()
  private lazy var emailLabel: UILabel = { UILabel(frame: .zero) }()
  private lazy var emailTextField: UITextField = { UITextField(frame: .zero) }()

  private lazy var loadingIndicator: UIActivityIndicatorView = {
    UIActivityIndicatorView()
      |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  private lazy var rootStackView = { UIStackView() }()
  private lazy var scrollView = {
    UIScrollView(frame: .zero)
      |> \.alwaysBounceVertical .~ true
      |> \.showsVerticalScrollIndicator .~ false

  }()

  private lazy var setPasswordButton = { UIButton(type: .custom)
    |> \.translatesAutoresizingMaskIntoConstraints .~ false
  }()

  fileprivate lazy var keyboardDimissingTapGestureRecognizer: UITapGestureRecognizer = {
    UITapGestureRecognizer(
      target: self,
      action: #selector(FacebookResetPasswordViewController.dismissKeyboard)
    )
      |> \.cancelsTouchesInView .~ false
  }()

  private let viewModel = FacebookResetPasswordViewModel()

  // MARK: - Lifecycle

  public override func viewDidLoad() {
    super.viewDidLoad()

    self.title = Strings.Set_new_password()

    self.view.addGestureRecognizer(self.keyboardDimissingTapGestureRecognizer)

    self.configureViews()
    self.setupConstraints()
    self.configureTargets()

  }

  public override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    self.contextLabel.text = Strings.We_re_simplifying_our_login_process_To_log_in()
    self.emailLabel.text = Strings.forgot_password_placeholder_email()
  }

  // MARK: - Styles

  public override func bindStyles() {
    super.bindStyles()

    _ = self.contextLabel
      |> contextLabelStyle

    _ = self.rootStackView
      |> baseStackViewStyle
    let isPad = self.traitCollection.userInterfaceIdiom == .pad
    applyLoginRootStackViewStyle(self.rootStackView, useLargerMargins: isPad)

    _ = self.emailLabel
      |> textFieldLabelStyle

    _ = self.emailTextField
      |> emailFieldStyle
      |> UITextField.lens.returnKeyType .~ .go
      |> roundedStyle(cornerRadius: Styles.grid(2))
      |> UITextField.lens.borderStyle .~ UITextField.BorderStyle.roundedRect
      |> UITextField.lens.layer.borderColor .~ LegacyColors.ksr_support_300.uiColor().cgColor
      |> UITextField.lens.layer.borderWidth .~ 1
      |> UITextField.lens.accessibilityLabel .~ self.emailLabel.text
      |> \.attributedPlaceholder %~ { _ in settingsAttributedPlaceholder("") }

    _ = self.setPasswordButton
      |> resetPasswordButtonStyle
      |> UIButton.lens.title(for: .normal) %~ { _ in
        Strings.Set_new_password()
      }
      |> UIButton.lens.isEnabled .~ false
  }

  // MARK: - Bind View Model

  public override func bindViewModel() {
    super.bindViewModel()

    self.observeState()
    self.viewModel.onFailure = { [weak self] message in
      self?.present(UIAlertController.genericError(message), animated: true, completion: nil)
    }
    self.viewModel.onSuccess = { [weak self] message in
      self?.present(UIAlertController.alert(message: message), animated: true)
    }

    Keyboard.change.observeForUI()
      .observeValues { [weak self] in self?.animateTextViewConstraint($0) }
  }

  private func observeState() {
    withObservationTracking {
      if self.viewModel.isLoading { self.loadingIndicator.startAnimating() }
      else { self.loadingIndicator.stopAnimating() }
      self.setPasswordButton.isEnabled = self.viewModel.isValid
      self.enableTextFieldsAndSaveButton(!self.viewModel.isLoading)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeState() }
    }
  }

  // MARK: - Functions

  private func configureViews() {
    _ = self.view
      |> \.backgroundColor .~ LegacyColors.ksr_white.uiColor()

    _ = (self.scrollView, self.view)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = (self.rootStackView, self.scrollView)
      |> ksr_addSubviewToParent()
      |> ksr_constrainViewToEdgesInParent()

    _ = ([
      self.contextLabel,
      self.emailLabel,
      self.emailTextField,
      self.setPasswordButton,
      self.loadingIndicator
    ], self.rootStackView)
      |> ksr_addArrangedSubviewsToStackView()

    self.rootStackView.setCustomSpacing(Styles.grid(7), after: self.contextLabel)
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      self.rootStackView.widthAnchor.constraint(equalTo: self.view.widthAnchor),

      self.emailTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

      self.setPasswordButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    ])
  }

  private func configureTargets() {
    self.emailTextField
      .addTarget(
        self,
        action: #selector(self.emailTextFieldDidChange(_:)),
        for: [.editingChanged, .editingDidEndOnExit]
      )
    self.emailTextField
      .addTarget(self, action: #selector(self.emailTextFieldReturn(_:)), for: .editingDidEndOnExit)

    self.setPasswordButton
      .addTarget(self, action: #selector(self.setPasswordButtonPressed), for: .touchUpInside)
  }

  private func enableTextFieldsAndSaveButton(_ isEnabled: Bool) {
    _ = [self.emailTextField, self.setPasswordButton]
      ||> \.isUserInteractionEnabled .~ isEnabled

    self.setPasswordButton.isHidden = !isEnabled
  }

  private func animateTextViewConstraint(_ change: Keyboard.Change) {
    UIView.animate(withDuration: change.duration, delay: 0.0, options: change.options, animations: {
      self.scrollView.contentInset.bottom = change.frame.height
    }, completion: nil)
  }

  // MARK: - Accessors

  @objc private func dismissKeyboard() {
    self.view.endEditing(true)
  }

  @objc private func emailTextFieldDidChange(_ textField: UITextField) {
    guard let email = textField.text else { return }

    self.viewModel.emailTextFieldFieldDidChange(email)
  }

  @objc internal func emailTextFieldReturn(_: UITextField) {
    self.viewModel.emailTextFieldFieldDidReturn()
  }

  @objc private func setPasswordButtonPressed() {
    self.viewModel.setPasswordButtonPressed()
  }
}

// MARK: - Styles

private let baseStackViewStyle: StackViewStyle = { stackView in
  stackView
    |> UIStackView.lens.distribution .~ .fill
    |> UIStackView.lens.alignment .~ .fill
    |> UIStackView.lens.axis .~ .vertical
    |> UIStackView.lens.spacing .~ Styles.grid(2)
}

@MainActor private let contextLabelStyle: LabelStyle = { label in
  label
    |> UILabel.lens.textAlignment .~ NSTextAlignment.left
    |> UILabel.lens.lineBreakMode .~ NSLineBreakMode.byWordWrapping
    |> UILabel.lens.numberOfLines .~ 0
    |> UILabel.lens.font %~ { _ in UIFont.ksr_body(size: 16) }
}

@MainActor private let textFieldLabelStyle: LabelStyle = { label in
  label
    |> UILabel.lens.textAlignment .~ NSTextAlignment.left
    |> UILabel.lens.lineBreakMode .~ NSLineBreakMode.byWordWrapping
    |> UILabel.lens.numberOfLines .~ 0
    |> UILabel.lens.backgroundColor .~ LegacyColors.ksr_white.uiColor()
    |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
    |> \.font %~ { _ in .ksr_callout(size: 13) }
}

@MainActor
private let textFieldStyle: TextFieldStyle = { textField in
  settingsNewPasswordFormFieldAutoFillStyle(textField)
    |> roundedStyle(cornerRadius: Styles.grid(2))
    |> UITextField.lens.textColor .~ LegacyColors.ksr_black.uiColor()
    |> UITextField.lens.font %~ { _ in UIFont.ksr_body(size: 13) }
    |> UITextField.lens.textAlignment .~ .left
    |> UITextField.lens.borderStyle .~ UITextField.BorderStyle.roundedRect
    |> UITextField.lens.layer.borderColor .~ LegacyColors.ksr_support_300.uiColor().cgColor
    |> UITextField.lens.layer.borderWidth .~ 1
    |> UITextField.lens.returnKeyType .~ .done
}
