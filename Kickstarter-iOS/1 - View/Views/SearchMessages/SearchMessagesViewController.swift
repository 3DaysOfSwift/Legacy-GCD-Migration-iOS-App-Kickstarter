import Observation
import KsApi

import UIKit

internal final class SearchMessagesViewController: UITableViewController {
  fileprivate let viewModel = MessagesSearchViewModel()
  fileprivate let dataSource = SearchMessagesDataSource()

  @IBOutlet fileprivate var searchTextField: UITextField!
  @IBOutlet fileprivate var loadingView: UIActivityIndicatorView!

  internal func configureWith(project: Project?) {
    self.viewModel.configureWith(project: project)
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.estimatedRowHeight = 120.0
    self.tableView.rowHeight = UITableView.automaticDimension
    self.tableView.dataSource = self.dataSource

    self.viewModel.viewDidLoad()
  }

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.viewModel.viewWillAppear()
    self.searchTextField.becomeFirstResponder()
  }

  internal override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    self.viewModel.viewWillDisappear()
    self.searchTextField.resignFirstResponder()
  }

  internal override func bindViewModel() {
    self.viewModel.onMessageThread = { [weak self] in self?.goTo(messageThread: $0) }
    self.observeSearching()
    self.observeThreads()
  }

  private func observeSearching() {
    withObservationTracking {
      if self.viewModel.isSearching { self.loadingView.startAnimating() }
      else { self.loadingView.stopAnimating() }
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSearching() }
    }
  }

  private func observeThreads() {
    withObservationTracking {
      self.dataSource.load(messageThreads: self.viewModel.messageThreads)
      self.tableView.reloadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeThreads() }
    }
  }

  internal override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    if let messageThread = self.dataSource[indexPath] as? MessageThread {
      self.viewModel.tappedMessageThread(messageThread)
    }
  }

  fileprivate func goTo(messageThread: MessageThread) {
    let vc = MessagesViewController.configuredWith(messageThread: messageThread)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  @IBAction fileprivate func searchTextChanged(_ textField: UITextField) {
    self.viewModel.searchTextChanged(textField.text)
  }
}

extension SearchMessagesViewController: UITextFieldDelegate {
  internal func textFieldShouldClear(_: UITextField) -> Bool {
    self.viewModel.clearSearchText()
    return true
  }
}
