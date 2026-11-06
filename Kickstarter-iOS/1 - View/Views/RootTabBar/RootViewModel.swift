import KsApi
import Prelude
import ReactiveSwift
import UIKit

public typealias RootViewControllerIndex = Int
public typealias RootTabBarItemBadgeValueData = (String?, RootViewControllerIndex)

public enum RootViewControllerData: Equatable {
  case discovery
  case activities
  case pledgedProjectsAndActivities
  case search
  case profile(isLoggedIn: Bool)

  public static func == (lhs: RootViewControllerData, rhs: RootViewControllerData) -> Bool {
    switch (lhs, rhs) {
    case (.discovery, .discovery): return true
    case (.activities, .activities): return true
    case (.pledgedProjectsAndActivities, .pledgedProjectsAndActivities): return true
    case (.search, .search): return true
    case let (.profile(lhsIsLoggedIn), .profile(rhsIsLoggedIn)):
      return lhsIsLoggedIn == rhsIsLoggedIn
    default:
      return false
    }
  }

  var isProfile: Bool {
    switch self {
    case .profile:
      return true
    default:
      return false
    }
  }

  var isActivity: Bool {
    switch self {
    case .activities, .pledgedProjectsAndActivities:
      return true
    case .discovery, .profile, .search:
      return false
    }
  }
}

public struct TabBarItemsData {
  public let items: [TabBarItem]
  public let isLoggedIn: Bool
}

public enum TabBarItem {
  case activity(index: RootViewControllerIndex)
  case home(index: RootViewControllerIndex)
  case profile(avatarUrl: URL?, index: RootViewControllerIndex)
  case search(index: RootViewControllerIndex)
}

@MainActor
public protocol RootViewModelInputs {
  /// Call when the application will enter foreground.
  func applicationWillEnterForeground()

  /// Call when the controller has received a user updated notification.
  @discardableResult func requestAvatar(url: URL?, index: Int, isLoggedIn: Bool) -> Task<Void, Never>?
  func currentUserUpdated()

  /// Call when a badge value was received via push notification.
  func didReceiveBadgeValue(_ value: Int?)

  /// Call when selected tab bar index changes.
  func didSelect(index: RootViewControllerIndex)

  /// Call before selected tab bar index changes.
  func shouldSelect(index: RootViewControllerIndex?)

  /// Call when we should switch to the activities tab.
  func switchToActivities()

  /// Call when we should switch to the discovery tab.
  func switchToDiscovery(params: DiscoveryParams?)

  /// Call when we should switch to the login tab.
  func switchToLogin()

  /// Call when we should switch to the profile tab.
  func switchToProfile()

  /// Call when we should switch to the search tab.
  func switchToSearch()

  /// Call when the a user locale preference has changed.
  /// Used to blow away and re-generate all the tabs, so the entire app reflects changes in user language or currency.
  /// See PR #576.
  func userLocalePreferencesChanged()

  /// Call when the controller has received a user session ended notification.
  func userSessionEnded()

  /// Call when the controller has received a user session started notification.
  func userSessionStarted()

  /// Call from the controller's `viewDidLoad` method.
  func viewDidLoad()

  /// Call when VoiceOver is enabled or disabled
  func voiceOverStatusDidChange()
}

@MainActor
public protocol RootViewModelOutputs: AnyObject {
  /// Emits when the discovery VC should filter with specific params.
  var onFilterDiscovery: (((RootViewControllerIndex, DiscoveryParams)) -> Void)? { get set }

  /// Emits a controller index that should be scrolled to the top. This requires figuring out what kind of
  /// controller it is, and setting its `contentOffset`.
  var onScrollToTop: ((RootViewControllerIndex) -> Void)? { get set }

  /// Emits an index that the tab bar should be switched to.
  var onSelectedIndex: ((RootViewControllerIndex) -> Void)? { get set }

  /// Emits the badge value to be set at a particular tab index
  var onSetBadgeValue: ((RootTabBarItemBadgeValueData) -> Void)? { get set }

  /// Emits the array of view controllers that should be set on the tab bar.
  var setViewControllers: Signal<[RootViewControllerData], Never> { get }

  /// Emits data for setting tab bar item styles.
  var onAvatarImage: ((Data, URL, Int) -> Void)? { get set }
  var tabBarItemsData: Signal<TabBarItemsData, Never> { get }

  /// Emits an already committed User for the existing user-updated notification.
  var onUserUpdated: ((User) -> Void)? { get set }

