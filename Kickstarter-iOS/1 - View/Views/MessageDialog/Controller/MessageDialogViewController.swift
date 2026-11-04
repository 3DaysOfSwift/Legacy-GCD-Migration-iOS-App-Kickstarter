import KDS
import KsApi

import Prelude
import UIKit

@MainActor
internal protocol MessageDialogViewControllerDelegate: AnyObject {
  func messageDialogWantsDismissal(_ dialog: MessageDialogViewController)
  func messageDialog(_ dialog: MessageDialogViewController, postedMessage: Message)
}

internal final class MessageDialogViewController: UIViewController {
  private var keyboardObservation: Keyboard.Observation?
  fileprivate let viewModel = MessageDialogViewModel()
  internal weak var delegate: MessageDialogViewControllerDelegate?

  @IBOutlet private var bodyTextView: UITextView!
  @IBOutlet private var bottomConstraint: NSLayoutConstraint!
  @IBOutlet private var cancelButton: UIBarButtonItem!
  @IBOutlet private var loadingView: UIView!
  @IBOutlet private var nameLabel: UILabel!
  @IBOutlet private var postButton: UIBarButtonItem!

  internal static func configuredWith(
    messageSubject: MessageSubject,
    context: KSRAnalytics.MessageDialogContext
  ) -> MessageDialogViewController {
    let vc = Storyboard.Messages.instantiate(MessageDialogViewController.self)
    vc.viewModel.configureWith(messageSubject: messageSubject, context: context)
    vc.modalPresentationStyle = .formSheet
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.viewModel.viewDidLoad()
  }

  internal override func bindViewModel() {
    self.viewModel.onRecipient = { [weak self] in self?.nameLabel.text = $0 }
    self.viewModel.onPostEnabled = { [weak self] in self?.postButton.isEnabled = $0 }
    self.viewModel.onLoadingHidden = { [weak self] in self?.loadingView.isHidden = $0 }
    self.viewModel.onKeyboardVisibility = { [weak self] visible in
      guard let textView = self?.bodyTextView else { return }
      if visible { textView.becomeFirstResponder() } else { textView.resignFirstResponder() }
    }
    self.keyboardObservation = Keyboard.observe { [weak self] change in
      guard let self else { return }
      self.bottomConstraint.constant = self.view.frame.height - change.frame.minY
    }
    self.viewModel.onDismiss = { [weak self] in
      guard let self else { return }
      self.delegate?.messageDialogWantsDismissal(self)
    }
    self.viewModel.onPosted = { [weak self] message in
      guard let self else { return }
      self.postNotification()
      self.delegate?.messageDialog(self, postedMessage: message)
    }
    self.viewModel.onError = { [weak self] in self?.presentError($0) }
  }

  internal override func bindStyles() {
    super.bindStyles()

    self.view.backgroundColor = Colors.Background.Surface.primary.uiColor()
    self.loadingView.backgroundColor = Colors.Background.Surface.primary.uiColor(opacity: 0.8)

    _ = self.cancelButton
      |> UIBarButtonItem.lens.title %~ { _ in Strings.general_navigation_buttons_cancel() }

    _ = self.nameLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_body().bolded

    _ = self.postButton
      |> UIBarButtonItem.lens.title %~ { _ in Strings.social_buttons_send() }

    applyBodyTextViewStyle(self.bodyTextView)
  }

  @IBAction fileprivate func cancelButtonPressed() {
    self.viewModel.cancelButtonPressed()
  }

  @IBAction fileprivate func postButtonPressed() {
    self.viewModel.postButtonPressed()
  }

  fileprivate func presentError(_ message: String) {
    self.present(
      UIAlertController.genericError(message),
      animated: true,
      completion: nil
    )
  }

  private func postNotification() {
    NotificationCenter.default.post(
      name: Notification.Name.ksr_showNotificationsDialog,
      object: nil,
      userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.message]
    )
  }
}

extension MessageDialogViewController: UITextViewDelegate {
  internal func textViewDidChange(_ textView: UITextView) {
    self.viewModel.bodyTextChanged(textView.text)
  }
}

@MainActor
private func applyBodyTextViewStyle(_ textView: UITextView) {
  textView.font = .ksr_body()
  textView.backgroundColor = Colors.Background.Surface.primary.uiColor()
}
