import Foundation
import KsApi
import Prelude
import ReactiveSwift

public typealias SearchResultCard = ProjectCardProperties

public struct SearchResults {
  public let isProjectsTitleVisible: Bool
  public let count: Int
  public let projects: [BackerDashboardProjectCellViewModel.ProjectCellModel]

  public init(
    isProjectsTitleVisible: Bool,
    count: Int,
    projects: [BackerDashboardProjectCellViewModel.ProjectCellModel]
  ) {
    self.isProjectsTitleVisible = isProjectsTitleVisible
    self.count = count
    self.projects = projects
  }
}

@MainActor
public protocol SearchViewModelInputs {
  /// Call when the user enters a new search term.
  func searchTextChanged(_ searchText: String)

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when the view will appear.
  func viewWillAppear(animated: Bool)

  /// Call when a project is tapped.
  func tapped(projectAtIndex index: Int)

  /// Call this when the user taps on a button to show one of the sort options.
  func tappedButton(forFilterType type: SearchFilterPill.FilterType)

  /// Call this when the user updates a sort or filter option
  func selectedFilter(_ event: SearchFilterEvent)

  /// Call this when the user types a location query string in the location filter
  func searchedForLocations(_ query: String)

  /// Call this when the user taps reset on a filter modal
  func resetFilters(for: SearchFilterModalType)

  /**
   Call from the controller's `tableView:willDisplayCell:forRowAtIndexPath` method.

   - parameter row:       The 0-based index of the row displaying.
   - parameter totalRows: The total number of rows in the table view.
   */
  func willDisplayProjectAtRow(_ row: Int, outOf totalProjects: Int)
}

@MainActor
public protocol SearchViewModelOutputs {
  /// Emits a project ID  and ref tag when the project page should be opened.
  var goToProject: Signal<(ProjectPageParam, RefTag), Never> { get }

  /// Used to power the datasource. Emits projects, whether or not to show the "Popular" title, and the results count. May emit an array of empty projects if the page was cleared and new results are loading.
  var searchResults: Signal<SearchResults, Never> { get }

  /// Emits when loading indicator should be hidden.
  var searchLoaderIndicatorIsAnimating: Signal<Bool, Never> { get }

  /// Emits true when no search results should be shown, and false otherwise.
  var showEmptyState: Signal<(DiscoveryParams, Bool), Never> { get }

  /// Sends a model object which can be used to display all filter options, and a type describing which filters to display.
  var showFilters: Signal<SearchFilterModalType, Never> { get }

  /// Emits to show the video feed banner
  var showVideoFeedBanner: Signal<Bool, Never> { get }

  /// An @ObservableObject model which SwiftUI can use to display the search filters modals and header.
  /// Owned and automatically updated by the `SearchFiltersUseCase`.
  var searchFilters: SearchFilters { get }
}

@MainActor
public protocol SearchViewModelType {
  var inputs: SearchViewModelInputs { get }
  var outputs: SearchViewModelOutputs { get }
}

@MainActor
public final class SearchViewModel: SearchViewModelType, SearchViewModelInputs, SearchViewModelOutputs {
  private let searchFeature: SearchFeature
  private let featureBindings = CompositeDisposable()
  private let completionAnalytics: SearchCompletionAnalytics
  // UIKit retains the shared Feature task rather than spawning wrapper Tasks.
  internal private(set) var searchTask: Task<Void, Never>?
  internal private(set) var pageTask: Task<Void, Never>?
  internal private(set) var filterOptionsTask: Task<Void, Never>?
  internal private(set) var locationLookupTask: Task<Void, Never>?

