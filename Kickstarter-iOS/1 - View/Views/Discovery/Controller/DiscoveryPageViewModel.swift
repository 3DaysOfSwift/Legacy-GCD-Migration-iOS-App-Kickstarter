import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift
import UIKit

@MainActor
public protocol DiscoveryPageViewModelInputs {
  /// Call when the Config has been updated in the AppEnvironment
  func configUpdated()

  /// Call with the sort provided to the view.
  func configureWith(sort: DiscoveryParams.Sort)

  /// Call when the current environment has changed
  func currentEnvironmentChanged(environment: EnvironmentType)

  /// Call when the logged in user has blocked another user
  func blockedUser()

  /// Call when onboarding has been completed
  func onboardingCompleted()

  /// Call when the personalization cell is tapped
  func personalizationCellTapped()

  /// Call when the personalization cell dismiss button is tapped
  func personalizationCellDismissTapped()

  /// Call when the user pulls tableView to refresh
  func pulledToRefresh()

  /// Call when the scrollViewDidScroll with its current contentOffset
  func scrollViewDidScroll(toContentOffset offset: CGPoint)

  /// Call when the filter is changed.
  func selectedFilter(_ params: DiscoveryParams)

  /// Call when the onboarding login/signup button is tapped
  func signupLoginButtonTapped()

  /// Call when the user taps on the activity sample.
  func tapped(activity: Activity)

  /// Call when the user taps on a project.
  func tapped(project: Project)

  /// Call when the controller has received a user session ended notification.
  func userSessionEnded()

  /// Call when the controller has received a user session started notification.
  func userSessionStarted()

  /// Call when the view appears.
  func viewDidAppear()

  /// Call when the view disappears.
  func viewDidDisappear(animated: Bool)

  /// Call when the view will appear.
  func viewWillAppear()

  /**
   Call from the controller's `tableView:willDisplayCell:forRowAtIndexPath` method.

   - parameter row:       The 0-based index of the row displaying.
   - parameter totalRows: The total number of rows in the table view.
   */
  func willDisplayRow(_ row: Int, outOf totalRows: Int)
}

@MainActor
public protocol DiscoveryPageViewModelOutputs: AnyObject {
  /// Emits a list of activities to be displayed in the sample.
  var onActivitiesForSample: (([Activity]) -> Void)? { get set }

  /// Hack to emit when we should asynchronously reload the table view's data to properly display postcards.
  /// Hopefully in the future we can remove this when we can resolve postcard display issues.
  var asyncReloadData: Signal<Void, Never> { get }

  /// Emits the contentInset for the UITableView
  var onContentInset: ((UIEdgeInsets) -> Void)? { get set }

  /// Emits when the personalization cell should be deleted
  var onDismissPersonalizationCell: (() -> Void)? { get set }

  /// Emits a project and ref tag that we should go to from the activity sample.
  var onGoToActivityProject: ((Project, RefTag) -> Void)? { get set }

  /// Emits an array of KsApi.Category objects used to generate a curated list of projects
  var onGoToCuratedProjects: (([KsApi.Category]) -> Void)? { get set }

  /// Emits a LoginIntent for the LoginToutViewController ot be configured with
  var onGoToLoginSignup: ((LoginIntent) -> Void)? { get set }

  /// Emits a project, playlist, ref tag that we should go to from discovery.
  var onGoToProjectPlaylist: ((Project, [Project], RefTag) -> Void)? { get set }

  /// Emits a project and update when should go to update.
  var onGoToProjectUpdate: ((Project, Update) -> Void)? { get set }

  /// Emits when we should dismiss the empty state controller.
  var hideEmptyState: Signal<(), Never> { get }

  /// Emits with the current contentOffset.
  var onContentOffsetChanged: ((CGPoint) -> Void)? { get set }

  /// Emits a list of projects that should be shown, and the corresponding filter request params
  var projectsLoaded: Signal<([Project], DiscoveryParams?), Never> { get }

  /// Emits a boolean that determines if projects are currently loading or not.
  var projectsAreLoadingAnimated: Signal<(Bool, Bool), Never> { get }

  /// Emits a bool to allow status bar tap to scroll the table view to the top.
  var onScrollsToTopChanged: ((Bool) -> Void)? { get set }

