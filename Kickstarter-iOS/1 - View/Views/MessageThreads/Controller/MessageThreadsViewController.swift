import Observation
import KDS
import KsApi

import Prelude
import UIKit

internal final class MessageThreadsViewController: UITableViewController {
  fileprivate let viewModel = MessageThreadsViewModel()
  fileprivate let dataSource = MessageThreadsDataSource()

  @IBOutlet fileprivate var footerView: UIView!
  @IBOutlet fileprivate var mailboxLabel: UILabel!

  internal static func configuredWith(project: Project?, refTag: RefTag?) -> MessageThreadsViewController {
    let vc = Storyboard.Messages.instantiate(MessageThreadsViewController.self)
    vc.viewModel.configureWith(project: project, refTag: refTag)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.rowHeight = UITableView.automaticDimension
    self.tableView.estimatedRowHeight = 100.0
    self.tableView.dataSource = self.dataSource

    self.viewModel.viewDidLoad()
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self |> baseTableControllerStyle()

    _ = self.mailboxLabel
      |> UILabel.lens.font .~ UIFont.ksr_callout().bolded
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onMailboxChooser = { [weak self] in self?.showMailboxChooserActionSheet() }
    self.viewModel.onSearch = { [weak self] in self?.goToSearch() }
    self.observeState()
    self.observeThreads()
  }

  private func observeState() {
    withObservationTracking {
      self.mailboxLabel.text = self.viewModel.mailboxName
      self.navigationItem.title = self.viewModel.mailboxName
      if !self.viewModel.isRefreshing { self.refreshControl?.endRefreshing() }
      self.tableView.tableFooterView?.isHidden = self.viewModel.loadingFooterIsHidden
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeState() }
    }
  }

  private func observeThreads() {
    withObservationTracking {
      self.dataSource.load(messageThreads: self.viewModel.messageThreads)
      self.dataSource.emptyState(isVisible: self.viewModel.emptyStateIsVisible)
      self.tableView.reloadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeThreads() }
    }
  }

  internal override func tableView(
    _: UITableView,
    willDisplay _: UITableViewCell,
    forRowAt indexPath: IndexPath
  ) {
    self.viewModel.willDisplayRow(
      self.dataSource.itemIndexAt(indexPath),
      outOf: self.dataSource.numberOfItems()
    )
  }

  internal override func tableView(
    _: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    if let messageThread = self.dataSource[indexPath] as? MessageThread {
      let vc = MessagesViewController.configuredWith(messageThread: messageThread)

      vc.dismissedAfterBlockingUserHandler = { [weak self] in
        self?.viewModel.refresh()
      }

      self.navigationController?.pushViewController(vc, animated: true)
    }
  }

  fileprivate func showMailboxChooserActionSheet() {
    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    alert.addAction(
      UIAlertAction(title: Strings.messages_navigation_inbox(), style: .default) { [weak self] _ in
        self?.viewModel.switchTo(mailbox: .inbox)
      }
    )

    alert.addAction(
      UIAlertAction(title: Strings.messages_navigation_sent(), style: .default) { [weak self] _ in
        self?.viewModel.switchTo(mailbox: .sent)
      }
    )

    alert.addAction(
      UIAlertAction(title: Strings.general_navigation_buttons_cancel(), style: .cancel, handler: nil)
    )

    if self.traitCollection.userInterfaceIdiom == .pad {
      alert.modalPresentationStyle = .popover
      let popover = alert.popoverPresentationController
      popover?.sourceView = self.mailboxLabel
      popover?.sourceRect = self.mailboxLabel.bounds
    }

    self.present(alert, animated: true, completion: nil)
  }

  @IBAction fileprivate func mailboxButtonPressed() {
    self.viewModel.mailboxButtonPressed()
  }

  @IBAction fileprivate func searchButtonPressed() {
    self.viewModel.searchButtonPressed()
  }

  @IBAction fileprivate func refresh() {
    self.viewModel.refresh()
  }

  fileprivate func goToSearch() {
    guard let vc = self.storyboard?.instantiateViewController(withIdentifier: "SearchMessagesViewController"),
          let search = vc as? SearchMessagesViewController else {
      fatalError("Could not instantiate SearchMessagesViewController.")
    }

    self.navigationController?.pushViewController(search, animated: true)
  }
}
