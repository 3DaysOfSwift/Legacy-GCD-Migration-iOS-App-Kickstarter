import KsApi
import UIKit

@MainActor
final class DiscoveryViewModel {
  enum Event {
    case configurePager([DiscoveryParams.Sort])
    case configureSortPager([DiscoveryParams.Sort])
    case navigationHeader(DiscoveryParams)
    case loadFilter(DiscoveryParams)
    case navigate(DiscoveryParams.Sort, UIPageViewController.NavigationDirection)
    case selectSort(DiscoveryParams.Sort)
    case sortsEnabled(Bool)
    case pagerStyle(Int?)
  }
  var onEvent: ((Event) -> Void)?
  private let discoveryFeature: DiscoveryFeature
  private let deferInitial: @MainActor (@escaping @MainActor () -> Void) -> Void
  private let sorts: [DiscoveryParams.Sort] = [.magic, .popular, .newest, .endingSoon]
  private var didConfigure = false
  private var filterReady = false
  private var didAppear = false
  private var recommendationsChanged = false
  private var initialParameters: DiscoveryParams?
  private var currentParameters: DiscoveryParams?
  private var pendingPage: Int?
  private var selectedSort: DiscoveryParams.Sort?
  private var previousNavigation: (DiscoveryParams.Sort, Bool) = (.magic, true)
  private var lastNavigation: (DiscoveryParams.Sort, Bool)?
  private var previousUserSort: DiscoveryParams.Sort = .magic
  private var lastPagerStyle: Int??

  init(discoveryFeature: DiscoveryFeature? = nil, deferInitial: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { action in
    Task { @MainActor in await Task.yield(); action() }
  }) {
    self.discoveryFeature = discoveryFeature ?? AppModel.shared.discoveryFeature
    self.deferInitial = deferInitial
  }

  func viewDidLoad() { self.configurePagerIfNeeded() }
  func remoteConfigClientConfigured() { self.configurePagerIfNeeded() }
  func remoteConfigClientConfigurationFailed() { self.configurePagerIfNeeded() }

  private func configurePagerIfNeeded() {
    guard !self.didConfigure else { return }
    self.didConfigure = true
    self.onEvent?(.configurePager(self.sorts))
    self.onEvent?(.configureSortPager(self.sorts))
    self.deferInitial { [weak self] in
      guard let self else { return }
      self.filterReady = true
      if let params = self.currentParameters { self.publishFilter(params) }
    }
  }

  func didChangeRecommendationsSetting() { self.recommendationsChanged = true }

  func viewWillAppear(animated _: Bool) {
    guard !self.didAppear || self.recommendationsChanged else { return }
    self.didAppear = true
    let params = DiscoveryFeature.initialParameters(for: AppEnvironment.current.currentUser)
    guard self.initialParameters != params else { return }
    self.initialParameters = params
    self.selectParameters(params)
  }

  func filter(withParams params: DiscoveryParams) {
    self.selectParameters(params)
    let categoryID = params.category?.intID
    if self.lastPagerStyle == nil || self.lastPagerStyle! != categoryID {
      self.lastPagerStyle = .some(categoryID)
      self.onEvent?(.pagerStyle(categoryID))
    }
  }

  private func selectParameters(_ params: DiscoveryParams) {
    self.discoveryFeature.selectFilter(params)
    guard self.currentParameters != params else { return }
    self.currentParameters = params
    if let sort = params.sort { self.changeSort(sort, fromSwipe: false, isUserAction: false) }
    if self.filterReady { self.publishFilter(params) }
  }

  private func publishFilter(_ params: DiscoveryParams) {
    self.onEvent?(.navigationHeader(params))
    self.onEvent?(.loadFilter(params))
  }

  func setSortsEnabled(_ enabled: Bool) { self.onEvent?(.sortsEnabled(enabled)) }
  func willTransition(toPage nextPage: Int) { self.pendingPage = nextPage }
  func pageTransition(completed: Bool) {
    guard completed, let page = self.pendingPage, self.sorts.indices.contains(page) else { return }
    self.changeSort(self.sorts[page], fromSwipe: true, isUserAction: true)
  }
  func sortPagerSelected(sort: DiscoveryParams.Sort) {
    self.changeSort(sort, fromSwipe: false, isUserAction: true)
  }

  private func changeSort(_ sort: DiscoveryParams.Sort, fromSwipe: Bool, isUserAction: Bool) {
    if self.selectedSort != sort {
      self.selectedSort = sort
      self.onEvent?(.selectSort(sort))
    }
    let event = (sort, fromSwipe)
    if self.lastNavigation?.0 != event.0 || self.lastNavigation?.1 != event.1 {
      let previous = self.previousNavigation
      self.lastNavigation = event
      self.previousNavigation = event
      if !fromSwipe {
        let lhs = self.sorts.firstIndex(of: sort) ?? -1
        let rhs = self.sorts.firstIndex(of: previous.0) ?? 9_999
        self.onEvent?(.navigate(sort, lhs < rhs ? .reverse : .forward))
      }
    }
    if isUserAction, self.previousUserSort != sort {
      if let params = self.currentParameters {
        AppEnvironment.current.ksrAnalytics.trackDiscoverySelectedSort(
          prevSort: self.previousUserSort, params: params,
          discoverySortContext: self.getDiscoverySortTypeContext(from: sort)
        )
      }
      self.previousUserSort = sort
    }
  }

  /// convert DiscoveryParams.Sort to TypeContext.DiscoverySortContext
  private func getDiscoverySortTypeContext(
    from sort: DiscoveryParams.Sort
  ) -> KSRAnalytics.TypeContext.DiscoverySortContext {
    switch sort {
    case .endingSoon: return .endingSoon
    case .magic: return .magic
    case .newest: return .newest
    case .popular: return .popular
    default:
      assert(
        false,
        "The other sort types were added for GraphQL compatibility, and should never come up in V1 Discover."
      )
      return .magic
    }
  }

}