  /// Emits when the floating tab bar feature is enabled or disabled.
  var floatingTabBarEnabled: Signal<Bool, Never> { get }
}

@MainActor
public protocol RootViewModelType {
  var inputs: RootViewModelInputs { get }
  var outputs: RootViewModelOutputs { get }
}

@MainActor
public final class RootViewModel: RootViewModelType, RootViewModelInputs, RootViewModelOutputs {
  private let profileFeature: ProfileFeature
  private var sessionFeature: SessionFeature { self.profileFeature.sessionFeature }
  private var latestSelectedIndex: RootViewControllerIndex?
  private var lastUserSelectedIndex = 0
  private var previousUserSelectedIndex = 0
  private var hasUserSelection = false
  private var latestTabBarData: TabBarItemsData?
  private var lastSearchOrigin: KSRAnalytics.TabBarItemLabel?
  private var requestedIndex: RootViewControllerIndex?
  private var controllerCount: Int?
  private var latestLoginState: Bool?
  private var hasLoadedRootView = false
  private var loadingRootView = false
  private var discoveryIndex: RootViewControllerIndex?
  private var activityIndex: RootViewControllerIndex?
  private var currentBadgeValue: String?
  private var lastBadgeInput: (Int?, RootViewControllerIndex)?
  private var avatarTask: Task<Void, Never>?
  private var avatarID: UUID?
  private var avatarInput: (URL, Int, Int)?
  public var onAvatarImage: ((Data, URL, Int) -> Void)?
  private var badgeTask: Task<Void, Never>?
  private var badgePresentationTasks: [UUID: Task<Void, Never>] = [:]
  private var badgeIdentity: (userID: Int, generation: Int, token: UUID)?

  public init(profileFeature: ProfileFeature? = nil) {
    let profileFeature = profileFeature ?? AppModel.shared.profileFeature
    self.profileFeature = profileFeature
    let currentUser = Signal.merge(
      self.viewDidLoadProperty.signal,
      self.userSessionStartedProperty.signal,
      self.userSessionEndedProperty.signal,
      self.currentUserUpdatedProperty.signal
    )
    .map { _ in AppEnvironment.current.currentUser }

    let loginState: Signal<Bool, Never> = currentUser
      .map {
        $0 != nil
      }
      .skipRepeats(==)


    /// This flag allows us to control the refresh of the tab bar when toggling on the Remote Config floating tab bar FF.
    /// On first launch we intentionally default to the standard tab bar.
    /// The flag is refreshed when the app returns to the foreground.
    let featuredFlagChanged = Signal.merge(
      self.viewDidLoadProperty.signal,
      self.applicationWillEnterForegroundSignal.signal
    )
    .map { _ in featureFloatingTabBarEnabled() }
    .skipRepeats()
    .skip(first: 1)

    let floatingTabBarEnabled = Signal.merge(
      self.viewDidLoadProperty.signal,
      featuredFlagChanged.ignoreValues()
    )
    .map { _ in featureFloatingTabBarEnabled() }
    .skipRepeats()

    self.floatingTabBarEnabled = floatingTabBarEnabled

    let standardViewControllers: Signal<[RootViewControllerData], Never> = Signal
      .combineLatest(loginState, floatingTabBarEnabled)
      .map { isLoggedIn, isFloatingTabBarEnabled -> [RootViewControllerData] in
        generateViewControllers(
          isLoggedIn: isLoggedIn,
          isFloatingTabBarEnabled: isFloatingTabBarEnabled
        )
      }

    self.setViewControllers = Signal.merge(
      standardViewControllers,
      // FIXME: Look at moving the userLocalePreferencesChangedProperty signal into the currentUser signal
      // https://kickstarter.atlassian.net/browse/MBL-2053
      Signal
        .combineLatest(loginState, floatingTabBarEnabled)
        .takeWhen(
          Signal.merge(
            self.userLocalePreferencesChangedProperty.signal,
            featuredFlagChanged.ignoreValues()
          )
        )
        .map { isLoggedIn, isFloatingTabBarEnabled -> [RootViewControllerData] in
          generateViewControllers(
            isLoggedIn: isLoggedIn,
            isFloatingTabBarEnabled: isFloatingTabBarEnabled
          )
        }
    )

    // FIXME: This signal always needs to happen when setViewControllers happens.
    // Should they be combined into one signal with a tuple? Explicitly made dependent on one another?
    // See https://kickstarter.atlassian.net/browse/MBL-2053
    self.tabBarItemsData = Signal.combineLatest(
      currentUser, floatingTabBarEnabled, .merge(
        self.viewDidLoadProperty.signal,
        featuredFlagChanged.ignoreValues(),
        self.userLocalePreferencesChangedProperty.signal
      )
    )
    .map { user, isFloatingTabBarEnabled, _ in (user, isFloatingTabBarEnabled) }
    .map { user, isFloatingTabBarEnabled in
      tabData(forUser: user, isFloatingTabBarEnabled: isFloatingTabBarEnabled)
    }

    self.tabBarItemsData.observeValues { [weak self] data in
      guard let self else { return }
      self.latestTabBarData = data
      self.trackSearchSelectionIfNeeded()
    }

    loginState.observeValues { [weak self] in self?.latestLoginState = $0 }
    self.setViewControllers.observeValues { [weak self] controllers in
      guard let self else { return }
      self.controllerCount = controllers.count
      if let index = controllers.firstIndex(of: .discovery) { self.discoveryIndex = index }
      if let index = controllers.firstIndex(where: \.isActivity) {
        self.activityIndex = index
        self.clearBadgeIfActivitySelected()
      }
      if !self.loadingRootView { self.publishSelectedIndexIfReady() }
    }
  }

