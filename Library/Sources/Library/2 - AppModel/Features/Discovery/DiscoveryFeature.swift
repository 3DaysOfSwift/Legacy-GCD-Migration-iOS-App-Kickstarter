import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol DiscoveryProvider {
  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope
  func activitySample() async throws -> ActivityEnvelope?
}

/// Uses the existing authenticated service and its native async URLSession transport.
@MainActor
public struct AsyncDiscoveryProvider: DiscoveryProvider {
  public init() {}

  public func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    let service = AppEnvironment.current.apiService
    if let cursor { return try await service.discoveryPage(paginationURL: cursor) }
    return try await service.discoveryPage(params: parameters)
  }

  public func activitySample() async throws -> ActivityEnvelope? {
    try await AppEnvironment.current.apiService.discoveryActivitySample()
  }
}

/// One Explore owner, with independent request identities for its four retained feeds.
/// Signals are output-only compatibility adapters for the existing UIKit presentation.
@MainActor
public final class DiscoveryFeature {
  public struct PageSnapshot {
    public fileprivate(set) var projects: [Project] = []
    public fileprivate(set) var parameters: DiscoveryParams?
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
    public fileprivate(set) var hasMore = false
    public fileprivate(set) var activitySample: [Activity] = []
    public fileprivate(set) var activityError: ErrorEnvelope?
  }

  private final class Page {
    var snapshot = PageSnapshot()
    var cursor: String?
    var request: (id: UUID, cursor: String?, task: Task<Void, Never>)?
    var activityRequest: (id: UUID, task: Task<Void, Never>)?
  }

  private var pages: [String: Page] = [:]
  private let provider: any DiscoveryProvider
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private let projectsPipe = Signal<(DiscoveryParams.Sort, [Project]), Never>.pipe()
  private let loadingPipe = Signal<(DiscoveryParams.Sort, Bool), Never>.pipe()
  private let activitiesPipe = Signal<(DiscoveryParams.Sort, [Activity]), Never>.pipe()

  public var projects: Signal<(DiscoveryParams.Sort, [Project]), Never> { self.projectsPipe.output }
  public var loading: Signal<(DiscoveryParams.Sort, Bool), Never> { self.loadingPipe.output }
  public var activities: Signal<(DiscoveryParams.Sort, [Activity]), Never> { self.activitiesPipe.output }

  public init(
    provider: any DiscoveryProvider,
    sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
      if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
      else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
      try Task.checkCancellation()
    }
  ) {
    self.provider = provider
    self.sleep = sleep
  }

  public func snapshot(for sort: DiscoveryParams.Sort) -> PageSnapshot {
    self.pages[sort.rawValue]?.snapshot ?? PageSnapshot()
  }

  public func refresh(sort: DiscoveryParams.Sort, parameters: DiscoveryParams) async {
    guard !Task.isCancelled else { return }
    await self.requestRefresh(sort: sort, parameters: parameters).value
  }

  public func loadNextPage(sort: DiscoveryParams.Sort) async {
    guard !Task.isCancelled else { return }
    await self.requestNextPage(sort: sort)?.value
  }

  public func loadActivitySample(sort: DiscoveryParams.Sort) async {
    guard !Task.isCancelled else { return }
    await self.requestActivitySample(sort: sort).value
  }

  /// Same-input callers share work. An explicit refresh/session/environment event
  /// may force a replacement even when its filter values have not changed.
  @discardableResult
  internal func requestRefresh(
    sort: DiscoveryParams.Sort, parameters: DiscoveryParams, force: Bool = false
  ) -> Task<Void, Never> {
    let page = self.page(for: sort)
    var parameters = parameters
    parameters.sort = sort
    if !force, let request = page.request, request.cursor == nil,
       page.snapshot.parameters == parameters { return request.task }
    page.request?.task.cancel()
    page.snapshot.parameters = parameters
    page.cursor = nil
    page.snapshot.hasMore = false
    return self.startPage(sort: sort, page: page, parameters: parameters, cursor: nil)
  }

  @discardableResult
  internal func requestNextPage(sort: DiscoveryParams.Sort) -> Task<Void, Never>? {
    let page = self.page(for: sort)
    if let request = page.request { return request.task }
    guard let parameters = page.snapshot.parameters, let cursor = page.cursor,
          page.snapshot.hasMore else { return nil }
    return self.startPage(sort: sort, page: page, parameters: parameters, cursor: cursor)
  }

  private func startPage(
    sort: DiscoveryParams.Sort, page: Page, parameters: DiscoveryParams, cursor: String?
  ) -> Task<Void, Never> {
    let id = UUID()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    page.snapshot.isLoading = true
    page.snapshot.error = nil
    let task = Task { @MainActor [weak self, provider, sleep] in
      defer {
        if page.request?.id == id {
          page.request = nil
          page.snapshot.isLoading = false
          self?.loadingPipe.input.send(value: (sort, false))
        }
      }
      do {
        try Task.checkCancellation()
        let response: Result<DiscoveryEnvelope, Error>
        do { response = .success(try await provider.page(parameters: parameters, cursor: cursor)) }
        catch is CancellationError { return }
        catch { response = .failure(error) }
        try Task.checkCancellation()
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, page.request?.id == id else { return }
        let envelope = try response.get()
        page.snapshot.projects = ((cursor == nil ? [] : page.snapshot.projects) + envelope.projects).distincts()
        page.cursor = envelope.urls.api.moreProjects
        page.snapshot.hasMore = !envelope.projects.isEmpty
        self.projectsPipe.input.send(value: (sort, page.snapshot.projects))
      } catch {
        guard page.request?.id == id, !Task.isCancelled, !(error is CancellationError) else { return }
        page.snapshot.error = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    page.request = (id, cursor, task)
    self.loadingPipe.input.send(value: (sort, true))
    return task
  }

  @discardableResult
  internal func requestActivitySample(sort: DiscoveryParams.Sort) -> Task<Void, Never> {
    let page = self.page(for: sort)
    page.activityRequest?.task.cancel()
    let id = UUID()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    page.snapshot.activityError = nil
    let task = Task { @MainActor [weak self, provider, sleep] in
      defer { if page.activityRequest?.id == id { page.activityRequest = nil } }
      do {
        try Task.checkCancellation()
        guard let envelope = try await provider.activitySample() else { return }
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, page.activityRequest?.id == id else { return }
        page.snapshot.activitySample = envelope.activities
        self.activitiesPipe.input.send(value: (sort, envelope.activities))
      } catch {
        // Legacy sample failures leave the existing sample unchanged.
        guard page.activityRequest?.id == id, !Task.isCancelled, !(error is CancellationError) else { return }
        page.snapshot.activityError = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    page.activityRequest = (id, task)
    return task
  }

  /// Owner-driven cancellation invalidates identity before cancelling transport.
  /// Merely hiding a retained feed does not cancel it (legacy behaviour).
  public func cancel(sort: DiscoveryParams.Sort) {
    guard let page = self.pages[sort.rawValue] else { return }
    let request = page.request
    let activity = page.activityRequest
    page.request = nil
    page.activityRequest = nil
    request?.task.cancel()
    activity?.task.cancel()
    if page.snapshot.isLoading {
      page.snapshot.isLoading = false
      self.loadingPipe.input.send(value: (sort, false))
    }
  }

  private func page(for sort: DiscoveryParams.Sort) -> Page {
    if let page = self.pages[sort.rawValue] { return page }
    let page = Page()
    self.pages[sort.rawValue] = page
    return page
  }
}
