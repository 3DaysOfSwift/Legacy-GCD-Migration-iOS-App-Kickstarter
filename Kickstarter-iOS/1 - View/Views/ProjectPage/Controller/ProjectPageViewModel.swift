import Experimentation
import Foundation
import GraphAPI
import KsApi
import Prelude
import ServerDrivenUI
import UIKit

public enum ProjectPageContentView: Equatable {
  case tableView
  case richTextView([RichTextElement])

  public static func == (lhs: ProjectPageContentView, rhs: ProjectPageContentView) -> Bool {
    switch (lhs, rhs) {
    case (.tableView, .tableView):
      return true
    case let (.richTextView(leftRichText), .richTextView(rightRichText)):
      return leftRichText == rightRichText
    default:
      return false
    }
  }
}

public protocol ProjectPageParam {
  var param: Param { get }
  var initialProject: (any ProjectPamphletMainCellConfiguration)? { get }
}

public struct ProjectPageParamBox: ProjectPageParam {
  public let param: Param
  public let initialProject: (any ProjectPamphletMainCellConfiguration)?

  public init(param: Param, initialProject: (any ProjectPamphletMainCellConfiguration)?) {
    self.param = param
    self.initialProject = initialProject
  }
}

extension Param: ProjectPageParam {
  public var param: Param { self }
  public var initialProject: (any ProjectPamphletMainCellConfiguration)? { nil }
}

@MainActor
public protocol ProjectPageViewModelInputs {
  /// Call when didSelectRowAt is called on a `ProjectFAQAskAQuestionCell`
  func askAQuestionCellTapped()

  /// Call when `AppDelegate`'s `applicationDidEnterBackground` is triggered.
  func applicationDidEnterBackground()

  /// Call when block user is tapped
  func blockUser(id: Int)

  /// Convenience overload for `configureWith` that defaults the `secretRewardToken` to `nil`.
  /// This version is primarily used in tests to avoid passing unnecessary parameters,
  /// which helps prevent widespread changes across all existing test cases in `ProjectPageViewModelTests`.
  /// Use this when the `secretRewardToken` context is not required.
  func configureWith(projectOrParam: Either<Project, any ProjectPageParam>, refInfo: RefInfo?)

  /// Call with the project given to the view controller, including an optional `secretRewardToken`.
  /// Use this when loading a project that include access to secret rewards for authenticated users.
  func configureWith(
    projectOrParam: Either<Project, any ProjectPageParam>,
    refInfo: RefInfo?,
    secretRewardToken: String?
  )

  /// Call when the Thank you page is dismissed after finishing backing the project
  func didBackProject()

  /// Call with the `Int` (index) of the cell selected and the existing values (`[Bool]`) in the data source
  func didSelectFAQsRowAt(row: Int, values: [Bool])

  /// Call with the `URL` of the `ImageViewElement` cell selected in the Campaign section of the data source.
  func didSelectCampaignImageLink(url: URL)

  /// Call when the ManagePledgeViewController finished updating/cancelling a pledge with an optional message
  func managePledgeViewControllerFinished(with message: String?)

  /// Call when the pledge CTA button is tapped
  func pledgeCTAButtonTapped(with state: PledgeStateCTAType)

  /// Call when pledgeRetryButton is tapped.
  func pledgeRetryButtonTapped()

  /// Call for image view elements that are missing inside `prefetchRowsAt` delegate in `ProjectPageViewController`
  func prepareImageAt(_ indexPath: IndexPath)

  /// Call for audio/video view elements that are missing a player inside `prefetchRowsAt` delegate in `ProjectPageViewController`
  func prepareAudioVideoAt(_ indexPath: IndexPath, with audioVideoViewElement: AudioVideoViewElement)

  /// Call when project notice details should be displayed.
  func projectNoticeDetailsRequested()

  /// Call when the delegate method for the `ProjectTabDisclaimerCellDelegate` is called.
  func projectTabDisclaimerCellDidTapURL(_ URL: URL)

  /// Call when the `ProjectNavigationSelectorViewDelegate` delegate method is called
  func projectNavigationSelectorViewDidSelect(index: Int)

