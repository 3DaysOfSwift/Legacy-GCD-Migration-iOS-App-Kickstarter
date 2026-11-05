import KsApi

import Prelude
import SafariServices
import WebKit

internal final class ProjectCreatorViewController: WebViewController {
  fileprivate let viewModel = ProjectCreatorViewModel()

  var isPresentedFromVideoFeed = false

  internal static func configuredWith(project: any ProjectCreatorConfiguration)
    -> ProjectCreatorViewController {
    let vc = ProjectCreatorViewController()
    vc.viewModel.configureWith(project: project)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()
    self.viewModel.viewDidLoad()

    self.navigationItem.title = Strings.project_subpages_menu_buttons_creator()

    if self.traitCollection.userInterfaceIdiom == .pad || self.isPresentedFromVideoFeed {
      self.navigationItem.leftBarButtonItem = .close(self, selector: #selector(self.closeButtonTapped))
    }
  }

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.navigationController?.setNavigationBarHidden(false, animated: animated)
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseControllerStyle()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onLogin = { [weak self] intent in
      Task { @MainActor [weak self] in self?.goToLoginTout(intent) }
    }
    self.viewModel.onLoad = { [weak self] request in
      Task { @MainActor [weak self] in _ = self?.webView.load(request) }
    }
    self.viewModel.onGoBack = { [weak self] in
      Task { @MainActor [weak self] in
        if self?.traitCollection.userInterfaceIdiom == .pad || self?.isPresentedFromVideoFeed == true {
          self?.dismiss(animated: true, completion: nil)
        } else {
          self?.navigationController?.popViewController(animated: true)
        }
      }
    }
    self.viewModel.onMessage = { [weak self] subject, context in
      Task { @MainActor [weak self] in self?.goToMessageDialog(subject: subject, context: context) }
    }
    self.viewModel.onSafari = { [weak self] url in
      Task { @MainActor [weak self] in self?.goTo(url: url) }
    }
  }

  internal func webView(
    _: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      self.viewModel.decidePolicy(
        forNavigationAction: WKNavigationActionData(navigationAction: navigationAction)
      )
    )
  }

  fileprivate func goToLoginTout(_ loginIntent: LoginIntent) {
    let vc = LoginToutViewController.configuredWith(loginIntent: loginIntent)
    let isIpad = AppEnvironment.current.device.userInterfaceIdiom == .pad
    let nav = UINavigationController(rootViewController: vc)
      |> \.modalPresentationStyle .~ (isIpad ? .formSheet : .fullScreen)

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func goToMessageDialog(subject: MessageSubject, context: KSRAnalytics.MessageDialogContext) {
    let vc = MessageDialogViewController.configuredWith(messageSubject: subject, context: context)
    vc.delegate = self
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .formSheet
    self.present(nav, animated: true, completion: nil)
  }

  @objc fileprivate func closeButtonTapped() {
    self.dismiss(animated: true, completion: nil)
  }
}

extension ProjectCreatorViewController: MessageDialogViewControllerDelegate {
  internal func messageDialogWantsDismissal(_ dialog: MessageDialogViewController) {
    dialog.dismiss(animated: true, completion: nil)
  }

  internal func messageDialog(_: MessageDialogViewController, postedMessage _: Message) {}
}
