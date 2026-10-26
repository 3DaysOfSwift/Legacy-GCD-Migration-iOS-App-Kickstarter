import Foundation
import GraphAPI
import KsApi
import Prelude
import ReactiveSwift

public typealias SearchResult = GraphAPI.SearchQuery.Data.Projects.Node

/// Owns filter policy, directly awaitable requests, cursor and accumulated results.
/// Distinct queries supersede old work; equivalent in-flight requests share completion.
/// Signals are an output-only compatibility edge for the unchanged UIKit screen.
@MainActor
public final class SearchFeature {
  public private(set) var projects: [SearchResult] = []
  public private(set) var totalCount = 0
  public private(set) var isLoading = false
  public private(set) var searchError: ErrorEnvelope?
  public private(set) var parameters: DiscoveryParams?

  private let resultsPipe = Signal<[SearchResult], Never>.pipe()
  private let pagesPipe = Signal<[SearchResult], Never>.pipe()
  private let countPipe = Signal<Int, Never>.pipe()
  private let loadingPipe = Signal<Bool, Never>.pipe()
  private let pageCountPipe = Signal<Int, Never>.pipe()
  public var results: Signal<[SearchResult], Never> { self.resultsPipe.output.skipRepeats(==) }
  public var paginatedResults: Signal<[SearchResult], Never> { self.pagesPipe.output }
  public var resultCount: Signal<Int, Never> { self.countPipe.output }
  public var loading: Signal<Bool, Never> { self.loadingPipe.output }
  public var pageCount: Signal<Int, Never> { self.pageCountPipe.output }

  internal let filterSelection: SearchFilterSelection
  private let (filterLoadSignal, filterLoadObserver) = Signal<Void, Never>.pipe()
  private let categoriesUseCase: FetchCategoriesUseCase
  private let locationsUseCase: FetchLocationsUseCase
  public var categories: Signal<[KsApi.Category], Never> { self.categoriesUseCase.categories }
  public var defaultLocations: Signal<[Location], Never> { self.locationsUseCase.defaultLocations }
  public var suggestedLocations: Signal<[Location], Never> { self.locationsUseCase.suggestedLocations }

  private let provider: any SearchProjectsProvider
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var nextCursor: String?
  private var completedPageCount = 0
  private var hasRequested = false
  private var request: (id: UUID, cursor: String?, task: Task<Void, Never>)?

