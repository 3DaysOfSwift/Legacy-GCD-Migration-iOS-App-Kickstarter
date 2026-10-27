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
  private let categoriesPipe = Signal<[KsApi.Category], Never>.pipe()
  private let defaultLocationsPipe = Signal<[Location], Never>.pipe()
  private let suggestedLocationsPipe = Signal<[Location], Never>.pipe()
  public var categories: Signal<[KsApi.Category], Never> { self.categoriesPipe.output }
  public var defaultLocations: Signal<[Location], Never> { self.defaultLocationsPipe.output }
  public var suggestedLocations: Signal<[Location], Never> { self.suggestedLocationsPipe.output }

  public private(set) var categoryOptions: [KsApi.Category] = []
  public private(set) var defaultLocationOptions: [Location] = []
  public private(set) var suggestedLocationOptions: [Location] = []
  public private(set) var locationQuery = ""
  public private(set) var isLoadingCategories = false
  public private(set) var isLoadingDefaultLocations = false
  public private(set) var isLoadingSuggestions = false
  public private(set) var categoryError: ErrorEnvelope?
  public private(set) var defaultLocationsError: ErrorEnvelope?
  public private(set) var suggestedLocationsError: ErrorEnvelope?

  private let lookupProvider: any SearchLookupProvider
  private let lookupSleep: @MainActor (TimeInterval) async throws -> Void
  private var filterOptionsRequest: (id: UUID, task: Task<Void, Never>)?
  private var categoryRequest: (id: UUID, task: Task<Void, Never>)?
  private var defaultLocationsRequest: (id: UUID, task: Task<Void, Never>)?
  private var suggestionsRequest: (id: UUID, task: Task<Void, Never>)?

  private let provider: any SearchProjectsProvider
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var nextCursor: String?
  private var completedPageCount = 0
  private var hasRequested = false
  private var request: (id: UUID, cursor: String?, task: Task<Void, Never>)?

  public init(
    provider: any SearchProjectsProvider,
    lookupProvider: (any SearchLookupProvider)? = nil,
    lookupSleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
      try Task.checkCancellation()
    },
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
    self.lookupSleep = lookupSleep
    self.filterSelection = SearchFilterSelection()
    self.lookupProvider = lookupProvider ?? AsyncSearchLookupProvider()
  }

  /// Default choices and lookup data are loaded only on explicit screen demand.
  public func loadFilterOptions() async {
    guard !Task.isCancelled else { return }
    await self.requestFilterOptions().value
  }

  @discardableResult
  internal func requestFilterOptions() -> Task<Void, Never> {
    if let request = self.filterOptionsRequest { return request.task }
    let id = UUID()
    let categories = self.requestCategories()
    let locations = self.requestDefaultLocations()
    self.filterSelection.publishInitialSelection()
    // Both independent requests start now; a slow/failing category lookup
    // must not hold default locations hostage (or vice versa).
    let task = Task { @MainActor [weak self] in
      defer {
        if self?.filterOptionsRequest?.id == id { self?.filterOptionsRequest = nil }
      }
      await categories.value
      await locations.value
    }
    self.filterOptionsRequest = (id, task)
    return task
  }

  /// Native, side-effect-free query construction. No initial signal, UI
  /// subscriber or network execution is required to read the current selection.
  public func queryParameters(for query: String) -> DiscoveryParams {
    let selection = self.filterSelection
    return DiscoveryParams.withQuery(
      query,
      sort: selection.selectedSortValue,
      category: selection.selectedCategoryValue.category,
      state: selection.selectedStateValue,
      percentRaised: selection.selectedPercentRaisedBucketValue,
      location: selection.selectedLocationValue,
      amountRaised: selection.selectedAmountRaisedBucketValue,
      goal: selection.selectedGoalBucketValue,
      toggles: selection.toggles
    )
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

  public func searchLocations(_ query: String) async {
    guard !Task.isCancelled else { return }
    await self.requestLocations(query)?.value
  }

  /// Clearing is a superseding command, not a separate output branch. Invalidate
  /// identity before cancellation, so late successes, errors and cleanup cannot
  /// affect the current query even if the provider ignores cancellation.
  @discardableResult
  internal func requestLocations(_ query: String) -> Task<Void, Never>? {
    if self.locationQuery == query, let request = self.suggestionsRequest { return request.task }
    self.cancelLocationSuggestions()
    self.locationQuery = query
    self.suggestedLocationsError = nil
    guard !query.isEmpty else {
      self.suggestedLocationOptions = []
      self.suggestedLocationsPipe.input.send(value: [])
      return nil
    }
    let id = UUID()
    self.isLoadingSuggestions = true
    let task = Task { @MainActor [weak self, lookupProvider] in
      defer {
        if self?.suggestionsRequest?.id == id {
          self?.suggestionsRequest = nil
          self?.isLoadingSuggestions = false
        }
      }
      do {
        try Task.checkCancellation()
        let locations = try await lookupProvider.fetchLocations(query: query)
        try Task.checkCancellation()
        guard let self, self.suggestionsRequest?.id == id else { return }
        self.suggestedLocationOptions = locations
        self.suggestedLocationsPipe.input.send(value: locations)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError),
          let self, self.suggestionsRequest?.id == id else { return }
        self.suggestedLocationsError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    self.suggestionsRequest = (id, task)
    return task
  }

  public func cancelFilterLookups() {
    self.cancelLocationSuggestions()
    self.filterOptionsRequest?.task.cancel()
    self.filterOptionsRequest = nil
    let categories = self.categoryRequest
    let defaults = self.defaultLocationsRequest
    self.categoryRequest = nil
    self.defaultLocationsRequest = nil
    categories?.task.cancel()
    defaults?.task.cancel()
    self.isLoadingCategories = false
    self.isLoadingDefaultLocations = false
  }

  private func cancelLocationSuggestions() {
    let previous = self.suggestionsRequest
    self.suggestionsRequest = nil
    previous?.task.cancel()
    self.isLoadingSuggestions = false
  }

  private func requestCategories() -> Task<Void, Never> {
    if let request = self.categoryRequest { return request.task }
    self.categoryError = nil
    if let cached = self.lookupProvider.cachedCategories {
      self.categoryOptions = cached
      self.categoriesPipe.input.send(value: cached)
      if !cached.isEmpty { return Task {} }
    }
    let id = UUID()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.isLoadingCategories = true
    let task = Task { @MainActor [weak self, lookupProvider, lookupSleep] in
      defer {
        if self?.categoryRequest?.id == id {
          self?.categoryRequest = nil
          self?.isLoadingCategories = false
        }
      }
      do {
        try Task.checkCancellation()
        let response: Result<[KsApi.Category], Error>
        do { response = .success(try await lookupProvider.fetchCategories()) }
        catch { response = .failure(error) }
        try Task.checkCancellation()
        try await lookupSleep(delay)
        try Task.checkCancellation()
        guard let self, self.categoryRequest?.id == id else { return }
        switch response {
        case let .success(categories):
          lookupProvider.cache(categories: categories)
          self.categoryOptions = categories
          self.categoriesPipe.input.send(value: categories)
        case let .failure(error):
          if !(error is CancellationError) {
            self.categoryError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
          }
        }
      } catch {
        guard !Task.isCancelled, !(error is CancellationError),
          let self, self.categoryRequest?.id == id else { return }
        self.categoryError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    self.categoryRequest = (id, task)
    return task
  }

  private func requestDefaultLocations() -> Task<Void, Never> {
    if let request = self.defaultLocationsRequest { return request.task }
    let id = UUID()
    self.defaultLocationsError = nil
    self.defaultLocationOptions = []
    self.defaultLocationsPipe.input.send(value: [])
    self.requestLocations("")
    self.isLoadingDefaultLocations = true
    let task = Task { @MainActor [weak self, lookupProvider] in
      defer {
        if self?.defaultLocationsRequest?.id == id {
          self?.defaultLocationsRequest = nil
          self?.isLoadingDefaultLocations = false
        }
      }
      do {
        try Task.checkCancellation()
        let locations = try await lookupProvider.fetchDefaultLocations()
        try Task.checkCancellation()
        guard let self, self.defaultLocationsRequest?.id == id else { return }
        self.defaultLocationOptions = locations
        self.defaultLocationsPipe.input.send(value: locations)
      } catch {
        guard !Task.isCancelled, !(error is CancellationError),
          let self, self.defaultLocationsRequest?.id == id else { return }
        self.defaultLocationsError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    self.defaultLocationsRequest = (id, task)
    return task
  }

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
    if self.parameters?.hasSameSearchInputs(as: parameters) == true,
       let request = self.request, request.cursor == nil {
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

  deinit {
    self.request?.task.cancel()
    self.filterOptionsRequest?.task.cancel()
    self.categoryRequest?.task.cancel()
    self.defaultLocationsRequest?.task.cancel()
    self.suggestionsRequest?.task.cancel()
  }
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
