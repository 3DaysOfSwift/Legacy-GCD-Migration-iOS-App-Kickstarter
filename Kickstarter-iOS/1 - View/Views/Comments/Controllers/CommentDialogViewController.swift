import KDS
import KsApi

import Prelude
import UIKit

internal protocol CommentDialogDelegate: AnyObject {
  func commentDialogWantsDismissal(_ dialog: CommentDialogViewController)
  func commentDialog(_ dialog: CommentDialogViewController, postedComment: Comment)
}

internal final class CommentDialogViewController: UIViewController {
  private var keyboardObservation: Keyboard.Observation?
  fileprivate let viewModel = CommentDialogViewModel()
  internal weak var delegate: CommentDialogDelegate?

  @IBOutlet fileprivate var bottomConstraint: NSLayoutConstraint!
  @IBOutlet fileprivate var cancelButton: UIBarButtonItem!
  @IBOutlet fileprivate var titleLabel: UILabel!
  @IBOutlet fileprivate var subtitleLabel: UILabel!
  @IBOutlet fileprivate var bodyTextView: UITextView!
  @IBOutlet fileprivate var postButton: UIBarButtonItem!
  @IBOutlet fileprivate var loadingView: UIView!

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.viewModel.viewWillAppear()
  }

  internal override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    self.viewModel.viewWillDisappear()
  }

  internal static func configuredWith(
    project: Project, update: Update?, recipient: ActivityCommentAuthor?,
    context: KSRAnalytics.CommentDialogContext
  ) -> CommentDialogViewController {
    let vc = Storyboard.CommentsDialog.instantiate(CommentDialogViewController.self)
    vc.viewModel.configureWith(
      project: project, update: update, recipientName: recipient?.name,
      context: context
    )
    return vc
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseControllerStyle()

    _ = self.postButton
      |> UIBarButtonItem.lens.title %~ { _ in Strings.social_buttons_post() }

    _ = self.titleLabel
      |> UILabel.lens.text %~ { _ in Strings.Public_comment() }

    _ = self.cancelButton
      |> UIBarButtonItem.lens.title %~ { _ in
        Strings.dashboard_post_update_compose_attachment_buttons_cancel()
      }

    _ = self.bodyTextView
      |> UITextView.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UITextView.lens.font .~ .ksr_body()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .body(text): self.bodyTextView.text = text
      case let .postEnabled(enabled): self.postButton.isEnabled = enabled
      case let .loadingHidden(hidden): self.loadingView.isHidden = hidden
      case let .posted(comment): self.commentPostedSuccessfully(comment)
      case .dismiss: self.notifyPresenterOfDismissal()
      case let .subtitle(text): self.subtitleLabel.text = text
      case let .keyboard(show):
        _ = show ? self.bodyTextView.becomeFirstResponder() : self.bodyTextView.resignFirstResponder()
      case let .error(message): self.presentError(message)
      }
    }

    self.keyboardObservation = Keyboard.observe { [weak self] in self?.animateTextViewConstraint($0) }
  }

  @IBAction internal func cancelButtonPressed() {
    self.viewModel.cancelButtonPressed()
  }

  @IBAction internal func postButtonPressed() {
    self.viewModel.postButtonPressed()
  }

  fileprivate func notifyPresenterOfDismissal() {
    self.delegate?.commentDialogWantsDismissal(self)
  }

  fileprivate func commentPostedSuccessfully(_ comment: Comment) {
    self.delegate?.commentDialog(self, postedComment: comment)
  }

  fileprivate func animateTextViewConstraint(_ change: Keyboard.Change) {
    UIView.animate(withDuration: change.duration, delay: 0.0, options: change.options, animations: {
      self.bottomConstraint.constant = -(change.frame.height + Styles.grid(2))
    }, completion: nil)
  }

  fileprivate func presentError(_ message: String) {
    self.present(
      UIAlertController.genericError(message),
      animated: true,
      completion: nil
    )
  }
}

extension CommentDialogViewController: UITextViewDelegate {
  internal func textViewDidChange(_ textView: UITextView) {
    self.viewModel.commentBodyChanged(textView.text)
  }
}
