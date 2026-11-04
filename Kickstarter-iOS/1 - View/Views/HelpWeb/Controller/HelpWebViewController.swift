import KDS

import Prelude
import UIKit

internal final class HelpWebViewController: WebViewController {
  fileprivate let viewModel = HelpWebViewModel()

  @IBOutlet private var logoImageView: UIImageView!

  internal static func configuredWith(helpType: HelpType) -> HelpWebViewController {
    let vc = Storyboard.Help.instantiate(HelpWebViewController.self)
    vc.viewModel.configureWith(helpType: helpType)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    if self.navigationController?.viewControllers.count == .some(1) {
      self.navigationItem.leftBarButtonItem = UIBarButtonItem(
        title: Strings.general_navigation_buttons_close(),
        style: .plain,
        target: self,
        action: #selector(self.closeButtonTapped)
      )
    }

    if let request = self.viewModel.requestForViewDidLoad() {
      self.webView.load(request)
    }
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self.logoImageView
      |> \.tintColor .~ Colors.Brand.logo.uiColor()
  }

  @objc fileprivate func closeButtonTapped() {
    self.dismiss(animated: true, completion: nil)
  }
}