  private func trackSearchSelectionIfNeeded() {
    guard self.hasUserSelection, let data = self.latestTabBarData, !data.items.isEmpty,
          data.items.indices.contains(self.lastUserSelectedIndex),
          tabBarItemLabel(for: data.items[self.lastUserSelectedIndex]) == .search else { return }
    let previous = data.items.indices.contains(self.previousUserSelectedIndex) ? self.previousUserSelectedIndex : 0
    let origin = tabBarItemLabel(for: data.items[previous])
    guard self.lastSearchOrigin != origin else { return }
    self.lastSearchOrigin = origin
    AppEnvironment.current.ksrAnalytics.trackSearchTabBarClicked(prevTabBarItemLabel: origin)
  }

  private func trackTabSelection(_ index: Int) {
    self.previousUserSelectedIndex = self.lastUserSelectedIndex
    self.lastUserSelectedIndex = index
    self.hasUserSelection = true
    self.trackSearchSelectionIfNeeded()
    guard let data = self.latestTabBarData, !data.items.isEmpty, data.items.indices.contains(index) else { return }
    let previous = data.items.indices.contains(self.previousUserSelectedIndex) ? self.previousUserSelectedIndex : 0
    AppEnvironment.current.ksrAnalytics.trackTabBarClicked(
      tabBarItemLabel: tabBarItemLabel(for: data.items[index]),
      previousTabBarItemLabel: tabBarItemLabel(for: data.items[previous])
    )
  }

  private func selectIndex(_ index: RootViewControllerIndex) {
    self.requestedIndex = index
    self.publishSelectedIndexIfReady()
  }

  private func publishSelectedIndexIfReady() {
    guard self.hasLoadedRootView, let requestedIndex = self.requestedIndex,
          let count = self.controllerCount, count > 0 else { return }
    let index = clamp(0, count - 1)(requestedIndex)
    self.latestSelectedIndex = index
    self.onSelectedIndex?(index)
    self.clearBadgeIfActivitySelected()
  }

  private func updateBadge(_ value: Int?, index: RootViewControllerIndex) {
    self.lastBadgeInput = (value, index)
    let hasPPOAction = AppEnvironment.current.currentUserPPOSettings?.hasAction ?? false
    let displayed = activitiesBadgeValue(with: value, hasPPOAction: hasPPOAction)
    self.currentBadgeValue = displayed
    self.onSetBadgeValue?((displayed, index))
  }

  private func clearBadgeIfActivitySelected() {
    guard let activityIndex = self.activityIndex, self.latestSelectedIndex == activityIndex,
          self.currentBadgeValue != nil else { return }
    self.updateBadge(AppEnvironment.current.currentUser?.erroredBackingsCount, index: activityIndex)
    self.clearActivityBadge()
  }

