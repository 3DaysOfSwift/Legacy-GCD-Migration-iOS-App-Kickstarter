import KsApi

import Prelude
import UIKit

internal final class ActivitiesViewController: UITableViewController {
  fileprivate let viewModel = ActivitiesViewModel()
  fileprivate let dataSource = ActivitiesDataSource()
  private var sessionEndedObserver: MainActorNotificationObservation?
  private var sessionStartedObserver: MainActorNotificationObservation?
  private var userUpdatedObserver: MainActorNotificationObservation?

  fileprivate var emptyStatesController: EmptyStatesViewController?

  internal static func instantiate() -> ActivitiesViewController {
    return Storyboard.Activity.instantiate(ActivitiesViewController.self)
  }

  private var didSetupBottomInsets = false

  internal required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)

    self.sessionStartedObserver = MainActorNotificationObservation(name: .ksr_sessionStarted) { [weak self] _ in
        self?.viewModel.userSessionStarted()
      }

    self.sessionEndedObserver = MainActorNotificationObservation(name: .ksr_sessionEnded) { [weak self] _ in
        self?.viewModel.userSessionEnded()
      }

    self.userUpdatedObserver = MainActorNotificationObservation(name: .ksr_userUpdated) { [weak self] _ in
        self?.viewModel.currentUserUpdated()
      }
  }


  internal override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    if !self.didSetupBottomInsets {
      self.didSetupBottomInsets = true

      /// Extend under the tab bar / bottom safe area
      self.tableView.contentInsetAdjustmentBehavior = .never

      let tabBarHeight = self.tabBarController?.tabBar.frame.height ?? 0
      let safeAreaBottom = self.view.safeAreaInsets.bottom
      let bottomInset = tabBarHeight + safeAreaBottom

      self.tableView.contentInset.bottom = bottomInset
      self.tableView.verticalScrollIndicatorInsets.bottom = bottomInset

      self.emptyStatesController?.additionalSafeAreaInsets = .zero
    }

    self.emptyStatesController?.view.frame = self.view.bounds
  }

  internal override func viewDidLoad() {
    super.viewDidLoad()

    self.tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: Styles.gridHalf(3)))
    self.tableView.registerCellClass(ActivityErroredBackingsCell.self)
    self.tableView.registerCellClass(RewardTrackingActivitiesCell.self)
    self.tableView.dataSource = self.dataSource

    let emptyVC = EmptyStatesViewController.configuredWith(emptyState: .activity)
    self.emptyStatesController = emptyVC
    emptyVC.delegate = self
    emptyVC.additionalSafeAreaInsets = .zero

    self.addChild(emptyVC)
    self.view.addSubview(emptyVC.view)
    emptyVC.didMove(toParent: self)

    self.viewModel.viewDidLoad()
  }

  internal override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    self.viewModel.viewWillAppear(animated: animated)
  }

  internal override func bindStyles() {
    super.bindStyles()

    _ = self
      |> baseTableControllerStyle(estimatedRowHeight: 200.0)

    _ = self.navigationItem
      |> UINavigationItem.lens.title %~ { _ in Strings.activity_navigation_title_activity() }
  }

  internal override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .activities(activities): self.dataSource.load(activities: activities); self.tableView.reloadData()
      case let .erroredBackings(backings): self.dataSource.load(erroredBackings: backings); self.tableView.reloadData()
      case .showEmptyStateIsLoggedIn:
        self.tableView.bounces = false
        if let empty = self.emptyStatesController { empty.view.isHidden = false; self.view.bringSubviewToFront(empty.view) }
      case .hideEmptyState: self.tableView.bounces = true; self.emptyStatesController?.view.isHidden = true
      case let .isRefreshing(refreshing):
        if refreshing { self.refreshControl?.beginRefreshing() } else { self.refreshControl?.endRefreshing() }
      case let .goToProject(project, refTag): self.present(project: project, refTag: refTag)
      case let .unansweredSurveys(surveys): self.dataSource.load(surveys: surveys); self.tableView.reloadData()
      case let .goToSurveyResponse(response): self.goToSurveyResponse(surveyResponse: response)
      case let .goToUpdate(project, update): self.goToUpdate(project: project, update: update)
      case let .goToManagePledge(params): self.goToManagePledge(params: params)
      case .clearBadgeValue: self.parent?.tabBarItem.badgeValue = nil
      case .updateUserInEnvironment: NotificationCenter.default.post(.init(name: .ksr_userUpdated))
      }
    }
  }

  internal override func tableView(
    _: UITableView,
    willDisplay cell: UITableViewCell,
    forRowAt indexPath: IndexPath
  ) {
    switch cell {
    case let updateCell as ActivityUpdateCell:
      updateCell.delegate = self
    case let surveyCell as ActivitySurveyResponseCell:
      surveyCell.delegate = self
    case let erroredCell as ActivityErroredBackingsCell:
      erroredCell.delegate = self
    case let trackingCell as RewardTrackingActivitiesCell:
      trackingCell.delegate = self
    default:
      break
    }

    self.viewModel.willDisplayRow(
      self.dataSource.itemIndexAt(indexPath),
      outOf: self.dataSource.numberOfItems()
    )
  }

  internal override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard let activity = self.dataSource[indexPath] as? Activity else {
      return
    }

    self.viewModel.tappedActivity(activity)
  }

  @IBAction internal func refresh() {
    self.viewModel.refresh()
  }

  fileprivate func present(project: Project, refTag: RefTag) {
    let projectParam = Either<Project, any ProjectPageParam>(left: project)
    let nav = ProjectPageViewController.navigationController(
      withProjectOrParam: projectParam,
      refInfo: RefInfo(refTag)
    )

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func goToSurveyResponse(surveyResponse: SurveyResponse) {
    let url = surveyResponse.urls.web.survey
    let vc = PledgeManagerWebViewController.configuredWith(url: url)
    vc.delegate = self

    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func goToUpdate(project: Project, update: Update) {
    let vc = UpdateViewController.configuredWith(project: project, update: update, context: .activity)
    self.navigationController?.pushViewController(vc, animated: true)
  }

  fileprivate func goToManagePledge(params: ManagePledgeViewParamConfigData) {
    let vc = ManagePledgeViewController.controller(with: params, delegate: self)
    self.present(vc, animated: true)
  }
}

// MARK: - ActivityUpdateCellDelegate

extension ActivitiesViewController: ActivityUpdateCellDelegate {
  internal func activityUpdateCellTappedProjectImage(activity: Activity) {
    self.viewModel.activityUpdateCellTappedProjectImage(activity: activity)
  }
}

// MARK: - ActivitySurveyResponseCellDelegate

extension ActivitiesViewController: ActivitySurveyResponseCellDelegate {
  func activityTappedRespondNow(forSurveyResponse surveyResponse: SurveyResponse) {
    self.viewModel.tappedRespondNow(forSurveyResponse: surveyResponse)
  }
}

// MARK: - EmptyStatesViewControllerDelegate

extension ActivitiesViewController: EmptyStatesViewControllerDelegate {
  func emptyStatesViewController(
    _: EmptyStatesViewController,
    goToDiscoveryWithParams params: DiscoveryParams?
  ) {
    guard let tabController = self.tabBarController as? RootTabBarViewController else { return }
    tabController.switchToDiscovery(params: params)
  }

  func emptyStatesViewControllerGoToFriends() {}
}

extension ActivitiesViewController: PledgeManagerWebViewControllerDelegate {
  func pledgeManagerWebViewControllerDismissed() {
    self.viewModel.surveyResponseViewControllerDismissed()
  }
}

extension ActivitiesViewController: TabBarControllerScrollable {}

// MARK: - ErroredBackingViewDelegate

extension ActivitiesViewController: ErroredBackingViewDelegate {
  func erroredBackingViewDidTapManage(_: ErroredBackingView, backing: ProjectAndBackingEnvelope) {
    self.viewModel.erroredBackingViewDidTapManage(with: backing)
  }
}

// MARK: - ManagePledgeViewControllerDelegate

extension ActivitiesViewController: ManagePledgeViewControllerDelegate {
  func managePledgeViewController(
    _: ManagePledgeViewController,
    managePledgeViewControllerFinishedWithMessage _: String?
  ) {
    self.viewModel.managePledgeViewControllerDidFinish()
  }

  func managePledgeViewControllerDidDismiss(_: ManagePledgeViewController) {}
}

// MARK: - RewardTrackingDetailsViewDelegate

extension ActivitiesViewController: RewardTrackingDetailsViewDelegate {
  func didTapTrackingButton(with trackingURL: URL) {
    self.goTo(url: trackingURL)
  }
}
