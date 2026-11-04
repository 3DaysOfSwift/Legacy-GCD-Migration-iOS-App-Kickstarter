import Foundation
import KsApi

import Prelude
import UIKit

internal final class FindFriendsViewController: UITableViewController {
  fileprivate let viewModel = FindFriendsViewModel()
  fileprivate let dataSource = FindFriendsDataSource()
  fileprivate let loadingIndicatorView = UIActivityIndicatorView()
  fileprivate let backgroundView = UIView()

  internal static func configuredWith(source: FriendsSource) -> FindFriendsViewController {
    let vc = Storyboard.Friends.instantiate(FindFriendsViewController.self)
    vc.viewModel.configureWith(source: source)
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.estimatedRowHeight = 100.0
    self.tableView.rowHeight = UITableView.automaticDimension

    self.tableView.backgroundView = self.backgroundView

    self.tableView.insertSubview(self.loadingIndicatorView, aboveSubview: self.backgroundView)

    self.tableView.dataSource = self.dataSource

    self.viewModel.viewDidLoad()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.navigationController?.setNavigationBarHidden(false, animated: animated)
  }

  override func bindViewModel() {
    super.bindViewModel()
    self.viewModel.onChange = { [weak self] in self?.renderState() }
    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case .followAllConfirmation(let count): self.showFollowAllConfirmationAlert(count: count)
      case .error(let error): self.present(UIAlertController.alertController(forError: error), animated: true)
      case .discovery: break
      }
    }
  }

  private func renderState() {
    if self.viewModel.showLoadingIndicator { self.loadingIndicatorView.startAnimating() }
    else { self.loadingIndicatorView.stopAnimating() }
    if let friends = self.viewModel.friends { self.dataSource.friends(friends, source: self.viewModel.source) }
    if let stats = self.viewModel.stats { self.dataSource.stats(stats: stats, source: self.viewModel.source) }
    if let visible = self.viewModel.showFacebookConnect { self.dataSource.facebookConnect(source: .findFriends, visible: visible) }
    self.tableView.reloadData()
  }

  internal override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    self.loadingIndicatorView.center = self.backgroundView.center
  }

  override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableControllerStyle()
      |> UIViewController.lens.title %~ { _ in Strings.Follow_friends() }

    _ = self.loadingIndicatorView
      |> baseActivityIndicatorStyle
  }

  override func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    if let statsCell = cell as? FindFriendsStatsCell, statsCell.delegate == nil {
      statsCell.delegate = self
    } else if let fbConnectCell = cell as? FindFriendsFacebookConnectCell, fbConnectCell.delegate == nil {
      fbConnectCell.delegate = self
    }

    self.viewModel.willDisplayRow(
      self.dataSource.itemIndexAt(indexPath),
      outOf: self.dataSource.numberOfItems()
    )
  }

  fileprivate func showFollowAllConfirmationAlert(count: Int) {
    self.present(
      UIAlertController.confirmFollowAllFriends(
        friendsCount: count,
        yesHandler: { _ in
          self.viewModel.confirmFollowAllFriends()
        },
        noHandler: { _ in }
      ),
      animated: true,
      completion: nil
    )
  }
}

extension FindFriendsViewController: FindFriendsStatsCellDelegate {
  func findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: Int) {
    self.viewModel.findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: friendCount)
  }
}

extension FindFriendsViewController: FindFriendsFacebookConnectCellDelegate {
  func findFriendsFacebookConnectCellDidFacebookConnectUser() {
    self.viewModel.findFriendsFacebookConnectCellDidFacebookConnectUser()
  }

  func findFriendsFacebookConnectCellDidDismissHeader() {}

  func findFriendsFacebookConnectCellShowErrorAlert(_ alert: AlertError) {
    self.viewModel.findFriendsFacebookConnectCellShowErrorAlert(alert)
  }
}