  public init(
    provider: any SearchProjectsProvider,
    sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite {
        try await Task.sleep(nanoseconds: UInt64.max)
      } else if seconds > 0 {
        try await Task.sleep(for: .seconds(seconds))
      }
      try Task.checkCancellation()
    }
  ) {
    self.provider = provider
    self.sleep = sleep
    self.filterSelection = SearchFilterSelection()
    self.categoriesUseCase = FetchCategoriesUseCase(initialSignal: self.filterLoadSignal)
    self.locationsUseCase = FetchLocationsUseCase(initialSignal: self.filterLoadSignal)
  }

  /// Default choices and lookup data are loaded only on explicit screen demand.
  public func loadFilterOptions() {
    self.filterLoadObserver.send(value: ())
    self.filterSelection.publishInitialSelection()
  }

  /// Transitional projection for the legacy screen's query signal.
  /// Selection policy and parameter construction remain owned by the Feature.
  public func queryParameters(for queryText: Signal<String, Never>) -> Signal<DiscoveryParams, Never> {
    return Signal.combineLatest(
      queryText,
      self.filterSelection.selectedSort,
      self.filterSelection.selectedCategory,
      self.filterSelection.selectedState,
      self.filterSelection.selectedPercentRaisedBucket,
      self.filterSelection.selectedLocation,
      self.filterSelection.selectedAmountRaisedBucket,
      self.filterSelection.selectedGoalBucket,
      self.filterSelection.selectedToggles
    )
    .map { query, sort, category, state, percentRaised, location, amountRaised, goal, toggles in
      DiscoveryParams.withQuery(
        query,
        sort: sort,
        category: category.category,
        state: state,
        percentRaised: percentRaised,
        location: location,
        amountRaised: amountRaised,
        goal: goal,
        toggles: toggles
      )
    }

  }

  public func updateQuery(_ query: String) {
    if query.isEmpty { self.filterSelection.clearedQueryText() }
  }

  public func selectFilter(_ event: SearchFilterEvent) {
    self.filterSelection.selectedFilter(event)
  }

  public func resetFilters(_ scope: SearchFilterReset) {
    self.filterSelection.resetFilters(for: scope)
  }

  public func toggleFilter(_ filter: SearchToggleFilter) {
    let selection = self.filterSelection
    switch filter {
    case .projectsWeLove: self.selectFilter(.projectsWeLove(!selection.projectsWeLoveValue))
    case .savedProjects: self.selectFilter(.savedProjects(!selection.savedProjectsValue))
    case .following: self.selectFilter(.following(!selection.followingValue))
    case .recommended: self.selectFilter(.recommended(!selection.recommendedValue))
    }
  }

  public func searchLocations(_ query: String) { self.locationsUseCase.searchedForLocations(query) }

  /// Await the complete first-page operation, including delivery timing/publication.
  /// A cancelled waiter does not cancel work shared by another caller. Distinct
  /// queries and cancelSearch() are the Feature's explicit cancellation owners.
  public func search(parameters: DiscoveryParams) async {
    guard !Task.isCancelled else { return }
    await self.requestSearch(parameters: parameters).value
  }

  public func loadNextPage() async {
    guard !Task.isCancelled else { return }
    await self.requestNextPage()?.value
  }

  /// Synchronous UIKit admission preserves immediate clearing/loading. It returns
  /// the very same Feature-owned task awaited by the public async command; it
  /// neither installs a second pipeline nor starts work from an observer.
  @discardableResult
  internal func requestSearch(parameters: DiscoveryParams) -> Task<Void, Never> {
    if self.parameters == parameters, let request = self.request, request.cursor == nil {
      return request.task
    }
    self.cancelSearch()
    self.parameters = parameters
    self.nextCursor = nil
    self.completedPageCount = 0
    self.projects = []
    self.resultsPipe.input.send(value: [])
    let debounce = self.hasRequested ? AppEnvironment.current.debounceInterval.searchDelaySeconds : 0
    self.hasRequested = true
    return self.requestPage(parameters: parameters, cursor: nil, debounce: debounce)
  }

  @discardableResult
  internal func requestNextPage() -> Task<Void, Never>? {
    // While the first page is loading, join it: an old query's cursor must
    // never escape into the replacement query. Repeated pages also join.
    if let request = self.request { return request.task }
    guard let parameters = self.parameters, let cursor = self.nextCursor else { return nil }
    return self.requestPage(parameters: parameters, cursor: cursor, debounce: 0)
  }

  /// Explicit owner cancellation, not a side effect of a single waiter leaving.
  public func cancelSearch() {
    let previous = self.request
    self.request = nil
    previous?.task.cancel()
    if self.isLoading { self.setLoading(false) }
  }

  private func requestPage(
    parameters: DiscoveryParams, cursor: String?, debounce: TimeInterval
  ) -> Task<Void, Never> {
    let id = UUID()
    let apiDelay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.searchError = nil
    self.setLoading(true)
    let task = Task { @MainActor [weak self, provider, sleep] in
      defer { self?.finishRequest(id: id) }
      do {
        try Task.checkCancellation()
        let response: Result<GraphAPI.SearchQuery.Data, Error>
        do {
          response = .success(try await provider.fetchPage(parameters: parameters, cursor: cursor))
        } catch is CancellationError {
          return
        } catch {
          response = .failure(error)
        }
        try Task.checkCancellation()
        // Legacy debounce delayed successful values, not admission or errors.
        let resultDelay: TimeInterval
        switch response {
        case .success: resultDelay = debounce + apiDelay
        case .failure: resultDelay = apiDelay
        }
        try await sleep(resultDelay)
        try Task.checkCancellation()
        guard let self, self.request?.id == id else { return }
        switch response {
        case let .success(data):
          self.publish(data, firstPage: cursor == nil)
        case let .failure(error):
          self.searchError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
        }
      } catch is CancellationError {
        // Superseded/explicitly cancelled operations never publish a failure.
      } catch {
        guard let self, self.request?.id == id else { return }
        self.searchError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    self.request = (id, cursor, task)
    return task
  }

  private func publish(_ data: GraphAPI.SearchQuery.Data, firstPage: Bool) {
    let incoming = data.projects?.nodes?.compactMap { $0 } ?? []
    let pageInfo = data.projects?.pageInfo
    self.nextCursor = !incoming.isEmpty && pageInfo?.hasNextPage == true ? pageInfo?.endCursor : nil
    self.totalCount = data.projects?.totalCount ?? 0
    self.countPipe.input.send(value: self.totalCount)
    self.projects = firstPage ? incoming : self.projects + incoming
    // Preserve legacy output ordering used by analytics: count, page, results,
    // then loading=false. Empty terminal pages retain already accumulated cards.
    if !self.projects.isEmpty {
      self.completedPageCount += 1
      self.pageCountPipe.input.send(value: self.completedPageCount)
    }
    self.pagesPipe.input.send(value: self.projects)
    self.resultsPipe.input.send(value: self.projects)
  }

  private func finishRequest(id: UUID) {
    guard self.request?.id == id else { return }
    self.request = nil
    self.setLoading(false)
  }

  private func setLoading(_ loading: Bool) {
    self.isLoading = loading
    self.loadingPipe.input.send(value: loading)
  }

  deinit { self.request?.task.cancel() }
}

public enum SearchToggleFilter { case projectsWeLove, savedProjects, following, recommended }

/// Compatibility conversion for the existing environment's configured intervals.
extension DispatchTimeInterval {
  internal var searchDelaySeconds: TimeInterval {
    switch self {
    case let .seconds(value): return Double(value)
    case let .milliseconds(value): return Double(value) / 1_000
    case let .microseconds(value): return Double(value) / 1_000_000
    case let .nanoseconds(value): return Double(value) / 1_000_000_000
    case .never: return .infinity
    @unknown default: return .infinity
    }
  }
}
