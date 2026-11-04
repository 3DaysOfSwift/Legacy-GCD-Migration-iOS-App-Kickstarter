import Observation
import Foundation

import MessageUI
import Prelude
import ReactiveExtensions
import ReactiveSwift
import UIKit

internal final class FacebookConfirmationViewController: UIViewController,
  @MainActor MFMailComposeViewControllerDelegate {
  @IBOutlet private var disclaimerTextView: UITextView!
  @IBOutlet private var confirmationLabel: UILabel!
  @IBOutlet private var createAccountButton: UIButton!
  @IBOutlet private var emailLabel: UILabel!
  @IBOutlet private var loginButton: UIButton!
  @IBOutlet private var loginLabel: UILabel!
  @IBOutlet private var newsletterLabel: UILabel!
  @IBOutlet private var newsletterSwitch: UISwitch!
  @IBOutlet private var rootStackView: UIStackView!

  private let helpViewModel = HelpViewModel()
  fileprivate let viewModel = FacebookConfirmationViewModel()

  internal static func configuredWith(facebookUserEmail email: String, facebookAccessToken token: String)
    -> FacebookConfirmationViewController {
    let vc = Storyboard.Login.instantiate(FacebookConfirmationViewController.self)
    vc.viewModel.email(email)
    vc.viewModel.facebookToken(token)
    vc.helpViewModel.configureWith(helpContext: .facebookConfirmation)
    vc.helpViewModel.canSendEmail(MFMailComposeViewController.canSendMail())
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.createAccountButton.addTarget(
      self, action: #selector(self.createAccountButtonPressed),
      for: .touchUpInside
    )

    self.loginButton.addTarget(self, action: #selector(self.loginButtonPressed), for: .touchUpInside)

    self.newsletterSwitch.addTarget(
      self, action: #selector(self.newsletterSwitchChanged),
      for: .valueChanged
    )

    let tapGestureRecognizer = UITapGestureRecognizer(
      target: self, action: #selector(self.newsletterLabelTapped)
    )
    self.newsletterLabel.addGestureRecognizer(tapGestureRecognizer)

    self.disclaimerTextView.delegate = self

    self.viewModel.viewDidLoad()
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self.confirmationLabel |> fbConfirmationMessageLabelStyle
    _ = self.createAccountButton |> createNewAccountButtonStyle
    _ = self.emailLabel |> fbConfirmEmailLabelStyle
    _ = self.loginButton |> loginWithEmailButtonStyle
    _ = self.loginLabel |> fbWrongAccountLabelStyle
    _ = self.navigationItem.title = Strings.signup_navbar_title()
    _ = self.newsletterLabel |> newsletterLabelStyle
    _ = self.newsletterSwitch |> newsletterSwitchStyle

    let isPad = self.traitCollection.userInterfaceIdiom == .pad
    applyDisclaimerTextViewStyle(self.disclaimerTextView, useLargerText: isPad)
    applyLoginRootStackViewStyle(self.rootStackView, useLargerMargins: isPad)
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.observeConfirmationState()
    self.viewModel.onLogin = { [weak self] in self?.goToLoginViewController() }
    self.viewModel.onSignupSuccess = {
      NotificationCenter.default.post(name: .ksr_sessionStarted, object: nil)
    }
    self.viewModel.onSignupError = { [weak self] message in
      self?.present(UIAlertController.genericError(message), animated: true, completion: nil)
    }
    self.viewModel.onHelp = { [weak self] in self?.goToHelpType($0) }

    self.helpViewModel.onHelpSheet = { [weak self] in
        self?.showHelpSheet(helpTypes: $0)
      }

    self.helpViewModel.onMailCompose = { [weak self] in
        guard let _self = self else { return }
        let controller = MFMailComposeViewController.support()
        controller.mailComposeDelegate = _self
        _self.present(controller, animated: true, completion: nil)
      }

    self.helpViewModel.onNoEmailError = { [weak self] alert in
        self?.present(alert, animated: true, completion: nil)
      }

    self.helpViewModel.onWebHelp = { [weak self] helpType in
        self?.goToHelpType(helpType)
      }

  }

  private func observeConfirmationState() {
    withObservationTracking {
      self.emailLabel.text = self.viewModel.displayEmail
      self.newsletterSwitch.setOn(self.viewModel.sendNewsletters, animated: false)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeConfirmationState() }
    }
  }

  fileprivate func goToHelpType(_ helpType: HelpType) {
    let vc = HelpWebViewController.configuredWith(helpType: helpType)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  fileprivate func goToLoginViewController() {
    self.navigationController?.pushViewController(LoginViewController.instantiate(), animated: true)
  }

  fileprivate func showHelpSheet(helpTypes: [HelpType]) {
    let helpSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    helpTypes.forEach { helpType in
      helpSheet.addAction(
        UIAlertAction(title: helpType.title, style: .default) { [weak helpVM = self.helpViewModel] _ in
          helpVM?.helpTypeButtonTapped(helpType)
        }
      )
    }

    helpSheet.addAction(
      UIAlertAction(
        title: Strings.login_tout_help_sheet_cancel(),
        style: .cancel,
        handler: nil
      )
    )

    // iPad provision
    helpSheet.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

    self.present(helpSheet, animated: true, completion: nil)
  }

  @objc private func newsletterSwitchChanged(_ sender: UISwitch) {
    self.viewModel.sendNewslettersToggled(sender.isOn)
  }

  @objc private func createAccountButtonPressed() {
    self.viewModel.createAccountButtonPressed()
  }

  @objc private func loginButtonPressed() {
    self.viewModel.loginButtonPressed()
  }

  @objc fileprivate func newsletterLabelTapped() {
    self.helpViewModel.showHelpSheetButtonTapped()
  }

  @objc internal func mailComposeController(
    _: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult,
    error _: Error?
  ) {
    self.helpViewModel.mailComposeCompletion(result: result)
    self.dismiss(animated: true, completion: nil)
  }
}

extension FacebookConfirmationViewController: UITextViewDelegate {
  func textView(
    _: UITextView,
    shouldInteractWith _: NSTextAttachment,
    in _: NSRange,
    interaction _: UITextItemInteraction
  ) -> Bool {
    return false
  }

  func textView(
    _: UITextView, shouldInteractWith url: URL,
    in _: NSRange,
    interaction _: UITextItemInteraction
  ) -> Bool {
    self.viewModel.tapped(url)
    return false
  }
}
