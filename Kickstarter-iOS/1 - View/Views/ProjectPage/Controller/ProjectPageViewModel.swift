import Experimentation
import Foundation
import GraphAPI
import KsApi
import Prelude
import ReactiveSwift
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
  var configureDataSource: Signal<
    (NavigationSection, Either<Project, any ProjectPageParam>, RefTag?),
    Never
  > {
    get
  }

  /// Emits a project that should be used to configure all children view controllers.
  var configureChildViewControllersWithProject: Signal<(Project, RefTag?), Never> { get }

  /// Emits PledgeCTAContainerViewData to configure PledgeCTAContainerView
  var configurePledgeCTAView: Signal<PledgeCTAContainerViewData, Never> { get }

  /// Emits `(Project, RefTag?)` to configure `ProjectNavigationSelectorView`
  var configureProjectNavigationSelectorView: Signal<(Project, RefTag?), Never> { get }

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
  var precreateAudioVideoURLs: Signal<(AudioVideoViewElement, IndexPath), Never> { get }

  /// Emits `[AudioVideoViewElement]` to preload the data source with `AVPlayer` objects for video player cells.
  var precreateAudioVideoURLsOnFirstLoad: Signal<[AudioVideoViewElement], Never> { get }

  /// Emits `[URL]` and `IndexPath` when the project has campaign data to download for a row
  var prefetchImageURLs: Signal<([URL], IndexPath), Never> { get }

  /// Emits `[ImageViewElement]` when the project has campaign data to download for an image row as soon as the urls are available.
  var prefetchImageURLsOnFirstLoad: Signal<[ImageViewElement], Never> { get }

  /// Emits a `Bool` when a project is flagged.
  var onProjectFlagged: ((Bool) -> Void)? { get set }

  /// Emits a signal when an orientation change happens if the currently selected tab is campaign.
  var onReloadCampaignData: (() -> Void)? { get set }

  /// Emits a `HelpType` to use when presenting a HelpWebViewController.
  var onShowHelp: ((HelpType) -> Void)? { get set }

  /// Emits a tuple of a `NavigationSection`, `Project`, `RefTag?`, `[Bool]` (isExpanded values) and `[URL]` for campaign data to instruct the data source which section it is loading. Also a
  /// `SimilarProjectsState` for loading the Similar Projects Carousel.
  var showProjectPageTabWithData: Signal<
    (NavigationSection, Project, RefTag?, [Bool], [URL], SimilarProjectsState, ProjectPageContentView),
    Never
  > { get }

  /// Emits a tuple of `Project`, `RefTag?` and `[Bool]` (isExpanded values) for the FAQs.
  var updateFAQsInDataSource: Signal<(Project, RefTag?, [Bool]), Never> { get }

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
  private var latestBackedProject: (Project, Backing)?
  private var latestProjectRefTag: RefTag?
  private var requestRefTag: RefTag?
  internal private(set) var loadingTask: Task<Void, Never>?

  public init(projectDetailsFeature: ProjectDetailsFeature? = nil, projectMediaFeature: ProjectMediaFeature? = nil) {
    self.projectMediaFeature = projectMediaFeature ?? AppModel.shared.projectMediaFeature
    let projectDetailsFeature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
    self.projectDetailsFeature = projectDetailsFeature
    self.similarProjectsUseCase = SimilarProjectsUseCase(projectDetailsFeature: projectDetailsFeature)
    let relatedState = self.relatedState
    self.similarProjectsUseCase.onState = { relatedState.value = $0 }
    let isLoading = MutableProperty(false)


    // Output-only adapter: the Feature owns execution and completion.
    let completion = Signal<Signal<(Project, RefTag?), ErrorEnvelope>.Event, Never>.pipe()
    let freshProjectAndRefTagEvent = completion.output

    let freshProjectAndRefTag: Signal<(Project, RefTag?), Never> = freshProjectAndRefTagEvent.values()

    let freshProject = freshProjectAndRefTag
      .map(first)

    self.prefetchImageURLs = freshProject.signal
      .compactMap { $0.extendedProjectProperties }
      .combineLatest(with: self.prepareImageAtProperty.signal.skipNil())
      .filterWhenLatestFrom(
        self.projectNavigationSelectorViewDidSelectProperty.signal.skipNil(),
        satisfies: { NavigationSection(rawValue: $0) == .campaign }
      )
      .switchMap { properties, indexPath -> SignalProducer<([URL], IndexPath)?, Never> in
        let imageViewElements = properties.story.htmlViewElements
          .compactMap { $0 as? ImageViewElement }

        if imageViewElements.count > 0 {
          let urlStrings = imageViewElements.map { $0.src }
          let urls = urlStrings.compactMap { URL(string: $0) }

          return SignalProducer(value: (urls, indexPath))
        }

        return SignalProducer(value: nil)
      }
      .skipNil()

    self.prefetchImageURLsOnFirstLoad = freshProject.signal
      .compactMap { $0.extendedProjectProperties }
      .switchMap { properties -> SignalProducer<[ImageViewElement], Never> in
        let imageViewElements = properties.story.htmlViewElements
          .compactMap { $0 as? ImageViewElement }

        return SignalProducer(value: imageViewElements)
      }

    self.precreateAudioVideoURLsOnFirstLoad = freshProject.signal
      .compactMap { $0.extendedProjectProperties }
      .switchMap { properties -> SignalProducer<[AudioVideoViewElement], Never> in
        let audioVideoViewElements = properties.story.htmlViewElements
          .compactMap { $0 as? AudioVideoViewElement }

        return SignalProducer(value: audioVideoViewElements)
      }

    self.precreateAudioVideoURLs = self.prepareAudioVideoAtProperty.signal.skipNil()

    // Project data that is passed when the ProjectPageViewController is initialized.
    // Used to show the Project overview page while we re-fetch the rest of the project data.
    let staleProjectData = self.configDataProperty.signal
      .takeWhen(self.viewDidLoadProperty.signal)
      .skipNil()
      .filter { projectOrParam, _, _ -> Bool in
        projectOrParam.canDisplayProjectPreview
      }

    let staleProjectDataSource = staleProjectData
      .map { projectOrParam, refInfo, _ in
        (NavigationSection.overview, projectOrParam, refInfo?.refTag)
      }

    // The first tab we render by default is overview.
    self.configureDataSource = freshProjectAndRefTag
      .combineLatest(with: self.viewDidLoadProperty.signal)
      .map { projectAndRefTag, _ in
        let (project, refTag) = projectAndRefTag
        return (.overview, .left(project), refTag)
      }
      .merge(with: staleProjectDataSource)

    self.configurePledgeCTAView = Signal.merge(
      // Successful fetch
      freshProject.map { .project($0) },
      // Errored fetch
      freshProjectAndRefTagEvent.errors().map { .error($0) },
      // Loading
      isLoading.signal.filter { $0 == true }.mapConst(.loading)
    )
    .skipRepeats()

    self.configureChildViewControllersWithProject = freshProjectAndRefTag
      .map { project, refTag in (project, refTag) }


    let cookieRefTag: Signal<RefTag?, Never> = freshProjectAndRefTag
      .map { project, refTag -> RefTag? in
        let r = cookieRefTagFor(project: project) ?? refTag
        return r
      }
      .take(first: 1)






    self.configureProjectNavigationSelectorView = freshProjectAndRefTag
      .map { projectAndRefTag in
        let (project, refTag) = projectAndRefTag
        return (project: project, refTag: refTag)
      }

    let trackFreshProjectAndRefTagViewed: Signal<(Project, RefTag?), Never> = Signal.zip(
      freshProjectAndRefTag,
      self.viewDidAppearAnimatedProperty.signal.ignoreValues()
    )
    .map(unpack)
    .map { project, refTag, _ in
      (project: project, refTag: refTag)
    }

    trackFreshProjectAndRefTagViewed
      .observeValues { project, refTag in
        AppEnvironment.current.ksrAnalytics.trackProjectViewed(
          project,
          refTag: refTag,
          sectionContext: .overview
        )
      }

    // Facebook CAPI + Google Analytics
    trackFreshProjectAndRefTagViewed
      .observeValues { projectAndRefTag in
        let (project, _) = projectAndRefTag

        AppEnvironment.current.appTrackingTransparency.updateAdvertisingIdentifier()

        guard let externalId = AppEnvironment.current.appTrackingTransparency.advertisingIdentifier
        else { return }

        var userId = ""

        if let userValue = AppEnvironment.current.currentUser {
          userId = "\(userValue.id)"
        }

        let projectId = "\(project.id)"

        var extInfo = Array(repeating: "", count: 16)
        extInfo[0] = "i2"
        extInfo[4] = AppEnvironment.current.mainBundle.platformVersion

        _ = AppEnvironment
          .current
          .apiService
          .prepareThirdPartyEvent(
            input: .init(
              deviceId: externalId,
              eventName: ThirdPartyEventInputName.ProjectPageViewed.rawValue,
              projectId: projectId,
              pledgeAmount: nil,
              shipping: nil,
              transactionId: nil,
              userId: userId,
              appData: .init(
                advertiserTrackingEnabled: true,
                applicationTrackingEnabled: true,
                extinfo: extInfo
              ),
              clientMutationId: ""
            )
          )
      }

    // Event attribution tracking
    self.configDataProperty.signal
      .skipNil()
      .combineLatest(with: freshProjectAndRefTag)
      .map { projectAndRefInfo, freshProjectAndRefTag in
        let (_, refInfo, _) = projectAndRefInfo
        let (project, _) = freshProjectAndRefTag
        return (project.graphID, refInfo)
      }
      .take(first: 1)
      .observeValues { [projectRoute = self.projectRoute] graphId, refInfo in
        projectDetailsFeature.recordAttribution(
          route: projectRoute, projectID: graphId,
          properties: AttributionTracking.eventParametersString(refInfo: refInfo)
        )
      }

    Signal.combineLatest(cookieRefTag.skipNil(), freshProjectAndRefTag.map(first))
      .take(first: 1)
      .map(cookieFrom(refTag:project:))
      .skipNil()
      .observeValues { AppEnvironment.current.cookieStorage.setCookie($0) }



    let dataSourceUpdate = self.projectNavigationSelectorViewDidSelectProperty.signal
      .skipNil()
      .skipRepeats()
      .map { index in NavigationSection(rawValue: index) }
      .skipNil()
      .combineLatest(with: freshProjectAndRefTag)
      .map { navSection, projectAndRefTag in
        let (project, refTag) = projectAndRefTag
        let initialIsExpandedArray = Array(
          repeating: false,
          count: project.extendedProjectProperties?.faqs.count ?? 0
        )

        var urls: [URL] = []
        var contentView: ProjectPageContentView = .tableView

        switch navSection {
        case .campaign:
          contentView = {
            guard navSection == .campaign,
                  featureProjectStoryRichTextEnabled(),
                  let richText = project.extendedProjectProperties?.story.richText
            else {
              return .tableView
            }
            return .richTextView(richText)
          }()

          let imageViewElements = project.extendedProjectProperties?.story.htmlViewElements
            .compactMap { $0 as? ImageViewElement } ?? []

          if imageViewElements.count > 0 {
            let urlStrings = imageViewElements.map { $0.src }
            urls = urlStrings.compactMap { URL(string: $0) }
          }
        default:
          break
        }

        return (navSection, project, refTag, initialIsExpandedArray, urls, contentView)
      }

    let similarProjectsState = self.relatedState.signal
      .merge(
        with: self.relatedState.producer
          .takeWhen(self.viewDidLoadProperty.signal)
      )

    self.showProjectPageTabWithData = Signal.combineLatest(
      dataSourceUpdate,
      similarProjectsState
    )
    .map { dataSource, similarProjects in
      let (navSection, project, refTag, initialIsExpandedArray, urls, contentView) = dataSource
      return (navSection, project, refTag, initialIsExpandedArray, urls, similarProjects, contentView)
    }

    self.updateFAQsInDataSource = freshProjectAndRefTag
      .combineLatest(with: self.didSelectFAQsRowAtProperty.signal.skipNil())
      .map { projectAndRefTag, indexAndDataSourceValues in
        let (project, refTag) = projectAndRefTag
        let (index, isExpandedValues) = indexAndDataSourceValues
        var updatedValues = isExpandedValues
        updatedValues[index] = !updatedValues[index]

        return (project, refTag, updatedValues)
      }


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
    _ = freshProject.signal.observeValues { project in
      blockAnalytics.receive(project: project)
    }



    // MARK: Rewards

    self.rewardsUseCase = RewardsUseCase()

    // MARK: - Pledge View

    // MARK: Similar Projects

    freshProjectAndRefTag
      .map { project, _ in "\(project.id)" }
      .skipRepeats()
      .observeForControllerAction()
      .observeValues { [weak self] projectID in
        self?.similarProjectsUseCase.projectIDLoaded(projectID: projectID)
      }

    self.rewardsUseCase.onRewards = { [weak self] in
      guard let self, let project = self.latestProject, let config = self.configDataProperty.value else { return }
      self.onGoToRewards?((project, self.latestProjectRefTag, config.2))
    }
    self.rewardsUseCase.onLogin = { [weak self] in self?.onGoToLoginWithIntent?($0) }

    self.similarProjectsUseCase.onNavigate = { [weak self] in self?.onNavigateToSimilarProject?($0) }

    let route = self.projectRoute
    self.projectDetailsObservation = projectDetailsFeature.observe { [weak self] update in
      guard let self else { return }
      switch update {
      case let .loading(updateRoute, loading) where updateRoute == route:
        isLoading.value = loading
      case let .completion(updateRoute, result) where updateRoute == route:
        switch result {
        case let .success(project):
          self.latestProject = project
          if project.personalization.isBacking ?? false, let backing = project.personalization.backing {
            self.latestBackedProject = (project, backing)
          }
          self.latestProjectRefTag = self.requestRefTag
          self.onProjectFlagged?(project.flagging ?? false)
          completion.input.send(value: .value((project, self.requestRefTag)))
        case let .failure(error): completion.input.send(value: .failed(error))
        }
      default: break
      }
    }
  }

  private func loadProject(force: Bool) {
    guard let (projectOrParam, refInfo, token) = self.configDataProperty.value else { return }
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

  private let configDataProperty = MutableProperty<(
    Either<Project, any ProjectPageParam>,
    RefInfo?,
    String?
  )?>(nil)
  public func configureWith(
    projectOrParam: Either<Project, any ProjectPageParam>,
    refInfo: RefInfo?,
    secretRewardToken: String?
  ) {
    self.cancelMediaPreparation()
    self.cancelImagePreparation()
    self.configDataProperty.value = (projectOrParam, refInfo, secretRewardToken)
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

  fileprivate let didSelectFAQsRowAtProperty = MutableProperty<(Int, [Bool])?>(nil)
  public func didSelectFAQsRowAt(row: Int, values: [Bool]) {
    self.didSelectFAQsRowAtProperty.value = (row, values)
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

  private let prepareImageAtProperty = MutableProperty<IndexPath?>(nil)
  public func prepareImageAt(_ indexPath: IndexPath) {
    self.prepareImageAtProperty.value = indexPath
  }

  private let prepareAudioVideoAtProperty = MutableProperty<(AudioVideoViewElement, IndexPath)?>(nil)
  public func prepareAudioVideoAt(_ indexPath: IndexPath, with audioVideoViewElement: AudioVideoViewElement) {
    self.prepareAudioVideoAtProperty.value = (audioVideoViewElement, indexPath)
  }

  public func projectNoticeDetailsRequested() {
    guard let notice = self.latestProject?.extendedProjectProperties?.projectNotice else { return }
    self.onGoToRestrictedCreator?(notice)
  }

  public func projectTabDisclaimerCellDidTapURL(_ url: URL) {
    if let help = HelpType.helpType(from: url) { self.onShowHelp?(help) }
  }

  private let projectNavigationSelectorViewDidSelectProperty = MutableProperty<Int?>(nil)
  public func projectNavigationSelectorViewDidSelect(index: Int) {
    self.projectNavigationSelectorViewDidSelectProperty.value = index
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

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
    self.loadProject(force: false)
  }

  fileprivate let viewDidAppearAnimatedProperty = MutableProperty(false)
  public func viewDidAppear(animated: Bool) {
    self.viewDidAppearAnimatedProperty.value = animated
  }

  public func viewWillTransition() {
    guard let index = self.projectNavigationSelectorViewDidSelectProperty.value,
          NavigationSection(rawValue: index) == .campaign else { return }
    self.onReloadCampaignData?()
  }

  public let configureDataSource: Signal<
    (NavigationSection, Either<Project, any ProjectPageParam>, RefTag?),
    Never
  >
  public let configureChildViewControllersWithProject: Signal<(Project, RefTag?), Never>
  public let configurePledgeCTAView: Signal<PledgeCTAContainerViewData, Never>
  public let configureProjectNavigationSelectorView: Signal<(Project, RefTag?), Never>
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
  public let precreateAudioVideoURLs: Signal<(AudioVideoViewElement, IndexPath), Never>
  public let precreateAudioVideoURLsOnFirstLoad: Signal<[AudioVideoViewElement], Never>
  public let prefetchImageURLs: Signal<([URL], IndexPath), Never>
  public let prefetchImageURLsOnFirstLoad: Signal<[ImageViewElement], Never>
  public var onProjectFlagged: ((Bool) -> Void)?
  public var onReloadCampaignData: (() -> Void)?
  public var onShowHelp: ((HelpType) -> Void)?
  public let showProjectPageTabWithData: Signal<
    (NavigationSection, Project, RefTag?, [Bool], [URL], SimilarProjectsState, ProjectPageContentView),
    Never
  >
  public let updateFAQsInDataSource: Signal<(Project, RefTag?, [Bool]), Never>
  public var onUpdateWatchProject: ((PledgeCTAPrelaunchState) -> Void)?
  public var onDidBlockUser: (() -> Void)?
  public var onDidBlockUserError: (() -> Void)?

  public var inputs: ProjectPageViewModelInputs { return self }
  public var outputs: ProjectPageViewModelOutputs { return self }

  // MARK: - Similar Projects

  private let similarProjectsUseCase: SimilarProjectsUseCase
  private let relatedState = MutableProperty<SimilarProjectsState>(.loading)

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