  /// Call when the delegate method for the `ProjectRisksDisclaimerCellDelegate` is called.
  func projectRisksDisclaimerCellDidTapURL(_ url: URL)

  /// Call when didSelectRow is called on the comments cell.
  func tappedComments()

  /// Call when didSelectRow is called on the updates cell.
  func tappedUpdates()

  /// Call when didSelectRow is called on the report project cell.
  func tappedReportProject()

  /// Call when the user session starts and we want to reload the data source.
  func userSessionStarted()

  /// Call when the view did appear, and pass the animated parameter.
  func viewDidAppear(animated: Bool)

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when right before orientation change on view
  func viewWillTransition()

  /// Call when a similar project is tapped.
  func similarProjectTapped(project: ProjectCardProperties)
}

@MainActor
public protocol ProjectPageViewModelOutputs: AnyObject {
  /// Emits a tuple of a `NavigationSection`, `Project` and `RefTag?` to configure the data source
  var onConfigureDataSource: (((NavigationSection, Either<Project, any ProjectPageParam>, RefTag?)) -> Void)? { get set }

  /// Emits a project that should be used to configure all children view controllers.
  var onConfigureProject: (((Project, RefTag?)) -> Void)? { get set }

  /// Emits PledgeCTAContainerViewData to configure PledgeCTAContainerView
  var onConfigurePledgeCTA: ((PledgeCTAContainerViewData) -> Void)? { get set }

  /// Emits `(Project, RefTag?)` to configure `ProjectNavigationSelectorView`

  /// Emits a message to show on `MessageBannerViewController`
  var onManagePledgeFinishedWithMessage: ((String) -> Void)? { get set }

  /// Emits a `Project` when the comments are to be rendered.
  var onGoToComments: ((Project) -> Void)? { get set }

  /// Emits `LoginIntent` to take the user to the `LoginToutViewController`
  var onGoToLoginWithIntent: ((LoginIntent) -> Void)? { get set }

  /// Emits `ManagePledgeViewParamConfigData` to take the user to the `ManagePledgeViewController`
  var onGoToManagePledge: ((ManagePledgeViewParamConfigData) -> Void)? { get set }

  /// Emits `URL` to take the user to the `PledgeManagementDetailsWebViewController`
  var onGoToPledgeManagementPledgeView: ((String) -> Void)? { get set }

  var onGoToPledgeManager: ((String) -> Void)? { get set }

  /// Emits a `Project` when the updates are to be rendered.
  var onGoToUpdates: ((Project) -> Void)? { get set }

  /// Emits a `String` that explains why the creator is restricted.
  var onGoToRestrictedCreator: ((String) -> Void)? { get set }

  /// Emits a `Bool` to show if the project has been flagged, the projectID as a `String`, and  a  project URL `String` when the report project view is to be rendered.
  var onGoToReportProject: (((Bool, String, String)) -> Void)? { get set }

  /// Emits a project and refTag to be used to navigate to the reward selection screen.
  var onGoToRewards: (((Project, RefTag?, String?)) -> Void)? { get set }

  /// Emits a URL that will be opened by an external Safari browser.
  var onGoToURL: ((URL) -> Void)? { get set }

  /// Emits a signal when the app is no longer being actively used to pause any playing media.
  var onPauseMedia: (() -> Void)? { get set }

  /// Emits when the Project page should be shown again (popping back in the stack and dismissing any modals).
  var onNavigateBackToProjectPage: (() -> Void)? { get set }

  /// Emits `Project` when the MessageDialogViewController should be presented
  var onPresentMessageDialog: ((Project) -> Void)? { get set }

  /// Emits `AudioVideoViewElement` and `IndexPath` when the project has campaign data to download for a row
  var onPrepareAudioVideo: (((AudioVideoViewElement, IndexPath)) -> Void)? { get set }

  /// Emits `[AudioVideoViewElement]` to preload the data source with `AVPlayer` objects for video player cells.
  var onPreloadAudioVideo: (([AudioVideoViewElement]) -> Void)? { get set }

