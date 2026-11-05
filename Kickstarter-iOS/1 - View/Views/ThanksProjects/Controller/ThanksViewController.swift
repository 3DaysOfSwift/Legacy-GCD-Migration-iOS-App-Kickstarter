import KDS
import KsApi

import Prelude
import StoreKit
import UIKit

internal final class ThanksViewController: UIViewController, UITableViewDelegate {
  @IBOutlet fileprivate var shareMoreButton: UIButton!
  @IBOutlet fileprivate var projectsTableView: UITableView!
  @IBOutlet fileprivate var backedLabel: UILabel!
  @IBOutlet fileprivate var recommendationsLabel: UILabel!
  @IBOutlet fileprivate var separatorView: UIView!
  @IBOutlet fileprivate var thankYouLabel: UILabel!
  @IBOutlet fileprivate var headerView: UIView!

  fileprivate let viewModel = ThanksViewModel()
  fileprivate let shareViewModel = ShareViewModel()
  fileprivate let dataSource = ThanksProjectsDataSource()

  internal static func configured(with data: ThanksPageData) -> ThanksViewController {
    let vc = Storyboard.Thanks.instantiate(ThanksViewController.self)
    vc.viewModel.configure(with: data)
    vc.shareViewModel.configureWith(shareContext: .thanks(data.project), shareContextView: nil)
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.view.backgroundColor = Colors.Background.Surface.primary.uiColor()

    self.projectsTableView.register(nib: .DiscoveryPostcardCell)
    self.projectsTableView.register(nib: .ThanksCategoryCell)
    self.projectsTableView.registerCellClass(DiscoveryProjectCardCell.self)

    self.projectsTableView.dataSource = self.dataSource
    self.projectsTableView.delegate = self

    self.setupNavigationItem()

    self.viewModel.viewDidLoad()
  }

  private func setupNavigationItem() {
    let icon = Kickstarter_iOS.image(named: "icon--cross")?
      .withRenderingMode(.alwaysTemplate)

    let closeButton = UIBarButtonItem(
      image: icon,
      style: .plain,
      target: self,
      action: #selector(self.closeButtonTapped)
    )

    // Force the icon to be our light/dark icon color, not the system tint color
    closeButton.tintColor = Colors.Icon.primary.uiColor()

    closeButton.accessibilityLabel = Strings.Dismiss()

    self.navigationItem.leftBarButtonItem = closeButton

    self.configureNavigationBarForPledgeFlow()

    // Make the nav bar look seamless until you scroll.
    // The seamless look matches how this page used to be designed when it didn't use a navigation bar.
    let scrollEdgeHiddenAppearance = UINavigationBarAppearance()
    scrollEdgeHiddenAppearance.configureForPledgeFlow()
    scrollEdgeHiddenAppearance.shadowColor = nil
    self.navigationItem.scrollEdgeAppearance = scrollEdgeHiddenAppearance

    // We don't show a title on this page.
    let emptyTitleView = UIView()
    self.navigationItem.titleView = emptyTitleView
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    if let headerView = projectsTableView.tableHeaderView {
      let height = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
      self.updateHeaderView(height: height)
    }
  }