  private func clearActivityBadge() {
    guard let userID = self.sessionFeature.currentUser?.id else { return }
    let generation = self.sessionFeature.generation
    if self.badgeIdentity?.userID == userID, self.badgeIdentity?.generation == generation { return }
    self.badgeTask?.cancel() // Presentation only; the admitted shared write continues.
    let token = UUID()
    let sessionFeature = self.sessionFeature
    let request = sessionFeature.request(.clearActivity)
    self.badgeIdentity = (userID, generation, token)
    self.badgeTask = Task { [weak self] in
      defer {
        if self?.badgeIdentity?.token == token {
          self?.badgeTask = nil
          self?.badgeIdentity = nil
        }
      }
      do {
        let user = try await request.value
        try Task.checkCancellation()
        guard sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.scheduleBadgePresentation(user, generation: generation)
      } catch {
        // Preserve silent badge-save failure; the shared throwing command is tested separately.
      }
    }
  }

  private func scheduleBadgePresentation(_ user: User, generation: Int) {
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    guard !delay.isInfinite else { return }
    let id = UUID()
    self.badgePresentationTasks[id] = Task { [weak self] in
      defer { self?.badgePresentationTasks[id] = nil }
      do {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        guard let self, self.sessionFeature.isCurrent(userID: user.id, generation: generation) else { return }
        self.onUserUpdated?(user)
      } catch { /* Cancellation ends pending presentation. */ }
    }
  }

  func waitForBadgeUpdate() async { await self.badgeTask?.value }
  func waitForBadgePresentation() async {
    for task in self.badgePresentationTasks.values { await task.value }
  }

  @discardableResult public func requestAvatar(url: URL?, index: Int, isLoggedIn: Bool) -> Task<Void, Never>? {
    let generation = self.sessionFeature.generation
    if isLoggedIn, let url, let input = self.avatarInput,
      input.0 == url, input.1 == index, input.2 == generation, self.avatarTask != nil { return self.avatarTask }
    self.avatarTask?.cancel()
    self.avatarID = nil
    self.avatarInput = nil
    guard isLoggedIn, let url else { self.profileFeature.cancelAvatar(); self.avatarTask = nil; return nil }
    let id = UUID()
    self.avatarID = id
    self.avatarInput = (url, index, generation)
    let feature = self.profileFeature
    self.avatarTask = Task { [weak self] in
      defer { if self?.avatarID == id { self?.avatarTask = nil } }
      do {
        let data = try await feature.avatar(url: url)
        try Task.checkCancellation()
        guard let self, self.avatarID == id else { return }
        self.onAvatarImage?(data, url, index)
      } catch { /* Keep the existing profile icon on a failed image read. */ }
    }
    return self.avatarTask
  }

  deinit {
    self.badgeTask?.cancel()
    self.badgePresentationTasks.values.forEach { $0.cancel() }
    self.avatarTask?.cancel()
  }

  private let (applicationWillEnterForegroundSignal, applicationWillEnterForegroundObserver)
    = Signal<(), Never>.pipe()
  public func applicationWillEnterForeground() {
    let previousIndex = self.activityIndex
    self.applicationWillEnterForegroundObserver.send(value: ())
    if let index = previousIndex {
      self.updateBadge(AppEnvironment.current.application.applicationIconBadgeNumber, index: index)
    }
  }

  fileprivate let currentUserUpdatedProperty = MutableProperty(())
  public func currentUserUpdated() {
    self.currentUserUpdatedProperty.value = ()
    if self.latestSelectedIndex != nil, let index = self.activityIndex {
      self.updateBadge(currentUserActivitiesAndErroredPledgeCount(), index: index)
    }
  }

  public func didReceiveBadgeValue(_ value: Int?) {
    guard self.latestSelectedIndex != nil, let index = self.activityIndex else { return }
    self.updateBadge(value, index: index)
  }

  public func didSelect(index: Int) {
    self.trackTabSelection(index)
    self.selectIndex(index)
  }

  public func shouldSelect(index: Int?) {
    guard let index, index == self.latestSelectedIndex else { return }
    self.onScrollToTop?(index)
  }

  public func switchToActivities() {
    self.selectIndex(1)
  }

  public func switchToDiscovery(params: DiscoveryParams?) {
    self.selectIndex(0)
    if let params, let index = self.discoveryIndex { self.onFilterDiscovery?((index, params)) }
  }

  public func switchToLogin() {
    guard self.latestLoginState == false, let count = self.controllerCount else { return }
    self.selectIndex(count)
  }

  public func switchToProfile() {
    guard self.latestLoginState == true, let count = self.controllerCount else { return }
    self.selectIndex(count)
  }

  public func switchToSearch() {
    self.selectIndex(2)
  }

