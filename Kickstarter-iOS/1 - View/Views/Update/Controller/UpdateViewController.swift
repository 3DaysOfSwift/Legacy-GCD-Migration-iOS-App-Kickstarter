import KsApi

import Prelude
import SafariServices
import UIKit
import WebKit

internal final class UpdateViewController: WebViewController {
  fileprivate let viewModel: UpdateViewModel = UpdateViewModel()
  fileprivate let shareViewModel = ShareViewModel()

  fileprivate let closeButton = UIBarButtonItem()

  @IBOutlet fileprivate var shareButton: UIBarButtonItem!

  internal static func configuredWith(project: Project, update: Update, context _: KSRAnalytics.UpdateContext)
    -> UpdateViewController {
    let vc = Storyboard.Update.instantiate(UpdateViewController.self)
    vc.viewModel.configureWith(project: project, update: update)
    vc.shareViewModel.configureWith(shareContext: .update(project, update), shareContextView: nil)

    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()
    self.viewModel.viewDidLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    self.navigationController?.setNavigationBarHidden(false, animated: animated)

    guard
      self.presentingViewController != nil,
      let navigationController = self.navigationController, navigationController.viewControllers == [self]
    else { return }

    self.navigationItem.leftBarButtonItem = self.closeButton
  }

  internal override func bindStyles() {
    _ = self |> baseControllerStyle()

    _ = self.closeButton |> closeBarButtonItemStyle
      |> UIBarButtonItem.lens.targetAction .~ (self, #selector(self.dismissSelf))

    _ = self.shareButton
      |> UIBarButtonItem.lens.accessibilityLabel %~ { _ in Strings.Share_update() }
  }

  internal override func bindViewModel() {
    self.viewModel.onTitle = { [weak self] in self?.navigationItem.title = $0 }
    self.viewModel.onLoadRequest = { [weak self] in _ = self?.webView.load($0) }
    self.viewModel.onComments = { [weak self] in self?.goToComments(forUpdate: $0) }
    self.viewModel.onProject = { [weak self] project, refTag in self?.goTo(project: project, refTag: refTag) }
    self.viewModel.onSafari = { [weak self] in self?.goTo(url: $0) }
  }

  internal func webView(
    _: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      self.viewModel.decidePolicyFor(navigationAction: .init(navigationAction: navigationAction))
    )
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

  fileprivate func goTo(project: Project, refTag: RefTag) {
    let projectParam = Either<Project, any ProjectPageParam>(left: project)
    let vc = ProjectPageViewController.configuredWith(
      projectOrParam: projectParam,
      refInfo: RefInfo(refTag)
    )

    let nav = NavigationController(rootViewController: vc)
    nav.modalPresentationStyle = self.traitCollection.userInterfaceIdiom == .pad ? .fullScreen : .formSheet

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func showShareSheet(_ controller: UIActivityViewController) {
    if UIDevice.current.userInterfaceIdiom == .pad {
      controller.modalPresentationStyle = .popover
      let popover = controller.popoverPresentationController
      popover?.permittedArrowDirections = .any
      popover?.barButtonItem = self.navigationItem.rightBarButtonItem
    }

    self.present(controller, animated: true, completion: nil)
  }

  @IBAction fileprivate func shareButtonTapped() {
    self.shareViewModel.shareButtonTapped()
  }

  @objc fileprivate func dismissSelf() {
    self.presentingViewController?.dismiss(animated: true, completion: nil)
  }
}