  /// Emits `[URL]` and `IndexPath` when the project has campaign data to download for a row
  var onPrefetchImageRow: ((([URL], IndexPath)) -> Void)? { get set }

  /// Emits `[ImageViewElement]` when the project has campaign data to download for an image row as soon as the urls are available.
  var onPrefetchImages: (([ImageViewElement]) -> Void)? { get set }

  /// Emits a `Bool` when a project is flagged.
  var onProjectFlagged: ((Bool) -> Void)? { get set }

  /// Emits a signal when an orientation change happens if the currently selected tab is campaign.
  var onReloadCampaignData: (() -> Void)? { get set }

  /// Emits a `HelpType` to use when presenting a HelpWebViewController.
  var onShowHelp: ((HelpType) -> Void)? { get set }

  /// Emits a tuple of a `NavigationSection`, `Project`, `RefTag?`, `[Bool]` (isExpanded values) and `[URL]` for campaign data to instruct the data source which section it is loading. Also a
  /// `SimilarProjectsState` for loading the Similar Projects Carousel.
  var onShowProjectPageTab: (((NavigationSection, Project, RefTag?, [Bool], [URL], SimilarProjectsState, ProjectPageContentView)) -> Void)? { get set }

  /// Emits a tuple of `Project`, `RefTag?` and `[Bool]` (isExpanded values) for the FAQs.
  var onUpdateFAQs: (((Project, RefTag?, [Bool])) -> Void)? { get set }

  /// Emits a prelaunch save state that updates the navigation bar's watch project state.
  var onUpdateWatchProject: ((PledgeCTAPrelaunchState) -> Void)? { get set }

  /// Emits when a block user request is successful.
  var onDidBlockUser: (() -> Void)? { get set }

  /// Emits when a block user request fails.
  var onDidBlockUserError: (() -> Void)? { get set }

  /// Called when a user taps a similar project.
  var onNavigateToSimilarProject: ((ProjectCardProperties) -> Void)? { get set }
}

@MainActor
public protocol ProjectPageViewModelType {
  @discardableResult func prepareMedia(slot: String, url: URL, thumbnail: URL?, completion: @escaping (PreparedProjectMedia) -> Void) -> Task<Void, Never>
  @discardableResult func prepareImage(slot: String, url: URL, completion: @escaping (UIImage) -> Void) -> Task<Void, Never>
  func cancelImagePreparation()
  func cancelMediaPreparation()
  var inputs: ProjectPageViewModelInputs { get }
  var outputs: ProjectPageViewModelOutputs { get }
}