  public init(searchFeature: SearchFeature? = nil) {
    // Resolve the live default inside MainActor, not in a Swift 5 default argument.
    let searchFeature = searchFeature ?? AppModel.shared.searchFeature
    self.searchFeature = searchFeature
    self.searchFiltersUseCase = SearchFiltersUseCase(
      searchFeature: searchFeature,
      categories: searchFeature.categories,
      defaultLocations: searchFeature.defaultLocations,
      suggestedLocations: searchFeature.suggestedLocations
    )
    // Output notification only: query input and first appearance are explicit commands.
    let queryText = self.queryTextPipe.output
    let selection = searchFeature.filterSelection
    // Keep the legacy screen's per-observer initial barrier and every subsequent
    // field notification. This stream reports selection changes; it owns no query.
    let selectionChanges = Signal.combineLatest(
      selection.selectedSort, selection.selectedCategory, selection.selectedState,
      selection.selectedPercentRaisedBucket, selection.selectedLocation,
      selection.selectedAmountRaisedBucket, selection.selectedGoalBucket,
      selection.selectedToggles
    ).ignoreValues()
    let paginatedProjects = searchFeature.paginatedResults
    let isLoading = searchFeature.loading
    let stats = searchFeature.resultCount
    let searchResults = searchFeature.results

    self.searchLoaderIndicatorIsAnimating = isLoading

    // Show the 'Discover projects' title if we're showing 'Discover' results (i.e. no query)
    let isProjectsTitleVisible = Signal.combineLatest(queryText, searchResults)
      .map { query, projects in query.isEmpty && !projects.isEmpty }
      .skipRepeats()

    self.projects = searchResults
      .map { (nodes: [SearchResult]) -> [SearchResultCard] in
        nodes.compactMap { node in
          let fragment = node.fragments.projectCardFragment
          return ProjectCardProperties(fragment)
        }
      }

    let shouldShowEmptyState = Signal.combineLatest(paginatedProjects, isLoading)
      .map { projects, isLoading in
        if isLoading { return false }
        return projects.isEmpty
      }
      .skipRepeats()

    self.showEmptyState = self.queryParametersPipe.output
      .takePairWhen(shouldShowEmptyState)

    self.reachabilityProperty <~ Reachability.signalProducer

    self.showVideoFeedBanner = Signal.merge(
      self.appearancePipe.output,
      self.reachabilityProperty.signal.ignoreValues()
    )
    .map { featureVideoFeedEnabled() && Reachability.current != .none }
    .skipRepeats()

    self.goToProject = self.projectNavigationPipe.output

    // Register analytics before presentation: a zero count or buffered page
    // settlement can track before the corresponding cards are published.
    self.completionAnalytics = SearchCompletionAnalytics(
      counts: stats, pages: searchFeature.pageCount,
      results: paginatedProjects, loading: isLoading
    )

    self.searchResults = Signal.combineLatest(
      isProjectsTitleVisible,
      stats,
      self.projects
    ).map { isProjectsTitleVisible, resultCount, projects in
      SearchResults(
        isProjectsTitleVisible: isProjectsTitleVisible,
        count: resultCount,
        projects: projects.map { $0.projectCellModel }
      )
    }.merge(with: self.initialResultsPipe.output)

    // Bind only after every presentation/analytics observer is installed.
    // These handles belong to this screen, not the app-scoped Feature.
    self.featureBindings += searchResults.observeValues { [weak self] results in
      self?.displayedResults = results
    }
    self.featureBindings += stats.observeValues { [weak self] count in
      self?.appearanceResultsCount = count
    }
    self.featureBindings += self.completionAnalytics.countsToTrack.observeValues { [weak self] count in
      self?.trackResultCompletion(count: count)
    }
    self.featureBindings += selectionChanges.observeValues { [weak self] in
      self?.hasReceivedFilterSelection = true
      self?.refreshSearchIfReady()
    }
    self.featureBindings += searchFeature.loading.observeValues { [weak self] loading in
      if !loading {
        self?.searchTask = nil
        self?.pageTask = nil
      }
    }
  }

  deinit {
    self.featureBindings.dispose()
  }

  // These are presentation snapshots, not duplicate Feature domain state. Nil
  // preserves the old signal prerequisites (no query/results/count emitted yet).
  private var queryText: String?
  private var displayedResults: [SearchResult]?
  private var latestQueryParameters: DiscoveryParams?
  private var appearanceResultsCount: Int?
  private var hasAppearedAnimated = false
  private var hasReceivedFilterSelection = false
  private var wasCloseToBottom: Bool?
  private let queryTextPipe = Signal<String, Never>.pipe()
  private let queryParametersPipe = Signal<DiscoveryParams, Never>.pipe()
  private let appearancePipe = Signal<Void, Never>.pipe()
  private let initialResultsPipe = Signal<SearchResults, Never>.pipe()
  private let projectNavigationPipe = Signal<(ProjectPageParam, RefTag), Never>.pipe()

