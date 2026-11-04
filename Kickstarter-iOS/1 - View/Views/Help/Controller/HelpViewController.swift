import KsApi

import MessageUI
import Prelude

final class HelpViewController: UIViewController {
  @IBOutlet fileprivate var tableView: UITableView!

  private let dataSource = HelpDataSource()
  fileprivate let helpViewModel: HelpViewModel = HelpViewModel()

  internal static func instantiate() -> HelpViewController {
    return Storyboard.Settings.instantiate(HelpViewController.self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.helpViewModel.canSendEmail(MFMailComposeViewController.canSendMail())

    self.tableView.dataSource = self.dataSource
    self.tableView.delegate = self
    self.tableView.register(nib: .SettingsTableViewCell)
    self.tableView.registerHeaderFooter(nib: .SettingsHeaderView)

    self.dataSource.configureRows()

    self.tableView.reloadData()
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> settingsViewControllerStyle
      |> UIViewController.lens.title %~ { _ in Strings.profile_settings_about_title() }

    _ = self.tableView
      |> settingsTableViewStyle
      |> settingsTableViewSeparatorStyle
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.helpViewModel.onMailCompose = { [weak self] in
        let controller = MFMailComposeViewController.support()
        controller.mailComposeDelegate = self
        self?.present(controller, animated: true, completion: nil)
      }

    self.helpViewModel.onNoEmailError = { [weak self] alert in
        self?.present(alert, animated: true, completion: nil)
      }

    self.helpViewModel.onWebHelp = { [weak self] helpType in
        self?.goToHelpType(helpType)
      }
  }

  fileprivate func goToHelpType(_ helpType: HelpType) {
    let vc = HelpWebViewController.configuredWith(helpType: helpType)
    self.navigationController?.pushViewController(vc, animated: true)
  }
}

extension HelpViewController: UITableViewDelegate {
  func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
    return HelpSectionType.sectionHeaderHeight
  }

  func tableView(_: UITableView, heightForFooterInSection _: Int) -> CGFloat {
    return 0.1 // Required to remove the footer in UITableViewStyleGrouped
  }

  func tableView(_ tableView: UITableView, viewForHeaderInSection _: Int) -> UIView? {
    return tableView.dequeueReusableHeaderFooterView(withIdentifier: Nib.SettingsHeaderView.rawValue)
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)

    guard let helpType = self.dataSource.cellTypeForIndexPath(indexPath: indexPath) else {
      return
    }

    self.helpViewModel.helpTypeButtonTapped(helpType)
  }
}

extension HelpViewController: @MainActor MFMailComposeViewControllerDelegate {
  internal func mailComposeController(
    _ controller: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult,
    error _: Error?
  ) {
    self.helpViewModel.mailComposeCompletion(result: result)

    controller.dismiss(animated: true, completion: nil)
  }
}