  override func bindStyles() {
    super.bindStyles()

    self.view.backgroundColor = Colors.Background.Surface.primary.uiColor()

    _ = self.projectsTableView
      |> UITableView.lens.separatorStyle .~ .none
      |> UITableView.lens.rowHeight .~ UITableView.automaticDimension
      |> UITableView.lens.estimatedRowHeight .~ 550

    _ = self.thankYouLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ UIFont.ksr_title1(size: 36)
      |> UILabel.lens.text %~ { _ in Strings.Thank_you_exclamation() }
      |> UILabel.lens.isAccessibilityElement .~ false

    _ = self.backedLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()

    _ = self.separatorView
      |> UIView.lens.backgroundColor .~ LegacyColors.ksr_support_700.uiColor()

    _ = self.recommendationsLabel
      |> UILabel.lens.textColor .~ LegacyColors.ksr_support_700.uiColor()
      |> UILabel.lens.font .~ .ksr_subhead()
      |> UILabel.lens.text %~ { _ in Strings.Other_projects_you_might_like() }

    self.shareMoreButton.applyStyleConfiguration(KSRButtonLegacyStyle.grey)
    _ = self.shareMoreButton
      |> UIButton.lens.targets .~ [(self, #selector(self.shareMoreButtonTapped), .touchUpInside)]
      |> UIButton.lens.title(for: .normal) %~ { _ in
        Strings.project_accessibility_button_share_label()
      }
  }

  override func bindViewModel() {
    super.bindViewModel()

    self.viewModel.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .backedProjectText(text): self.backedLabel.attributedText = text
      case let .postProjectBackedNotification(notification): NotificationCenter.default.post(notification)
      case let .goToDiscovery(params): self.goToDiscovery(params: params)
      case let .goToProject(project, projects, refTag): self.goToProject(project, projects: projects, refTag: refTag)
      case .postContextualNotification:
        NotificationCenter.default.post(Notification(name: .ksr_showNotificationsDialog, userInfo: [
          UserInfoKeys.context: PushNotificationDialog.Context.pledge,
          UserInfoKeys.viewController: self
        ]))
      case .showRatingAlert: self.showRatingAlert()
      case .showGamesNewsletterAlert: self.showGamesNewsletterAlert()
      case let .showGamesNewsletterOptInAlert(title): self.showGamesNewsletterOptInAlert(title: title)
      case .updateUserInEnvironment: self.viewModel.userUpdated()
      case let .postUserUpdatedNotification(notification): NotificationCenter.default.post(notification)
      case let .showRecommendations(projects, category):
        self.dataSource.loadData(projects: projects, category: category)
        self.projectsTableView.reloadData()
      }
    }

    self.shareViewModel.onShareSheet = { [weak self] controller, _ in self?.showShareSheet(controller) }
  }

  private func updateHeaderView(height: CGFloat) {
    var headerFrame = self.headerView.frame
    guard height != headerFrame.size.height else { return }

    headerFrame.size.height = height
    self.headerView.frame = headerFrame
    self.projectsTableView.tableHeaderView = self.headerView
  }

  fileprivate func goToDiscovery(params: DiscoveryParams) {
    self.view.window?.rootViewController
      .flatMap { $0 as? RootTabBarViewController }
      .doIfSome { $0.switchToDiscovery(params: params) }

    self.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
  }

  fileprivate func goToAppStore(link: String) {
    guard let url = URL(string: link) else { return }
    UIApplication.shared.open(url)
  }

  fileprivate func goToProject(_ project: Project, projects _: [Project], refTag: RefTag) {
    let projectParam = Either<Project, any ProjectPageParam>(left: project)
    let nav = ProjectPageViewController.navigationController(
      withProjectOrParam: projectParam,
      refInfo: RefInfo(refTag)
    )

    self.present(nav, animated: true, completion: nil)
  }

  fileprivate func showRatingAlert() {
    if let scene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
      SKStoreReviewController.requestReview(in: scene)
    }
  }

  fileprivate func showGamesNewsletterAlert() {
    self.present(
      UIAlertController.games(
        subscribeHandler: { [weak self] _ in
          self?.viewModel.gamesNewsletterSignupButtonTapped()
        }
      ),
      animated: true,
      completion: nil
    )
  }

  fileprivate func showGamesNewsletterOptInAlert(title: String) {
    self.present(
      UIAlertController.newsletterOptIn(title),
      animated: true,
      completion: nil
    )
  }

  fileprivate func showShareSheet(_ controller: UIActivityViewController) {
    if UIDevice.current.userInterfaceIdiom == .pad {
      controller.modalPresentationStyle = .popover
      let popover = controller.popoverPresentationController
      popover?.sourceView = self.shareMoreButton
    }

    self.present(controller, animated: true, completion: nil)
  }

  internal func tableView(
    _: UITableView, willDisplay cell: UITableViewCell,
    forRowAt _: IndexPath
  ) {
    if let cell = cell as? ThanksCategoryCell {
      cell.delegate = self
    }
  }

  internal func tableView(
    _: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    if let project = self.dataSource.projectAtIndexPath(indexPath) {
      self.viewModel.projectTapped(project)
    }
  }

  @objc fileprivate func shareMoreButtonTapped() {
    self.shareViewModel.shareButtonTapped()
  }

  @objc fileprivate func closeButtonTapped() {
    self.viewModel.closeButtonTapped()
  }
}

extension ThanksViewController: ThanksCategoryCellDelegate {
  func thanksCategoryCell(_: ThanksCategoryCell, didTapSeeAllProjectsWith category: KsApi.Category) {
    self.viewModel.categoryCellTapped(category)
  }
}