  public func searchTextChanged(_ searchText: String) {
    self.publishQueryText(searchText)
    // Typed empty text resets filters after query publication. Initial discovery
    // text deliberately does not: an appearance is not a user's clear command.
    self.searchFeature.updateQuery(searchText)
  }

  private func publishQueryText(_ query: String) {
    self.queryText = query
    // Legacy parameter admission preceded query-text presentation observers.
    // Preserve that order, including synchronous cancellation/loading analytics.
    self.refreshSearchIfReady()
    self.queryTextPipe.input.send(value: query)
  }

  private func refreshSearchIfReady() {
    guard self.hasReceivedFilterSelection, let query = self.queryText else { return }
    let parameters = self.searchFeature.queryParameters(for: query)
    self.latestQueryParameters = parameters
    self.queryParametersPipe.input.send(value: parameters)
    self.searchTask = self.searchFeature.requestSearch(parameters: parameters)
  }

  public func tapped(projectAtIndex index: Int) {
    guard let query = self.queryText, let projects = self.displayedResults else { return }
    guard projects.indices.contains(index) else {
      assert(false, "Tapped card out of bounds.")
      return
    }

    let project = projects[index]
    let graphQLID = project.fragments.backerDashboardProjectCellFragment.projectId
    if decompose(id: graphQLID) != nil,
       let card = ProjectCardProperties(project.fragments.projectCardFragment) {
      self.projectNavigationPipe.input.send(value: (
        card.projectPageParam, refTag(query: query, projects: projects, project: project)
      ))
    }

    // A malformed navigation ID did not suppress legacy click analytics.
    if let parameters = self.latestQueryParameters {
      AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
        page: .search,
        project: project.fragments.projectAnalyticsFragment,
        typeContext: .results,
        location: .searchResults,
        params: parameters
      )
    }
  }

  public func viewDidLoad() {
    self.filterOptionsTask = self.searchFeature.requestFilterOptions()
  }

  public func viewWillAppear(animated: Bool) {
    let isFirstAnimatedAppearance = animated && !self.hasAppearedAnimated
    if isFirstAnimatedAppearance {
      self.hasAppearedAnimated = true
      self.publishQueryText("")
    }

    self.appearancePipe.input.send(value: ())
    if isFirstAnimatedAppearance {
      self.appearanceResultsCount = 0
      self.completionAnalytics.recordCount(0)
    }
    if animated { self.trackAppearance() }
    if isFirstAnimatedAppearance {
      self.initialResultsPipe.input.send(value: SearchResults(
        isProjectsTitleVisible: false, count: 0, projects: []
      ))
    }
  }

  private func trackAppearance() {
    guard let query = self.queryText,
          let parameters = self.latestQueryParameters,
          let count = self.appearanceResultsCount else { return }
    AppEnvironment.current.ksrAnalytics.trackProjectSearchView(
      params: parameters, results: query.isEmpty ? 0 : count
    )
  }

  private func trackResultCompletion(count: Int) {
    guard let query = self.queryText, !query.isEmpty,
          let parameters = self.latestQueryParameters else { return }
    AppEnvironment.current.ksrAnalytics.trackProjectSearchView(params: parameters, results: count)
  }

  public func willDisplayProjectAtRow(_ row: Int, outOf totalRows: Int) {
    let isCloseToBottom = row >= totalRows - 3
    guard self.wasCloseToBottom != isCloseToBottom else { return }
    self.wasCloseToBottom = isCloseToBottom
    if isCloseToBottom { self.pageTask = self.searchFeature.requestNextPage() }
  }

  public func tappedButton(forFilterType type: SearchFilterPill.FilterType) {
    self.searchFiltersUseCase.inputs.tappedButton(forFilterType: type)
  }

  public func resetFilters(for type: SearchFilterModalType) {
    self.searchFiltersUseCase.inputs.resetFilters(for: type)
  }

  private let searchFiltersUseCase: SearchFiltersUseCase
  private let reachabilityProperty = MutableProperty(Reachability.current)

  public let goToProject: Signal<(ProjectPageParam, RefTag), Never>
  public let projects: Signal<[SearchResultCard], Never>
  public let searchLoaderIndicatorIsAnimating: Signal<Bool, Never>
  public let showEmptyState: Signal<(DiscoveryParams, Bool), Never>
  public let showVideoFeedBanner: Signal<Bool, Never>
  public let searchResults: Signal<SearchResults, Never>

  public var showFilters: Signal<SearchFilterModalType, Never> {
    return self.searchFiltersUseCase.showFilters
  }

  public func selectedFilter(_ event: SearchFilterEvent) {
    self.searchFeature.selectFilter(event)
  }

  public func searchedForLocations(_ query: String) {
    self.locationLookupTask = self.searchFeature.requestLocations(query)
  }

  public var searchFilters: SearchFilters {
    return self.searchFiltersUseCase.searchFilters
  }

  public var inputs: SearchViewModelInputs { return self }
  public var outputs: SearchViewModelOutputs { return self }
}

