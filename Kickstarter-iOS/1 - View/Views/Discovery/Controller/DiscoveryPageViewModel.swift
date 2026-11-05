import KsApi
import Prelude
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
  var onAsyncReloadData: (() -> Void)? { get set }

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
  var onHideEmptyState: (() -> Void)? { get set }

  /// Emits with the current contentOffset.
  var onContentOffsetChanged: ((CGPoint) -> Void)? { get set }

  /// Emits a list of projects that should be shown, and the corresponding filter request params
  var onProjectsLoaded: (([Project], DiscoveryParams?) -> Void)? { get set }

  /// Emits a boolean that determines if projects are currently loading or not.
  var onProjectsLoadingChanged: ((Bool, Bool) -> Void)? { get set }

  /// Emits a bool to allow status bar tap to scroll the table view to the top.
  var onScrollsToTopChanged: ((Bool) -> Void)? { get set }

  /// Emits to show the empty state controller.
  var onShowEmptyState: ((EmptyState) -> Void)? { get set }

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
  private var discoveryObservation: MainActorObservation?
  internal private(set) var pageTask: Task<Void, Never>?
  internal private(set) var activityTask: Task<Void, Never>?

  public init(discoveryFeature: DiscoveryFeature? = nil) {
    let discoveryFeature = discoveryFeature ?? AppModel.shared.discoveryFeature
    self.discoveryFeature = discoveryFeature
    self.discoveryObservation = discoveryFeature.observe { [weak self] update in
      guard let self else { return }
      switch update {
      case let .projects(sort, projects):
        if sort == self.currentSort { self.receiveProjects(projects) }
      case let .loading(sort, loading):
        if sort == self.currentSort { self.receiveLoading(loading) }
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

  private var previousEnvironment: EnvironmentType?
  public func currentEnvironmentChanged(environment: EnvironmentType) {
    guard self.previousEnvironment != environment else { return }
    self.previousEnvironment = environment
    self.refreshLastReadyFeed()
  }

  public func blockedUser() { self.refreshLastReadyFeed() }

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

  public func pulledToRefresh() {
    self.hasPulledToRefresh = true
    self.refreshLastReadyFeed()
  }

  private var currentSort: DiscoveryParams.Sort?
  public func configureWith(sort: DiscoveryParams.Sort) {
    self.currentSort = sort
    self.publishParametersIfReady()
  }

  private var visible: Bool?
  private var hasWillAppeared = false
  private var lastReadyParameters: DiscoveryParams?
  private var lastReadyUser: User?
  private var hasReadyUser = false

  private func refreshCurrentUser() {
    let user = AppEnvironment.current.currentUser
    guard !self.hasCurrentUserValue || self.onboardingUser != user else { return }
    self.hasCurrentUserValue = true
    self.onboardingUser = user
    self.refreshIfInputsChanged()
    self.updateOnboarding()
  }
  private func publishParametersIfReady() {
    guard let sort = self.currentSort, let filter = self.selectedFilterValue else { return }
    let parameters = DiscoveryParams.lens.sort.set(sort, filter)
    let hadParameters = self.currentNavigationParameters != nil
    self.currentNavigationParameters = parameters
    self.clearActivityOnDisappear = true
    self.refreshIfInputsChanged()
    self.updateOnboarding()
    self.updateEmptyState()
    if hadParameters { self.onHideEmptyState?() }
  }
  private func refreshIfInputsChanged() {
    guard self.visible == true, self.hasCurrentUserValue, let parameters = self.currentNavigationParameters else { return }
    guard !self.hasReadyUser || self.lastReadyUser != self.onboardingUser || self.lastReadyParameters != parameters else { return }
    self.hasReadyUser = true
    self.lastReadyUser = self.onboardingUser
    self.lastReadyParameters = parameters
    self.requestFirstPage(parameters)
  }
  private func refreshLastReadyFeed() {
    guard let parameters = self.lastReadyParameters else { return }
    self.requestFirstPage(parameters)
  }
  private func requestFirstPage(_ parameters: DiscoveryParams) {
    guard let sort = self.currentSort else { return }
    self.pageTask = self.discoveryFeature.requestRefresh(sort: sort, parameters: parameters, force: true)
    if self.hasWillAppeared { AppEnvironment.current.ksrAnalytics.trackDiscovery(params: parameters) }
  }

  private var hasPulledToRefresh = false
  private var hasAppearedForLoading = false
  private var lastRefreshLoading: Bool?
  private var lastNonRefreshLoading: Bool?
  private var lastPublishedLoading: (Bool, Bool)?

  private func publishLoading(_ loading: Bool, animated: Bool) {
    if let previous = self.lastPublishedLoading, previous.0 == loading, previous.1 == animated { return }
    self.lastPublishedLoading = (loading, animated)
    self.currentProjectsLoading = loading
    self.updateEmptyState()
    self.publishContentOffsetIfReady()
    self.onProjectsLoadingChanged?(loading, animated)
  }
  private func publishNonRefreshLoading(_ loading: Bool) {
    guard self.lastNonRefreshLoading != loading else { return }
    self.lastNonRefreshLoading = loading
    self.publishLoading(loading, animated: false)
  }
  private func updateRefreshLoading(_ loading: Bool) {
    guard self.lastRefreshLoading != loading else { return }
    self.lastRefreshLoading = loading
    self.publishNonRefreshLoading(false)
    self.publishLoading(loading, animated: true)
  }
  private func receiveLoading(_ loading: Bool) {
    self.publishNonRefreshLoading(loading)
    if self.hasPulledToRefresh { self.updateRefreshLoading(loading) }
  }

  private var lastPaginatedProjects: [Project]?
  private var lastEmptyState: EmptyState?
  private func updateEmptyState() {
    guard let parameters = self.currentNavigationParameters,
          self.currentProjectsLoading == false,
          let projects = self.lastPaginatedProjects, projects.isEmpty,
          let state = emptyState(forParams: parameters), self.lastEmptyState != state else { return }
    self.lastEmptyState = state
    self.onShowEmptyState?(state)
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

  private var selectedFilterValue: DiscoveryParams?
  public func selectedFilter(_ params: DiscoveryParams) {
    let changed = self.lastPersonalizationFilter != params
    self.lastPersonalizationFilter = params
    self.selectedFilterValue = params
    self.publishParametersIfReady()
    if changed { self.publishProjectList([]) }
    if changed, self.currentSort != nil {
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
    guard self.currentSort == sort, self.lastRawActivities != activities else { return }
    self.lastRawActivities = activities
    let unseen = activities.filter { hasNotSeen(activity: $0) }
    saveSeen(activities: unseen)
    self.publishActivities(unseen)
  }
  private var currentNavigationParameters: DiscoveryParams?
  private var currentNavigationProjects: [Project]?
  private var hasReceivedNonemptyProjects = false
  private var hasPublishedFirstProjectList = false
  private func publishProjectList(_ projects: [Project]) {
    if !self.hasReceivedNonemptyProjects {
      guard !projects.isEmpty else { return }
      self.hasReceivedNonemptyProjects = true
    }
    guard self.currentNavigationProjects != projects else { return }
    if let parameters = self.currentNavigationParameters {
      if !self.hasPublishedFirstProjectList {
        self.hasPublishedFirstProjectList = true
        self.onAsyncReloadData?()
        self.onHideEmptyState?()
      }
      self.onProjectsLoaded?(projects, parameters)
    }
    self.currentNavigationProjects = projects
  }
  private func receiveProjects(_ projects: [Project]) {
    self.publishProjectList(projects)
    self.lastPaginatedProjects = projects
    self.updateEmptyState()
    if !projects.isEmpty { self.onHideEmptyState?() }
  }
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

  public func tapped(project: Project) {
    if let parameters = self.currentNavigationParameters, let projects = self.currentNavigationProjects {
      self.onGoToProjectPlaylist?(project, projects, .fromParams(parameters))
    }
    if let parameters = self.currentNavigationParameters {
      AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
        page: .discovery, project: project, typeContext: .init(params: parameters),
        location: .discoverAdvanced, params: parameters
      )
    }
  }

  public func userSessionStarted() { self.refreshCurrentUser() }
  public func userSessionEnded() { self.refreshCurrentUser() }

  public func viewDidAppear() {
    self.clearActivityOnDisappear = true
    self.hasAppeared = true
    if self.visible != true { self.visible = true; self.refreshIfInputsChanged() }
    if let sort = self.currentSort, AppEnvironment.current.currentUser != nil {
      self.activityTask = self.discoveryFeature.requestActivitySample(sort: sort)
    }
    if self.hasReadyPersonalizationFilters { self.onShowPersonalization?(shouldShowPersonalization()) }
    self.onScrollsToTopChanged?(true)
  }

  public func viewDidDisappear(animated: Bool) {
    if animated, self.clearActivityOnDisappear == true { self.publishActivities([]) }
    if !animated { self.clearActivityOnDisappear = true }
    self.visible = false
    self.onScrollsToTopChanged?(false)
  }

  public func viewWillAppear() {
    self.refreshCurrentUser()
    self.hasWillAppeared = true
    if let parameters = self.lastReadyParameters {
      AppEnvironment.current.ksrAnalytics.trackDiscovery(params: parameters)
    }
    if !self.hasAppearedForLoading {
      self.hasAppearedForLoading = true
      self.onHideEmptyState?()
      self.publishLoading(true, animated: false)
    }
    if AppEnvironment.current.currentUser == nil { self.publishActivities([]) }
    self.onContentInset?(.zero)
    self.updateVideoFeedBanner()
  }

  private var wasCloseToBottom: Bool?
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    let closeToBottom = row >= totalRows - 3 && row > 0
    guard self.wasCloseToBottom != closeToBottom else { return }
    self.wasCloseToBottom = closeToBottom
    guard closeToBottom, let sort = self.currentSort else { return }
    self.pageTask = self.discoveryFeature.requestNextPage(sort: sort)
  }

  private var connectivity: Reachability = .none
  private var receivedInitialConnectivity = false
  private var lastVideoFeedBanner: Bool?
  private var connectivityObservation: MainActorObservation?

  public var onActivitiesForSample: (([Activity]) -> Void)?
  public var onAsyncReloadData: (() -> Void)?
  public var onContentInset: ((UIEdgeInsets) -> Void)?
  public var onDismissPersonalizationCell: (() -> Void)?
  public var onGoToActivityProject: ((Project, RefTag) -> Void)?
  public var onGoToCuratedProjects: (([KsApi.Category]) -> Void)?
  public var onGoToLoginSignup: ((LoginIntent) -> Void)?
  public var onGoToProjectPlaylist: ((Project, [Project], RefTag) -> Void)?
  public var onGoToProjectUpdate: ((Project, Update) -> Void)?
  public var onHideEmptyState: (() -> Void)?
  public var onContentOffsetChanged: ((CGPoint) -> Void)?
  public var onProjectsLoaded: (([Project], DiscoveryParams?) -> Void)?
  public var onProjectsLoadingChanged: ((Bool, Bool) -> Void)?
  public var onScrollsToTopChanged: ((Bool) -> Void)?
  public var onShowEmptyState: ((EmptyState) -> Void)?
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
