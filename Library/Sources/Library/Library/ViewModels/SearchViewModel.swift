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
    let queryParams = searchFeature.queryParameters(for: queryText)

    let requestFirstPageWith = queryParams
    let paginatedProjects = searchFeature.paginatedResults
    let isLoading = searchFeature.loading
    let page = searchFeature.pageCount
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

    self.showEmptyState = requestFirstPageWith
      .takePairWhen(shouldShowEmptyState)

    self.reachabilityProperty <~ Reachability.signalProducer

    self.showVideoFeedBanner = Signal.merge(
      self.appearancePipe.output,
      self.reachabilityProperty.signal.ignoreValues()
    )
    .map { featureVideoFeedEnabled() && Reachability.current != .none }
    .skipRepeats()

    self.goToProject = self.projectNavigationPipe.output

    // Tracking

    // This represents search results count whenever the search page is viewed.
    // An initial value is emitted on first visit.
    let viewWillAppearSearchResultsCount = Signal.merge(
      stats,
      self.initialAppearanceCountPipe.output
    )

    let hasResults = Signal.combineLatest(paginatedProjects, isLoading)
      .filter(second >>> isFalse)
      .map(first)
      .map { !$0.isEmpty }

    let firstPageResults = Signal.zip(hasResults, page)
      .filter { _, page in page == 1 }
      .map(first)

    // This represents search results count only when a search is performed
    // and there is a response from the API for the query.
    let newQuerySearchResultsCount = Signal.merge(
      viewWillAppearSearchResultsCount.filter { $0 == 0 },
      viewWillAppearSearchResultsCount.takeWhen(firstPageResults)
    )

    Signal.combineLatest(queryText, requestFirstPageWith)
      .takePairWhen(newQuerySearchResultsCount)
      .map(unpack)
      .filter { query, _, _ in !query.isEmpty }
      .observeValues { _, params, stats in
        AppEnvironment.current.ksrAnalytics
          .trackProjectSearchView(params: params, results: stats)
      }

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
    self.featureBindings += viewWillAppearSearchResultsCount.observeValues { [weak self] count in
      self?.appearanceResultsCount = count
    }
    self.featureBindings += queryParams.observeValues { [weak self] parameters in
      // Install the analytics snapshot before admission publishes loading/clearing.
      self?.latestQueryParameters = parameters
      self?.searchTask = searchFeature.requestSearch(parameters: parameters)
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
  private var wasCloseToBottom: Bool?
  private let queryTextPipe = Signal<String, Never>.pipe()
  private let appearancePipe = Signal<Void, Never>.pipe()
  private let initialAppearanceCountPipe = Signal<Int, Never>.pipe()
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
    self.queryTextPipe.input.send(value: query)
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
      self.initialAppearanceCountPipe.input.send(value: 0)
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
