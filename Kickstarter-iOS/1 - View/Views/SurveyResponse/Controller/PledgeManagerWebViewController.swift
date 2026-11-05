import KsApi

import Prelude
import UIKit
import WebKit

@MainActor
internal protocol PledgeManagerWebViewControllerDelegate: AnyObject {
  /// Called when the delegate should notify the parent that self was dismissed.
  func pledgeManagerWebViewControllerDismissed()
}

internal final class PledgeManagerWebViewController: WebViewController {
  internal weak var delegate: PledgeManagerWebViewControllerDelegate?
  private var sessionStartedObserver: MainActorNotificationObservation?
  fileprivate let viewModel = PledgeManagerWebViewModel()

  internal static func configuredWith(url: String)
    -> PledgeManagerWebViewController {
    let vc = PledgeManagerWebViewController()
    vc.viewModel.configureWith(url: url)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.navigationItem.leftBarButtonItem =
      UIBarButtonItem(
        title: Strings.general_navigation_buttons_close(),
        style: .plain,
        target: self,
        action: #selector(self.closeButtonTapped)
      )

    self.viewModel.viewDidLoad()

  }

  internal override func bindViewModel() {
    super.bindViewModel()
    self.sessionStartedObserver = MainActorNotificationObservation(name: .ksr_sessionStarted) { [weak self] _ in
      self?.viewModel.userSessionStarted()
    }
    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case .dismissViewController:
        self.navigationController?.dismiss(animated: true, completion: nil)
        self.delegate?.pledgeManagerWebViewControllerDismissed()
      case let .goToLoginSignup(intent): self.goToLoginSignup(with: intent)
      case let .goToNativeScreen(request):
        switch request {
        case let .goToProject(param, refTag): self.goToProject(param: param, refTag: refTag)
        case let .goToPledge(param): self.goToPledge(param: param)
        case let .goToUpdate(param, updateId): self.viewModel.fetchUpdateVCData(param: param, updateId: updateId)
        }
      case let .presentUpdateVC(project, update): self.goToUpdate(project: project, update: update)
      case let .webViewLoadRequest(request): self.webView.load(request)
      case let .title(title): self.title = title
      }
    }
  }

  @objc fileprivate func closeButtonTapped() {
    self.viewModel.closeButtonTapped()
  }

  internal func webView(
    _: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      self.viewModel.decidePolicyFor(
        navigationAction: WKNavigationActionData(navigationAction: navigationAction)
      )
    )
  }

  // MARK: - Handle login

  fileprivate func goToLoginSignup(with intent: LoginIntent) {
    let loginSignupViewController = LoginToutViewController.configuredWith(
      loginIntent: intent
    )
    self.presentViewController(loginSignupViewController)
  }

  // MARK: - Deeplinks

  fileprivate func goToProject(param: Param, refTag: RefTag?) {
    /// Instead of using the helper `self.presentViewController`, use the project page's preferred navigation wrapper.
    let nav = ProjectPageViewController.navigationController(
      withProjectOrParam: .right(param),
      refInfo: RefInfo(refTag)
    )

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func goToUpdate(project: Project, update: Update) {
    let vc = UpdateViewController.configuredWith(
      project: project,
      update: update,
      context: .deepLink
    )
    self.presentViewController(vc)
  }

  fileprivate func goToPledge(param: Param) {
    let vc = ManagePledgeViewController.instantiate()
    vc.configureWith(params: (param, nil))
    self.presentViewController(vc)
  }

  fileprivate func presentViewController(_ vc: UIViewController) {
    let nav = NavigationController(rootViewController: vc)
    nav.modalPresentationStyle = self.traitCollection.userInterfaceIdiom == .pad ? .fullScreen : .formSheet

    self.present(nav, animated: true, completion: nil)
  }
}