@MainActor
public final class ProjectPageViewModel: ProjectPageViewModelType, ProjectPageViewModelInputs,
  ProjectPageViewModelOutputs {
  private let projectMediaFeature: ProjectMediaFeature
  private var mediaWaiters: [String: (id: UUID, url: URL, thumbnail: URL?, task: Task<Void, Never>)] = [:]

  private var imageWaiters: [String: (id: UUID, url: URL, task: Task<Void, Never>)] = [:]

  @discardableResult
  public func prepareImage(slot: String, url: URL, completion: @escaping (UIImage) -> Void) -> Task<Void, Never> {
    if let pending = self.imageWaiters[slot], pending.url == url { return pending.task }
    self.imageWaiters[slot]?.task.cancel()
    let id = UUID()
    let request = self.projectMediaFeature.requestImage(route: self.projectRoute, url: url)
    let task = Task { [weak self] in
      defer { if self?.imageWaiters[slot]?.id == id { self?.imageWaiters[slot] = nil } }
      do {
        let image = try await request.value
        guard !Task.isCancelled, self?.imageWaiters[slot]?.id == id else { return }
        completion(image)
      } catch { /* Optional campaign images retain their existing fallback and may retry. */ }
    }
    self.imageWaiters[slot] = (id, url, task)
    return task
  }

  public func cancelImagePreparation() {
    self.imageWaiters.values.forEach { $0.task.cancel() }
    self.imageWaiters.removeAll()
    self.projectMediaFeature.cancelImages(route: self.projectRoute)
  }

  @discardableResult
  public func prepareMedia(
    slot: String, url: URL, thumbnail: URL?, completion: @escaping (PreparedProjectMedia) -> Void
  ) -> Task<Void, Never> {
    if let pending = self.mediaWaiters[slot], pending.url == url, pending.thumbnail == thumbnail { return pending.task }
    self.mediaWaiters[slot]?.task.cancel()
    let id = UUID()
    let request = self.projectMediaFeature.requestPreparation(route: self.projectRoute, slot: slot, url: url, thumbnail: thumbnail)
    let task = Task { [weak self] in
      defer { if self?.mediaWaiters[slot]?.id == id { self?.mediaWaiters[slot] = nil } }
      do {
        let media = try await request.value
        guard !Task.isCancelled, self?.mediaWaiters[slot]?.id == id else { return }
        completion(media)
      } catch {
        // Preserve the existing optional-player fallback; the slot can retry.
      }
    }
    self.mediaWaiters[slot] = (id, url, thumbnail, task)
    return task
  }

  public func cancelMediaPreparation() {
    self.mediaWaiters.values.forEach { $0.task.cancel() }
    self.mediaWaiters.removeAll()
    self.projectMediaFeature.cancelPreparations(route: self.projectRoute)
  }

  private let projectDetailsFeature: ProjectDetailsFeature
  private var projectDetailsObservation: MainActorObservation?
  private let projectRoute = UUID()
  private var latestProject: Project?
  private var hasLoadedView = false
  private var latestBackedProject: (Project, Backing)?
  private var latestProjectRefTag: RefTag?
  private var latestImageElements: [ImageViewElement]?
  private var latestImageIndexPath: IndexPath?
  private var latestFAQSelection: (Int, [Bool])?
  private var selectedNavigationIndex: Int?
  private var latestNavigationSection: NavigationSection?
  private var relatedState: SimilarProjectsState = .loading
  private var hasRelatedStateEmission = false
  private var requestRefTag: RefTag?
  private var pendingViewedProjects: [(Project, RefTag?)] = []
  private var pendingAppearances = 0
  private var didRecordAttribution = false
  private var didInspectFirstCookie = false
  private var lastRelatedProjectID: String?
  internal private(set) var loadingTask: Task<Void, Never>?

  public init(projectDetailsFeature: ProjectDetailsFeature? = nil, projectMediaFeature: ProjectMediaFeature? = nil) {
    self.projectMediaFeature = projectMediaFeature ?? AppModel.shared.projectMediaFeature
    let projectDetailsFeature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
    self.projectDetailsFeature = projectDetailsFeature
    self.similarProjectsUseCase = SimilarProjectsUseCase(projectDetailsFeature: projectDetailsFeature)


    // MARK: Project notice


    // MARK: User blocking

    // MARK: User Blocking Analytics

    let blockAnalytics = self.blockAnalytics
    blockAnalytics.onInitiate = { project, blockedUserId in
        AppEnvironment.current.ksrAnalytics
          .trackBlockedUser(
            project,
            page: .project,
            sectionContext: .overview,
            locationContext: .creatorDetailsMenu,
            typeContext: .initiate,
            targetUserId: "\(blockedUserId)"
          )
    }



    // MARK: Rewards

    self.rewardsUseCase = RewardsUseCase()

    // MARK: - Pledge View

    // MARK: Similar Projects

    self.rewardsUseCase.onRewards = { [weak self] in
      guard let self, let project = self.latestProject, let config = self.configData else { return }
      self.onGoToRewards?((project, self.latestProjectRefTag, config.2))
    }
    self.rewardsUseCase.onLogin = { [weak self] in self?.onGoToLoginWithIntent?($0) }

    self.similarProjectsUseCase.onState = { [weak self] state in
      guard let self else { return }
      self.relatedState = state
      self.hasRelatedStateEmission = true
      self.showSelectedProjectTabIfReady()
    }

    self.similarProjectsUseCase.onNavigate = { [weak self] in self?.onNavigateToSimilarProject?($0) }

    let route = self.projectRoute
    self.projectDetailsObservation = projectDetailsFeature.observe { [weak self] update in
      guard let self else { return }
      switch update {
      case let .loading(updateRoute, loading) where updateRoute == route:
        if loading { self.onConfigurePledgeCTA?(.loading) }
      case let .completion(updateRoute, result) where updateRoute == route:
        switch result {
        case let .success(project):
          self.latestProject = project
          if project.personalization.isBacking ?? false, let backing = project.personalization.backing {
            self.latestBackedProject = (project, backing)
          }
          self.latestProjectRefTag = self.requestRefTag
          self.onProjectFlagged?(project.flagging ?? false)
          self.onConfigurePledgeCTA?(.project(project))
          self.onConfigureProject?((project, self.requestRefTag))
          if self.hasLoadedView {
            self.onConfigureDataSource?((.overview, .left(project), self.requestRefTag))
          }
          self.recordProjectLoaded(project, refTag: self.requestRefTag)
          self.updateFAQsIfReady()
          self.showSelectedProjectTabIfReady()
          if let elements = project.extendedProjectProperties?.story.htmlViewElements {
            self.latestImageElements = elements.compactMap { $0 as? ImageViewElement }
            self.prefetchImageRowIfNeeded()
            self.onPrefetchImages?(elements.compactMap { $0 as? ImageViewElement })
            self.onPreloadAudioVideo?(elements.compactMap { $0 as? AudioVideoViewElement })
          }
        case let .failure(error):
          self.onConfigurePledgeCTA?(.error(error))
        }
      default: break
      }
    }
  }

  private func recordProjectLoaded(_ project: Project, refTag: RefTag?) {
    self.blockAnalytics.receive(project: project)
    self.pendingViewedProjects.append((project, refTag))
    self.flushProjectViews()
    self.recordAttributionIfReady()
    if !self.didInspectFirstCookie {
      self.didInspectFirstCookie = true
      if let tag = cookieRefTagFor(project: project) ?? refTag,
         let cookie = cookieFrom(refTag: tag, project: project) {
        AppEnvironment.current.cookieStorage.setCookie(cookie)
      }
    }
    let projectID = "\(project.id)"
    if self.lastRelatedProjectID != projectID {
      self.lastRelatedProjectID = projectID
      DispatchQueue.main.async { [weak self] in
        self?.similarProjectsUseCase.projectIDLoaded(projectID: projectID)
      }
    }
  }

  private func recordAttributionIfReady() {
    guard !self.didRecordAttribution, let project = self.latestProject,
          let (_, refInfo, _) = self.configData else { return }
    self.didRecordAttribution = true
    self.projectDetailsFeature.recordAttribution(
      route: self.projectRoute, projectID: project.graphID,
      properties: AttributionTracking.eventParametersString(refInfo: refInfo)
    )
  }

  private func flushProjectViews() {
    while self.pendingAppearances > 0, !self.pendingViewedProjects.isEmpty {
      self.pendingAppearances -= 1
      let (project, refTag) = self.pendingViewedProjects.removeFirst()
      AppEnvironment.current.ksrAnalytics.trackProjectViewed(project, refTag: refTag, sectionContext: .overview)
      self.recordThirdPartyProjectView(project)
    }
  }

  private func recordThirdPartyProjectView(_ project: Project) {
    AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()
    guard let externalID = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier else { return }
    let userID = AppEnvironment.current.currentUser.map { "\($0.id)" } ?? ""
    var extInfo = Array(repeating: "", count: 16)
    extInfo[0] = "i2"
    extInfo[4] = AppEnvironment.current.mainBundle.platformVersion
    _ = AppEnvironment.current.apiService.prepareThirdPartyEvent(
      input: .init(
        deviceId: externalID,
        eventName: ThirdPartyEventInputName.ProjectPageViewed.rawValue,
        projectId: "\(project.id)", pledgeAmount: nil, shipping: nil, transactionId: nil,
        userId: userID,
        appData: .init(advertiserTrackingEnabled: true, applicationTrackingEnabled: true, extinfo: extInfo),
        clientMutationId: ""
      )
    )
  }

  private func loadProject(force: Bool) {
    guard let (projectOrParam, refInfo, token) = self.configData else { return }
    self.requestRefTag = refInfo?.refTag.map(cleanUp(refTag:))
    self.loadingTask = self.projectDetailsFeature.requestLoad(
      route: self.projectRoute, param: projectOrParam.param.param, secretRewardToken: token, force: force
    )
  }

  internal func waitForBlocking() async {
    await self.projectDetailsFeature.discussionFeature.waitForMutations()
    await self.blockPresentation.wait()
  }

  deinit {
    self.loadingTask?.cancel()
    self.imageWaiters.values.forEach { $0.task.cancel() }
    self.mediaWaiters.values.forEach { $0.task.cancel() }

    let details = self.projectDetailsFeature
    let media = self.projectMediaFeature
    let route = self.projectRoute
    // Finite route cleanup, with no self capture or new network operation.
    Task { @MainActor in
      media.cancelPreparations(route: route)
      media.cancelImages(route: route)
      details.release(route: route)
    }
  }

  public func askAQuestionCellTapped() {
    guard let project = self.latestProject else { return }
    self.onPresentMessageDialog?(project)
  }

  public func applicationDidEnterBackground() {
    self.onPauseMedia?()
  }

  private let blockPresentation = DiscussionBlockPresentation()
  private let blockAnalytics = BlockUserAnalyticsContext()
  public func blockUser(id: Int) {
    self.blockAnalytics.receive(userID: "\(id)")
    self.blockPresentation.start(feature: self.projectDetailsFeature.discussionFeature, id: String(id)) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success:
        NotificationCenter.default.post(.init(name: .ksr_blockedUser))
        self.onDidBlockUser?()
        if let (project, blockedUserId) = self.blockAnalytics.latest {
          AppEnvironment.current.ksrAnalytics.trackBlockedUser(
            project,
            page: .project,
            sectionContext: .overview,
            locationContext: .creatorDetailsMenu,
            typeContext: .confirm,
            targetUserId: blockedUserId
          )
        }
      case .failure:
        self.onDidBlockUserError?()
      }
    }
  }

  private var configData: (Either<Project, any ProjectPageParam>, RefInfo?, String?)?
  public func configureWith(
    projectOrParam: Either<Project, any ProjectPageParam>,
    refInfo: RefInfo?,
    secretRewardToken: String?
  ) {
    self.cancelMediaPreparation()
    self.cancelImagePreparation()
    self.configData = (projectOrParam, refInfo, secretRewardToken)
    self.recordAttributionIfReady()
    self.rewardsUseCase.configure(secretRewardToken: secretRewardToken)
  }

  /// Convenience overload for `configureWith` that defaults the `secretRewardToken` to `nil`.
  /// This version is primarily used in tests to avoid passing unnecessary parameters,
  /// which helps prevent widespread changes across all existing test cases in `ProjectPageViewModelTests`.
  /// Use this when the `secretRewardToken` context is not required.
  public func configureWith(projectOrParam: Either<Project, any ProjectPageParam>, refInfo: RefInfo?) {
    self.configureWith(projectOrParam: projectOrParam, refInfo: refInfo, secretRewardToken: nil)
  }

  public func didBackProject() {
    self.onNavigateBackToProjectPage?()
    self.loadProject(force: true)
  }

  public func didSelectFAQsRowAt(row: Int, values: [Bool]) {
    self.latestFAQSelection = (row, values)
    self.updateFAQsIfReady()
  }

  private func updateFAQsIfReady() {
    guard let project = self.latestProject, let (index, values) = self.latestFAQSelection,
          values.indices.contains(index) else { return }
    var updatedValues = values
    updatedValues[index].toggle()
    self.onUpdateFAQs?((project, self.latestProjectRefTag, updatedValues))
  }

  public func didSelectCampaignImageLink(url: URL) {
    self.onGoToURL?(url)
  }

  public func managePledgeViewControllerFinished(with message: String?) {
    if let message { self.onManagePledgeFinishedWithMessage?(message) }
    self.loadProject(force: true)
  }

  public func pledgeCTAButtonTapped(with state: PledgeStateCTAType) {
    switch state {
    case let .prelaunch(saved, watchesCount):
      self.onUpdateWatchProject?(
        PledgeCTAPrelaunchState(prelaunch: true, saved: saved, watchesCount: watchesCount)
      )
    case .pledge, .viewRewards, .viewYourRewards:
      self.rewardsUseCase.goToRewardsTapped()
    case .pledgeManager:
      guard let project = self.latestProject else { return }
      self.onGoToPledgeManager?(
        AppEnvironment.current.apiService.serverConfig.webBaseUrl.absoluteString + project.redemptionPageUrl
      )
    case .fix, .viewBacking, .manage:
      guard let (project, backing) = self.latestBackedProject else { return }
      switch pledgeDestination(project: project, backing: backing) {
      case let .native(params): self.onGoToManagePledge?(params)
      case let .web(url): self.onGoToPledgeManagementPledgeView?(url)
      }
    default:
      break
    }
  }

  public func pledgeRetryButtonTapped() {
    self.loadProject(force: false)
  }

  public func prepareImageAt(_ indexPath: IndexPath) {
    self.latestImageIndexPath = indexPath
    self.prefetchImageRowIfNeeded()
  }

  private func prefetchImageRowIfNeeded() {
    guard let section = self.selectedNavigationIndex,
          NavigationSection(rawValue: section) == .campaign,
          let indexPath = self.latestImageIndexPath,
          let elements = self.latestImageElements, !elements.isEmpty else { return }
    self.onPrefetchImageRow?((elements.compactMap { URL(string: $0.src) }, indexPath))
  }

  public func prepareAudioVideoAt(_ indexPath: IndexPath, with audioVideoViewElement: AudioVideoViewElement) {
    self.onPrepareAudioVideo?((audioVideoViewElement, indexPath))
  }

  public func projectNoticeDetailsRequested() {
    guard let notice = self.latestProject?.extendedProjectProperties?.projectNotice else { return }
    self.onGoToRestrictedCreator?(notice)
  }

  public func projectTabDisclaimerCellDidTapURL(_ url: URL) {
    if let help = HelpType.helpType(from: url) { self.onShowHelp?(help) }
  }

  public func projectNavigationSelectorViewDidSelect(index: Int) {
    guard self.selectedNavigationIndex != index else { return }
    self.selectedNavigationIndex = index
    guard let section = NavigationSection(rawValue: index) else { return }
    self.latestNavigationSection = section
    self.showSelectedProjectTabIfReady()
  }

  private func showSelectedProjectTabIfReady() {
    guard self.hasRelatedStateEmission, let section = self.latestNavigationSection,
          let project = self.latestProject else { return }
    let expanded = Array(repeating: false, count: project.extendedProjectProperties?.faqs.count ?? 0)
    var urls: [URL] = []
    var contentView: ProjectPageContentView = .tableView
    if section == .campaign {
      if featureProjectStoryRichTextEnabled(), let richText = project.extendedProjectProperties?.story.richText {
        contentView = .richTextView(richText)
      }
      urls = (project.extendedProjectProperties?.story.htmlViewElements ?? [])
        .compactMap { $0 as? ImageViewElement }
        .compactMap { URL(string: $0.src) }
    }
    self.onShowProjectPageTab?((section, project, self.latestProjectRefTag, expanded, urls, self.relatedState, contentView))
  }

  public func projectRisksDisclaimerCellDidTapURL(_ url: URL) {
    if let help = HelpType.helpType(from: url) { self.onShowHelp?(help) }
  }

  public func tappedComments() {
    guard let project = self.latestProject else { return }
    self.onGoToComments?(project)
  }

  public func tappedUpdates() {
    guard let project = self.latestProject else { return }
    self.onGoToUpdates?(project)
  }

  public func tappedReportProject() {
    guard let project = self.latestProject else { return }
    self.onGoToReportProject?((project.flagging ?? false, "\(project.graphID)", project.urls.web.project))
  }

  public func userSessionStarted() {
    self.loadProject(force: true)
  }

  public func viewDidLoad() {
    self.hasLoadedView = true
    self.hasRelatedStateEmission = true
    self.showSelectedProjectTabIfReady()
    if let (projectOrParam, refInfo, _) = self.configData, projectOrParam.canDisplayProjectPreview {
      self.onConfigureDataSource?((.overview, projectOrParam, refInfo?.refTag))
    }
    if let project = self.latestProject {
      self.onConfigureDataSource?((.overview, .left(project), self.latestProjectRefTag))
    }
    self.loadProject(force: false)
  }

  public func viewDidAppear(animated: Bool) {
    self.pendingAppearances += 1
    self.flushProjectViews()
  }

  public func viewWillTransition() {
    guard let index = self.selectedNavigationIndex,
          NavigationSection(rawValue: index) == .campaign else { return }
    self.onReloadCampaignData?()
  }

  public var onConfigureDataSource: (((NavigationSection, Either<Project, any ProjectPageParam>, RefTag?)) -> Void)?
  public var onConfigureProject: (((Project, RefTag?)) -> Void)?
  public var onConfigurePledgeCTA: ((PledgeCTAContainerViewData) -> Void)?
  public var onManagePledgeFinishedWithMessage: ((String) -> Void)?
  public var onGoToComments: ((Project) -> Void)?

  public var onGoToLoginWithIntent: ((LoginIntent) -> Void)?

  public var onGoToManagePledge: ((ManagePledgeViewParamConfigData) -> Void)?

  public var onGoToPledgeManager: ((String) -> Void)?

  public var onGoToPledgeManagementPledgeView: ((String) -> Void)?

  public var onGoToRestrictedCreator: ((String) -> Void)?
  public var onGoToRewards: (((Project, RefTag?, String?)) -> Void)?
  public var onGoToUpdates: ((Project) -> Void)?
  public var onGoToReportProject: (((Bool, String, String)) -> Void)?
  public var onGoToURL: ((URL) -> Void)?
  public var onPauseMedia: (() -> Void)?
  public var onNavigateBackToProjectPage: (() -> Void)?
  public var onPresentMessageDialog: ((Project) -> Void)?
  public var onPrepareAudioVideo: (((AudioVideoViewElement, IndexPath)) -> Void)?
  public var onPreloadAudioVideo: (([AudioVideoViewElement]) -> Void)?
  public var onPrefetchImageRow: ((([URL], IndexPath)) -> Void)?
  public var onPrefetchImages: (([ImageViewElement]) -> Void)?
  public var onProjectFlagged: ((Bool) -> Void)?
  public var onReloadCampaignData: (() -> Void)?
  public var onShowHelp: ((HelpType) -> Void)?
  public var onShowProjectPageTab: (((NavigationSection, Project, RefTag?, [Bool], [URL], SimilarProjectsState, ProjectPageContentView)) -> Void)?
  public var onUpdateFAQs: (((Project, RefTag?, [Bool])) -> Void)?
  public var onUpdateWatchProject: ((PledgeCTAPrelaunchState) -> Void)?
  public var onDidBlockUser: (() -> Void)?
  public var onDidBlockUserError: (() -> Void)?

  public var inputs: ProjectPageViewModelInputs { return self }
  public var outputs: ProjectPageViewModelOutputs { return self }

  // MARK: - Similar Projects

  private let similarProjectsUseCase: SimilarProjectsUseCase

  public func similarProjectTapped(project: ProjectCardProperties) {
    self.similarProjectsUseCase.projectTapped(project: project)
  }

  public var onNavigateToSimilarProject: ((ProjectCardProperties) -> Void)?

  // MARK: - RewardsUseCase

  private let rewardsUseCase: RewardsUseCase
}


private extension Either where A == Project, B == ProjectPageParam {
  var param: Param {
    switch self {
    case let .left(project):
      return Param.id(project.id)
    case let .right(projectParam):
      return projectParam.param
    }
  }
}

private extension Either where A == Project, B == any ProjectPageParam {
  /// Whether or not the view model can emit some initial (stale) data while we wait for the project to reload.
  var canDisplayProjectPreview: Bool {
    // The VM was configured with a ProjectPageParam that has an initialProject set
    if let right = self.right,
       let _ = right.initialProject {
      return true
    }

    // The VM was configured with a Project object
    if let _ = self.left {
      return true
    }

    return false
  }
}
