import KDS
import KsApi

import Prelude
import UIKit

internal final class BackerDashboardProjectsViewController: UITableViewController {
  private var userUpdatedObserver: MainActorNotificationObservation?
  fileprivate let viewModel: BackerDashboardProjectsViewModel = BackerDashboardProjectsViewModel()
  fileprivate let dataSource = BackerDashboardProjectsDataSource()

  private let nextPageLoadingIndicator = UIActivityIndicatorView()

  internal static func configuredWith(projectsType: ProfileProjectsType)
    -> BackerDashboardProjectsViewController {
    let vc = BackerDashboardProjectsViewController()
    vc.viewModel.configureWith(projectsType: projectsType)
    return vc
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.dataSource = self.dataSource

    let refreshControl = UIRefreshControl()
    refreshControl.addTarget(self, action: #selector(self.refresh), for: .valueChanged)
    self.refreshControl = refreshControl

    self.nextPageLoadingIndicator.hidesWhenStopped = true
    // The large style looks almost like the UIRefreshControl spinner.
    self.nextPageLoadingIndicator.style = .large
    self.nextPageLoadingIndicator.color = Colors.Icon.primary.uiColor()
    // Set the height of the loading indicator view to include padding.
    self.nextPageLoadingIndicator.frame = CGRect(x: 0, y: 0, width: 0, height: Spacing.unit_20)

    self.tableView.register(nib: .BackerDashboardEmptyStateCell)
    self.tableView.registerCellClass(BackerDashboardProjectCell.self)

    self.tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: Styles.grid(2)))

    self.userUpdatedObserver = MainActorNotificationObservation(name: .ksr_userUpdated) { [weak self] _ in
        self?.viewModel.currentUserUpdated()
      }

    self.viewModel.viewDidLoad()
  }


  internal override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // The refresh control needs to be on screen when we call beginRefreshing, or else it won't show the spinner.
    // So this is all done on didAppear instead of willAppear.
    self.viewModel.viewDidAppear(animated)
  }

  internal override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    // Refresh control is sensitive to lifecycle methods - see https://stackoverflow.com/questions/24341192/uirefreshcontrol-stuck-after-switching-tabs-in-uitabbarcontroller.
    // This fixes this issue.
    self.refreshControl?.endRefreshing()
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onRefreshing = { [weak self] refreshing in
      if refreshing { self?.refreshControl?.beginRefreshing() } else { self?.refreshControl?.endRefreshing() }
    }
    self.viewModel.onLoadingNextPage = { [weak self] loading in
      guard let self else { return }
      if loading {
        self.nextPageLoadingIndicator.startAnimating()
        self.tableView.tableFooterView = self.nextPageLoadingIndicator
      } else {
        self.nextPageLoadingIndicator.stopAnimating()
        self.tableView.tableFooterView = nil
      }
    }
    self.viewModel.onEmptyState = { [weak self] visible, type in
      self?.dataSource.emptyState(visible: visible, projectsType: type)
      self?.tableView.reloadData()
    }
    self.viewModel.onProjects = { [weak self] projects in
      self?.dataSource.load(projects: projects)
      self?.tableView.reloadData()
    }
    self.viewModel.onProject = { [weak self] project, refTag in self?.goTo(project: project, refTag: refTag) }
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableControllerStyle()
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

  internal override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard let projectCellModel = self.dataSource[indexPath] as? ProjectCardPropertiesProjectCellModel else {
      return
    }

    self.viewModel.projectTapped(projectCellModel.properties)
  }

  private func goTo(project: ProjectCardProperties, refTag: RefTag) {
    let projectParam = Either<Project, any ProjectPageParam>(right: project.projectPageParam)
    let nav = ProjectPageViewController.navigationController(
      withProjectOrParam: projectParam,
      refInfo: RefInfo(refTag)
    )

    self.present(nav, animated: true, completion: nil)
  }

  @objc private func refresh() {
    self.viewModel.refresh()
  }
}