/// Owns only the legacy analytics pairing, not search state or request lifetime.
/// A settlement is an emitted result collection while not loading, or loading
/// becoming false after any result collection. Empty/error settlements may wait
/// for a later page ordinal. Do not reset this queue on query changes: the legacy
/// zip retained it, and changing that behaviour needs a separate product decision.
@MainActor
private final class SearchCompletionAnalytics {
  private let bindings = CompositeDisposable()
  private let countsPipe = Signal<Int, Never>.pipe()
  var countsToTrack: Signal<Int, Never> { self.countsPipe.output }
  private var latestCount: Int?
  private var hasPublishedResults = false
  private var isLoading: Bool?
  private var pendingPages: [Int] = []
  private var unpairedSettlements = 0

  init(
    counts: Signal<Int, Never>, pages: Signal<Int, Never>,
    results: Signal<[SearchResult], Never>, loading: Signal<Bool, Never>
  ) {
    self.bindings += counts.observeValues { [weak self] in self?.recordCount($0) }
    self.bindings += pages.observeValues { [weak self] in self?.recordPage($0) }
    self.bindings += results.observeValues { [weak self] _ in
      self?.hasPublishedResults = true
      self?.recordSettlementIfReady()
    }
    self.bindings += loading.observeValues { [weak self] loading in
      self?.isLoading = loading
      self?.recordSettlementIfReady()
    }
  }

  func recordCount(_ count: Int) {
    self.latestCount = count
    if count == 0 { self.countsPipe.input.send(value: count) }
  }

  private func recordPage(_ page: Int) {
    guard self.unpairedSettlements > 0 else {
      self.pendingPages.append(page)
      return
    }
    self.unpairedSettlements -= 1
    self.trackIfFirstPage(page)
  }

  private func recordSettlementIfReady() {
    guard self.hasPublishedResults, self.isLoading == false else { return }
    guard !self.pendingPages.isEmpty else {
      self.unpairedSettlements += 1
      return
    }
    self.trackIfFirstPage(self.pendingPages.removeFirst())
  }

  private func trackIfFirstPage(_ page: Int) {
    guard page == 1, let count = self.latestCount else { return }
    self.countsPipe.input.send(value: count)
  }

  deinit { self.bindings.dispose() }
}

/// Calculates a ref tag from the search query, the list of displayed projects, and the project
/// tapped.
private func refTag(query: String, projects: [SearchResult], project: SearchResult) -> RefTag {
  if project == projects.first, query.isEmpty {
    return RefTag.searchPopularFeatured
  } else if project == projects.first, !query.isEmpty {
    return RefTag.searchFeatured
  } else if query.isEmpty {
    return RefTag.searchPopular
  } else {
    return RefTag.search
  }
}
