import Foundation
import KsApi

import MessageUI
import Prelude
import SafariServices
import WebKit

internal final class ProjectUpdatesViewController: WebViewController {
  fileprivate let viewModel = ProjectUpdatesViewModel()
  fileprivate let activityIndicator = UIActivityIndicatorView()
  internal static func configuredWith(project: Project) -> ProjectUpdatesViewController {
    let vc = ProjectUpdatesViewController()
    vc.viewModel.configureWith(project: project)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()
    self.viewModel.canSendEmail(MFMailComposeViewController.canSendMail())
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(self.activityIndicator)
    NSLayoutConstraint.activate([
      self.activityIndicator.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      self.activityIndicator.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
    ])
    self.viewModel.viewDidLoad()
  }

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.navigationController?.setNavigationBarHidden(false, animated: animated)
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self |> baseControllerStyle()
    _ = self.activityIndicator
      |> baseActivityIndicatorStyle
      |> UIActivityIndicatorView.lens.animating .~ true

    self.navigationItem.title = Strings.project_menu_buttons_updates()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onSafari = { [weak self] in self?.goTo(url: $0) }
    self.viewModel.onPhone = { [weak self] in self?.call(number: $0) }
    self.viewModel.onMail = { [weak self] in self?.openMailComposer(recipient: $0) }
    self.viewModel.onNoEmail = { [weak self] in self?.present($0, animated: true) }
    self.viewModel.onUpdate = { [weak self] in self?.goToUpdate(forProject: $0, update: $1) }
    self.viewModel.onComments = { [weak self] in self?.goToComments(forUpdate: $0) }
    self.viewModel.onLoadRequest = { [weak self] in _ = self?.webView.load($0) }
    self.viewModel.onActivityHidden = { [weak self] in self?.activityIndicator.isHidden = $0 }
  }

  fileprivate func goToComments(forUpdate update: Update) {
    let vc = commentsViewController(update: update)
    if self.traitCollection.userInterfaceIdiom == .pad {
      let nav = UINavigationController(rootViewController: vc)
      nav.modalPresentationStyle = UIModalPresentationStyle.pageSheet
      self.present(nav, animated: true, completion: nil)
    } else {
      self.navigationController?.pushViewController(vc, animated: true)
    }
  }

  fileprivate func goToUpdate(forProject project: Project, update: Update) {
    let vc = UpdateViewController.configuredWith(project: project, update: update, context: .updates)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  fileprivate func openMailComposer(recipient: String) {
    guard MFMailComposeViewController.canSendMail() else { return }

    let controller = MFMailComposeViewController()
    controller.setToRecipients([recipient])
    controller.mailComposeDelegate = self
    self.present(controller, animated: true, completion: nil)
  }

  fileprivate func call(number url: URL) {
    UIApplication.shared.open(url)
  }

  internal func webView(
    _: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      self.viewModel.decidePolicy(
        forNavigationAction: .init(navigationAction: navigationAction)
      )
    )
  }

  func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
    self.viewModel.webViewDidStartProvisionalNavigation()
  }

  func webView(_: WKWebView, didFinish _: WKNavigation!) {
    self.viewModel.webViewDidFinishNavigation()
  }
}

extension ProjectUpdatesViewController: @MainActor MFMailComposeViewControllerDelegate {
  internal func mailComposeController(
    _ controller: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult,
    error _: Error?
  ) {
    self.viewModel.mailComposeCompletion(result: result)
    controller.dismiss(animated: true, completion: nil)
  }
}