  /// Emits to show the empty state controller.
  var showEmptyState: Signal<EmptyState, Never> { get }

  /// Emits a boolean that determines of the onboarding should be shown.
  var onShowOnboarding: ((Bool) -> Void)? { get set }

  /// Emits to show the personalization section
  var onShowPersonalization: ((Bool) -> Void)? { get set }

  /// Emits to show the video feed banner
  var onVideoFeedBannerChanged: ((Bool) -> Void)? { get set }
}

@MainActor
public protocol DiscoveryPageViewModelType {
  var inputs: DiscoveryPageViewModelInputs { get }
  var outputs: DiscoveryPageViewModelOutputs { get }
}

@MainActor
public final class DiscoveryPageViewModel: DiscoveryPageViewModelType, DiscoveryPageViewModelInputs,
  DiscoveryPageViewModelOutputs {
  private let discoveryFeature: DiscoveryFeature
  private let projectsPipe = Signal<(DiscoveryParams.Sort, [Project]), Never>.pipe()
  private let loadingPipe = Signal<(DiscoveryParams.Sort, Bool), Never>.pipe()
  private var discoveryObservation: MainActorObservation?
  private let featureBindings = ScopedDisposable(CompositeDisposable())
  internal private(set) var pageTask: Task<Void, Never>?
  internal private(set) var activityTask: Task<Void, Never>?

  public init(discoveryFeature: DiscoveryFeature? = nil) {
    let discoveryFeature = discoveryFeature ?? AppModel.shared.discoveryFeature
    self.discoveryFeature = discoveryFeature
    let currentUser = Signal.merge(
      self.userSessionStartedProperty.signal,
      self.userSessionEndedProperty.signal,
      self.viewWillAppearProperty.signal
    )
    .map { AppEnvironment.current.currentUser }
    .skipRepeats(==)

    let paramsChanged = Signal.combineLatest(
      self.sortProperty.signal.skipNil(),
      self.selectedFilterProperty.signal.skipNil()
    )
    .map(DiscoveryParams.lens.sort.set)

    let isVisible = Signal.merge(
      self.viewDidAppearProperty.signal.mapConst(true),
      self.viewDidDisappearProperty.signal.mapConst(false)
    ).skipRepeats()

    let environmentChanged = self.currentEnvironmentChangedProperty.signal
      .skipNil()
      .skipRepeats()

    let firstPageParams = Signal.combineLatest(
      currentUser,
      paramsChanged,
      isVisible
    )
    .filter { _, _, visible in
      visible
    }
    .skipRepeats { lhs, rhs in
      lhs.0 == rhs.0 && lhs.1 == rhs.1
    }
    .map { $0.1 }

    let requestFirstPageWith = Signal.merge(
      firstPageParams,
      firstPageParams.takeWhen(environmentChanged),
      firstPageParams.takeWhen(self.pulledToRefreshProperty.signal),
      firstPageParams.takeWhen(self.blockedUserProperty.signal)
    )

    let selectedSort = self.sortProperty
    let paginatedProjects = self.projectsPipe.output
      .filter { $0.0 == selectedSort.value }
      .map { $0.1 }
    let isLoading = self.loadingPipe.output
      .filter { $0.0 == selectedSort.value }
      .map { $0.1 }

    let projects = Signal.merge(
      paginatedProjects,
      self.selectedFilterProperty.signal.skipNil().skipRepeats().mapConst([])
    )
    .skip { $0.isEmpty }
    .skipRepeats(==)

    self.projectsLoaded = paramsChanged.takePairWhen(projects)
      .map { paramsValue, projects in
        (projects, paramsValue)
      }

    self.asyncReloadData = self.projectsLoaded.take(first: 1).ignoreValues()


    let isRefreshing = isLoading
      .combineLatest(with: self.pulledToRefreshProperty.signal)
      .map(first)
      .skipRepeats()

    let projectsLoadingNoRefresh = Signal.merge(
      isLoading,
      isLoading.takeWhen(isRefreshing).mapConst(false)
    ).skipRepeats()

    self.projectsAreLoadingAnimated = Signal.merge(
      isRefreshing.map { ($0, true) },
      projectsLoadingNoRefresh.map { ($0, false) },
      self.viewWillAppearProperty.signal.take(first: 1).mapConst((true, false))
    )
    .skipRepeats(==)

    self.showEmptyState = Signal.combineLatest(
      paramsChanged,
      self.projectsAreLoadingAnimated.map(first),
      paginatedProjects
    )
    .filter { _, projectsAreLoading, projects in projectsAreLoading == false && projects.isEmpty }
    .map { params, _, _ in
      emptyState(forParams: params)
    }
    .skipNil()
    .skipRepeats()

    self.hideEmptyState = Signal.merge(
      self.viewWillAppearProperty.signal.take(first: 1),
      self.asyncReloadData,
      paginatedProjects.filter { !$0.isEmpty }.ignoreValues(),
      paramsChanged.skip(first: 1).ignoreValues()
    )


    self.featureBindings += self.projectsAreLoadingAnimated.observeValues { [weak self] loading, _ in
      guard let self else { return }
      self.currentProjectsLoading = loading
      self.publishContentOffsetIfReady()
    }

    // These observers only admit commands. The Feature owns and retains the work.
    self.featureBindings += requestFirstPageWith.observeValues { [weak self] parameters in
      guard let self, let sort = self.sortProperty.value else { return }
      self.pageTask = discoveryFeature.requestRefresh(sort: sort, parameters: parameters, force: true)
    }
    self.featureBindings += self.viewDidAppearProperty.signal.observeValues { [weak self] in
      guard let self, let sort = self.sortProperty.value,
            AppEnvironment.current.currentUser != nil else { return }
      self.activityTask = discoveryFeature.requestActivitySample(sort: sort)
    }

    // MARK: - Tracking

    self.featureBindings += Signal.combineLatest(requestFirstPageWith, self.viewWillAppearProperty.signal)
      .observeValues { params, _ in
        AppEnvironment.current.ksrAnalytics.trackDiscovery(params: params)
      }

    self.featureBindings += paramsChanged
      .takePairWhen(self.tappedProject.signal.skipNil())
      .observeValues { params, project in

        AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
          page: .discovery,
          project: project,
          typeContext: .init(params: params),
          location: .discoverAdvanced,
          params: params
        )
      }
    self.featureBindings += currentUser.observeValues { [weak self] user in
      self?.hasCurrentUserValue = true
      self?.onboardingUser = user
      self?.updateOnboarding()
    }
    self.featureBindings += paramsChanged.observeValues { [weak self] parameters in
      self?.currentNavigationParameters = parameters
      self?.clearActivityOnDisappear = true
      self?.updateOnboarding()
    }
    self.featureBindings += projects.observeValues { [weak self] in self?.currentNavigationProjects = $0 }

    self.discoveryObservation = discoveryFeature.observe { [weak self] update in
      guard let self else { return }
      switch update {
      case let .projects(sort, projects): self.projectsPipe.input.send(value: (sort, projects))
      case let .loading(sort, loading): self.loadingPipe.input.send(value: (sort, loading))
      case let .activities(sort, activities): self.receiveActivities(activities, sort: sort)
      }
    }
    self.connectivityObservation = AppEnvironment.current.reachability.observe { [weak self] value in
      guard let self else { return }
      self.connectivity = value
      if self.receivedInitialConnectivity { self.updateVideoFeedBanner() }
      self.receivedInitialConnectivity = true
    }
  }


  public func configUpdated() {
    self.updateVideoFeedBanner()
  }

  fileprivate let currentEnvironmentChangedProperty = MutableProperty<EnvironmentType?>(nil)
  public func currentEnvironmentChanged(environment: EnvironmentType) {
    self.currentEnvironmentChangedProperty.value = environment
  }

  fileprivate let blockedUserProperty = MutableProperty(())
  public func blockedUser() {
    self.blockedUserProperty.value = ()
  }

  public func onboardingCompleted() {
    if self.hasAppeared, self.hasReadyPersonalizationFilters { self.onShowPersonalization?(shouldShowPersonalization()) }
  }

  public func personalizationCellTapped() {
    guard let categories = cachedCategories() else { return }
    self.onGoToCuratedProjects?(categories)
  }

  public func personalizationCellDismissTapped() {
    AppEnvironment.current.userDefaults.hasDismissedPersonalizationCard = true
    self.onDismissPersonalizationCell?()
  }

  fileprivate let pulledToRefreshProperty = MutableProperty(())
  public func pulledToRefresh() {
    self.pulledToRefreshProperty.value = ()
  }

  fileprivate let sortProperty = MutableProperty<DiscoveryParams.Sort?>(nil)
  public func configureWith(sort: DiscoveryParams.Sort) {
    self.sortProperty.value = sort
  }

  private var currentContentOffset: CGPoint?
  private var currentProjectsLoading: Bool?
  public func scrollViewDidScroll(toContentOffset offset: CGPoint) {
    self.currentContentOffset = offset
    self.publishContentOffsetIfReady()
  }
  private func publishContentOffsetIfReady() {
    guard self.currentProjectsLoading == false, let offset = self.currentContentOffset else { return }
    self.onContentOffsetChanged?(offset)
  }

  fileprivate let selectedFilterProperty = MutableProperty<DiscoveryParams?>(nil)
  public func selectedFilter(_ params: DiscoveryParams) {
    let changed = self.lastPersonalizationFilter != params
    self.lastPersonalizationFilter = params
    self.selectedFilterProperty.value = params
    if changed, self.sortProperty.value != nil {
      self.hasReadyPersonalizationFilters = true
      if self.hasAppeared { self.onShowPersonalization?(shouldShowPersonalization()) }
    }
  }

  public func signupLoginButtonTapped() {
    self.onGoToLoginSignup?(.discoveryOnboarding)
  }

  private var clearActivityOnDisappear: Bool?
  private var lastRawActivities: [Activity]?
  private var lastVisibleActivities: [Activity]?

  private func publishActivities(_ activities: [Activity]) {
    guard self.lastVisibleActivities != activities else { return }
    self.lastVisibleActivities = activities
    self.onActivitiesForSample?(activities)
  }

  private func receiveActivities(_ activities: [Activity], sort: DiscoveryParams.Sort) {
    guard self.sortProperty.value == sort, self.lastRawActivities != activities else { return }
    self.lastRawActivities = activities
    let unseen = activities.filter { hasNotSeen(activity: $0) }
    saveSeen(activities: unseen)
    self.publishActivities(unseen)
  }
  private var currentNavigationParameters: DiscoveryParams?
  private var currentNavigationProjects: [Project]?
  public func tapped(activity: Activity) {
    guard let project = activity.project else { return }
    if activity.category == .update {
      guard let update = activity.update else { return }
      self.clearActivityOnDisappear = false
      self.onGoToProjectUpdate?(project, update)
    } else {
      self.clearActivityOnDisappear = false
      self.onGoToActivityProject?(project, .activitySample)
    }
  }

  fileprivate let tappedProject = MutableProperty<Project?>(nil)
  public func tapped(project: Project) {
    if let parameters = self.currentNavigationParameters, let projects = self.currentNavigationProjects {
      self.onGoToProjectPlaylist?(project, projects, .fromParams(parameters))
    }
    self.tappedProject.value = project
  }

  fileprivate let userSessionStartedProperty = MutableProperty(())
  public func userSessionStarted() {
    self.userSessionStartedProperty.value = ()
  }

  fileprivate let userSessionEndedProperty = MutableProperty(())
  public func userSessionEnded() {
    self.userSessionEndedProperty.value = ()
  }

  fileprivate let viewDidAppearProperty = MutableProperty(())
  public func viewDidAppear() {
    self.clearActivityOnDisappear = true
    self.hasAppeared = true
    self.viewDidAppearProperty.value = ()
    if self.hasReadyPersonalizationFilters { self.onShowPersonalization?(shouldShowPersonalization()) }
    self.onScrollsToTopChanged?(true)
  }

  fileprivate let viewDidDisappearProperty = MutableProperty(false)
  public func viewDidDisappear(animated: Bool) {
    if animated, self.clearActivityOnDisappear == true { self.publishActivities([]) }
    if !animated { self.clearActivityOnDisappear = true }
    self.viewDidDisappearProperty.value = animated
    self.onScrollsToTopChanged?(false)
  }

  fileprivate let viewWillAppearProperty = MutableProperty(())
  public func viewWillAppear() {
    self.viewWillAppearProperty.value = ()
    if AppEnvironment.current.currentUser == nil { self.publishActivities([]) }
    self.onContentInset?(.zero)
    self.updateVideoFeedBanner()
  }

  private var wasCloseToBottom: Bool?
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    let closeToBottom = row >= totalRows - 3 && row > 0
    guard self.wasCloseToBottom != closeToBottom else { return }
    self.wasCloseToBottom = closeToBottom
    guard closeToBottom, let sort = self.sortProperty.value else { return }
    self.pageTask = self.discoveryFeature.requestNextPage(sort: sort)
  }

  private var connectivity: Reachability = .none
  private var receivedInitialConnectivity = false
  private var lastVideoFeedBanner: Bool?
  private var connectivityObservation: MainActorObservation?

  public var onActivitiesForSample: (([Activity]) -> Void)?
  public let asyncReloadData: Signal<Void, Never>
  public var onContentInset: ((UIEdgeInsets) -> Void)?
  public var onDismissPersonalizationCell: (() -> Void)?
  public var onGoToActivityProject: ((Project, RefTag) -> Void)?
  public var onGoToCuratedProjects: (([KsApi.Category]) -> Void)?
  public var onGoToLoginSignup: ((LoginIntent) -> Void)?
  public var onGoToProjectPlaylist: ((Project, [Project], RefTag) -> Void)?
  public var onGoToProjectUpdate: ((Project, Update) -> Void)?
  public let hideEmptyState: Signal<Void, Never>
  public var onContentOffsetChanged: ((CGPoint) -> Void)?
  public let projectsLoaded: Signal<([Project], DiscoveryParams?), Never>
  public let projectsAreLoadingAnimated: Signal<(Bool, Bool), Never>
  public var onScrollsToTopChanged: ((Bool) -> Void)?
  public let showEmptyState: Signal<EmptyState, Never>
  public var onShowOnboarding: ((Bool) -> Void)?
  public var onShowPersonalization: ((Bool) -> Void)?
  private var hasCurrentUserValue = false
  private var onboardingUser: User?
  private var lastOnboarding: Bool?
  private var hasAppeared = false
  private var hasReadyPersonalizationFilters = false
  private var lastPersonalizationFilter: DiscoveryParams?
  private func updateOnboarding() {
    guard self.hasCurrentUserValue, let parameters = self.currentNavigationParameters else { return }
    let visible = self.onboardingUser == nil && parameters.sort == .magic
    guard self.lastOnboarding != visible else { return }
    self.lastOnboarding = visible
    self.onShowOnboarding?(visible)
  }
  public var onVideoFeedBannerChanged: ((Bool) -> Void)?

  private func updateVideoFeedBanner() {
    let visible = featureVideoFeedEnabled() && self.connectivity != .none
    guard self.lastVideoFeedBanner != visible else { return }
    self.lastVideoFeedBanner = visible
    self.onVideoFeedBannerChanged?(visible)
  }

  public var inputs: DiscoveryPageViewModelInputs { return self }
  public var outputs: DiscoveryPageViewModelOutputs { return self }
}

@MainActor
private func hasNotSeen(activity: Activity) -> Bool {
  return activity.id != AppEnvironment.current.userDefaults.lastSeenActivitySampleId
}

@MainActor
private func saveSeen(activities: [Activity]) {
  activities.forEach { activity in
    AppEnvironment.current.userDefaults.lastSeenActivitySampleId = activity.id
  }
}

private func shouldShowPersonalization() -> Bool {
  return false
}

@MainActor
private func cachedCategories() -> [KsApi.Category]? {
  guard let data = AppEnvironment.current.userDefaults.onboardingCategories,
        let categories = try? JSONDecoder().decode([KsApi.Category].self, from: data)
  else {
    return []
  }

  return categories
}

@MainActor
private func emptyState(forParams params: DiscoveryParams) -> EmptyState? {
  if params.starred == .some(true) {
    return .starred
  } else if params.recommended == .some(true) {
    return .recommended
  } else if params.social == .some(true) {
    return AppEnvironment.current.currentUser?.social == .some(true) ? .socialNoPledges : .socialDisabled
  }

  return nil
}