  fileprivate let userLocalePreferencesChangedProperty = MutableProperty(())
  public func userLocalePreferencesChanged() {
    self.userLocalePreferencesChangedProperty.value = ()
  }

  fileprivate let userSessionStartedProperty = MutableProperty(())
  public func userSessionStarted() {
    self.userSessionStartedProperty.value = ()
  }

  fileprivate let userSessionEndedProperty = MutableProperty(())
  public func userSessionEnded() {
    self.userSessionEndedProperty.value = ()
    if let index = self.activityIndex { self.updateBadge(nil, index: index) }
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    let previousIndex = self.activityIndex
    self.loadingRootView = true
    self.viewDidLoadProperty.value = ()
    self.loadingRootView = false
    self.hasLoadedRootView = true
    self.selectIndex(0)
    if let index = previousIndex {
      self.updateBadge(AppEnvironment.current.application.applicationIconBadgeNumber, index: index)
    }
  }

  public func voiceOverStatusDidChange() {
    if let (value, index) = self.lastBadgeInput { self.updateBadge(value, index: index) }
  }

  public var onFilterDiscovery: (((RootViewControllerIndex, DiscoveryParams)) -> Void)?
  public var onScrollToTop: ((RootViewControllerIndex) -> Void)?
  public var onSelectedIndex: ((RootViewControllerIndex) -> Void)?
  public var onSetBadgeValue: ((RootTabBarItemBadgeValueData) -> Void)?
  public let setViewControllers: Signal<[RootViewControllerData], Never>
  public let tabBarItemsData: Signal<TabBarItemsData, Never>
  public var onUserUpdated: ((User) -> Void)?
  public let floatingTabBarEnabled: Signal<Bool, Never>

  public var inputs: RootViewModelInputs { return self }
  public var outputs: RootViewModelOutputs { return self }
}

@MainActor
private func currentUserActivitiesAndErroredPledgeCount() -> Int {
  return (AppEnvironment.current.currentUser?.unseenActivityCount ?? 0)
}

private func generateViewControllers(
  isLoggedIn: Bool,
  isFloatingTabBarEnabled: Bool
) -> [RootViewControllerData] {
  var controllers: [RootViewControllerData] = []
  controllers.append(.discovery)

  guard isFloatingTabBarEnabled == false else {
    controllers.append(.search)
    controllers.append(.profile(isLoggedIn: isLoggedIn))

    return controllers
  }

  if isLoggedIn {
    controllers.append(.pledgedProjectsAndActivities)
  } else {
    controllers.append(.activities)
  }

  controllers.append(.search)
  controllers.append(.profile(isLoggedIn: isLoggedIn))

  return controllers
}

private func tabData(forUser user: User?, isFloatingTabBarEnabled: Bool) -> TabBarItemsData {
  var items: [TabBarItem] = []

  if isFloatingTabBarEnabled {
    items = [
      .home(index: 0),
      .search(index: 1),
      .profile(avatarUrl: (user?.avatar.small).flatMap(URL.init(string:)), index: 2)
    ]
  } else {
    items = [
      .home(index: 0), .activity(index: 1), .search(index: 2),
      .profile(avatarUrl: (user?.avatar.small).flatMap(URL.init(string:)), index: 3)
    ]
  }

  return TabBarItemsData(
    items: items,
    isLoggedIn: user != nil
  )
}

extension TabBarItemsData: Equatable {}
extension TabBarItem: Equatable {}

@MainActor
private func activitiesBadgeValue(with value: Int?, hasPPOAction: Bool) -> String? {
  guard !hasPPOAction else {
    // an empty string will show a dot as badge
    return ""
  }

  let isVoiceOverRunning = AppEnvironment.current.isVoiceOverRunning()
  let badgeValue = value ?? 0
  let maxBadgeValue = !isVoiceOverRunning ? 99 : badgeValue
  let clampedBadgeValue = min(badgeValue, maxBadgeValue)

  guard clampedBadgeValue > 0 else { return nil }

  return (badgeValue > maxBadgeValue) && !isVoiceOverRunning
    ? Strings.activities_badge_value_plus(activities_badge_value: "\(clampedBadgeValue)")
    : "\(clampedBadgeValue)"
}

private func tabBarItemLabel(for tabBarItem: TabBarItem) -> KSRAnalytics.TabBarItemLabel {
  switch tabBarItem {
  case .activity:
    return .activity
  case .home:
    return .discovery
  case .profile:
    return .profile
  case .search:
    return .search
  }
}
