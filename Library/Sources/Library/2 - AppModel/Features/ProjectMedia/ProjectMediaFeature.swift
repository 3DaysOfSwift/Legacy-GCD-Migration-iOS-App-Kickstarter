import Foundation
import KsApi
import Observation
import ReactiveSwift

@MainActor
public protocol ProjectMediaProvider {
  func report(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope
  func feed() async throws -> [VideoFeedItem]
  func setWatched(id: String, watched: Bool) async throws
}

@MainActor
public struct AsyncProjectMediaProvider: ProjectMediaProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func report(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope {
    try await self.service.reportVideoEvent(project: project, completed: completed)
  }

  public func feed() async throws -> [VideoFeedItem] {
    let data = try await self.service.projectVideoFeed()
    return data.videoFeed?.nodes?.compactMap { $0 }.map(VideoFeedItem.init) ?? []
  }

  public func setWatched(id: String, watched: Bool) async throws {
    _ = try await self.service.setProjectWatched(id: id, watched: watched)
  }
}

/// Playback counter requests are independent events, not replaceable searches.
/// Start and completion may both be in flight; neither cancels the other.
@MainActor
public final class ProjectMediaFeature {
  /// One authoritative observable feed per screen route. Only this Feature
  /// mutates it; a ViewModel reads its individual properties for presentation.
  @Observable @MainActor
  public final class FeedState {
    public fileprivate(set) var items: [VideoFeedItem] = []
    public fileprivate(set) var fetchedItems: [VideoFeedItem] = []
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: Error?
    public fileprivate(set) var isInitialLoadComplete = false
    public fileprivate(set) var saveFailedItemID: String?
  }

  public enum FeedError: Error { case empty }
  private var feeds: [UUID: FeedState] = [:]
  private var feedRequests: [UUID: (userID: Int?, token: UUID, task: Task<Void, Never>)] = [:]
  private var feedSaves: [UUID: [String: (token: UUID, task: Task<Void, Never>)]] = [:]

  private struct WatchIdentity: Hashable {
    let projectID: String
    let userID: Int?
  }

  private var watchWrites: [WatchIdentity: (watched: Bool, token: UUID, task: Task<Void, Error>)] = [:]

  public func feedState(route: UUID) -> FeedState {
    if let feed = self.feeds[route] { return feed }
    let feed = FeedState()
    self.feeds[route] = feed
    return feed
  }

  public var hasCurrentUser: Bool { AppEnvironment.current.currentUser != nil }

  public func loadFeed(route: UUID) async {
    guard !Task.isCancelled else { return }
    await self.requestFeed(route: route).value
  }

  @discardableResult
  public func requestFeed(route: UUID) -> Task<Void, Never> {
    let userID = AppEnvironment.current.currentUser?.id
    if let request = self.feedRequests[route], request.userID == userID { return request.task }
    self.feedRequests[route]?.task.cancel()
    let feed = self.feedState(route: route)
    let provider = self.makeProvider()
    let token = UUID()
    feed.isLoading = true
    feed.error = nil
    let task = Task { [weak self] in
      defer {
        if self?.feedRequests[route]?.token == token {
          self?.feedRequests[route] = nil
          feed.isLoading = false
        }
      }
      do {
        try Task.checkCancellation()
        guard userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
        let items = try await provider.feed()
        try Task.checkCancellation()
        guard let self, self.feedRequests[route]?.token == token,
              userID == AppEnvironment.current.currentUser?.id else { return }
        guard let first = items.first else { throw FeedError.empty }
        // Match the existing reload observer contract: initial flag precedes
        // fetchedItems; saves never write fetchedItems or trigger a collection reload.
        feed.isInitialLoadComplete = true
        feed.fetchedItems = items
        feed.items = items
        AppEnvironment.current.ksrAnalytics.trackVideoFeedImpression(
          videoId: first.id, projectId: first.projectId, positionInSession: 0
        )
      } catch is CancellationError {
      } catch {
        guard !Task.isCancelled, let self, self.feedRequests[route]?.token == token,
              userID == AppEnvironment.current.currentUser?.id else { return }
        feed.error = error
      }
    }
    self.feedRequests[route] = (userID, token, task)
    return task
  }

  /// Equivalent pending desired states share; changed states queue after the
  /// preceding write for this account/project. Disposing a request cannot undo
  /// a server mutation, so save→unsave must not race on separate connections.
  @discardableResult
  public func requestWatch(projectID: String, watched: Bool) -> Task<Void, Error> {
    let key = WatchIdentity(projectID: projectID, userID: AppEnvironment.current.currentUser?.id)
    if let pending = self.watchWrites[key], pending.watched == watched { return pending.task }
    let predecessor = self.watchWrites[key]?.task
    let provider = self.makeProvider()
    let token = UUID()
    let task = Task { [self] in
      defer { if self.watchWrites[key]?.token == token { self.watchWrites[key] = nil } }
      if let predecessor { _ = await predecessor.result }
      try Task.checkCancellation()
      guard key.userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
      try await provider.setWatched(id: projectID, watched: watched)
      try Task.checkCancellation()
      guard key.userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
    }
    self.watchWrites[key] = (watched, token, task)
    return task
  }

  @discardableResult
  public func toggleSaved(route: UUID, projectID: String) -> Task<Void, Never>? {
    guard let feed = self.feeds[route],
          let index = feed.items.firstIndex(where: { $0.id == projectID }) else { return nil }
    let item = feed.items[index]
    let wasSaved = item.isSaved
    let userID = AppEnvironment.current.currentUser?.id
    feed.items[index].isSaved = !wasSaved
    feed.items[index].watchesCount = max(0, item.watchesCount + (wasSaved ? -1 : 1))
    AppEnvironment.current.ksrAnalytics.trackVideoFeedCTAClicked(
      ctaContext: .videoFeedSave, videoId: item.id, projectId: item.projectId
    )
    let mutation = self.requestWatch(projectID: item.projectId, watched: !wasSaved)
    let token = UUID()
    let task = Task { [self] in
      defer {
        if self.feedSaves[route]?[projectID]?.token == token {
          self.feedSaves[route]?[projectID] = nil
        }
      }
      do {
        try await mutation.value
      } catch {
        guard !(error is CancellationError), self.feeds[route] === feed,
              self.feedSaves[route]?[projectID]?.token == token,
              userID == AppEnvironment.current.currentUser?.id,
              let index = feed.items.firstIndex(where: { $0.id == projectID }) else { return }
        // Preserve rollback and toast for the latest visible intent only.
        feed.items[index].isSaved = wasSaved
        feed.items[index].watchesCount = max(0, feed.items[index].watchesCount + (wasSaved ? 1 : -1))
        feed.saveFailedItemID = projectID
      }
    }
    self.feedSaves[route, default: [:]][projectID] = (token, task)
    return task
  }

  public func clearSaveFailure(route: UUID) {
    self.feeds[route]?.saveFailedItemID = nil
  }

  public func waitForSaves(route: UUID) async {
    let tasks = self.feedSaves[route]?.values.map(\.task) ?? []
    for task in tasks { await task.value }
  }

  public func reconcileSavedProjects(route: UUID) {
    guard let feed = self.feeds[route],
          let cache = AppEnvironment.current.cache[KSCache.ksr_projectSaved] as? [Int: Bool] else { return }
    for index in feed.items.indices {
      if let id = decompose(id: feed.items[index].projectId), let saved = cache[id] {
        let previous = feed.items[index].isSaved
        feed.items[index].isSaved = saved
        if previous != saved { feed.items[index].watchesCount += saved ? 1 : -1 }
      }
    }
  }

  private struct Event: Hashable {
    let route: UUID
    let url: String
    let completed: Bool
    let userID: Int?
  }

  private var requests: [Event: (id: UUID, task: Task<Void, Never>)] = [:]
  private let makeProvider: () -> any ProjectMediaProvider
  private let completionPipe = Signal<(UUID, Bool, VoidEnvelope), Never>.pipe()
  public var completions: Signal<(UUID, Bool, VoidEnvelope), Never> { self.completionPipe.output }

  public init(makeProvider: @escaping () -> any ProjectMediaProvider) {
    self.makeProvider = makeProvider
  }

  public func report(route: UUID, project: any HasProjectWebURL, completed: Bool) async {
    guard !Task.isCancelled else { return }
    await self.requestReport(route: route, project: project, completed: completed).value
  }

  @discardableResult
  public func requestReport(
    route: UUID, project: any HasProjectWebURL, completed: Bool
  ) -> Task<Void, Never> {
    let event = Event(
      route: route,
      url: project.projectWebURL,
      completed: completed,
      userID: AppEnvironment.current.currentUser?.id
    )
    if let request = self.requests[event] { return request.task }
    let token = UUID()
    let provider = self.makeProvider()
    let task = Task { [weak self] in
      defer { if self?.requests[event]?.id == token { self?.requests[event] = nil } }
      do {
        try Task.checkCancellation()
        guard event.userID == AppEnvironment.current.currentUser?.id else { return }
        let value = try await provider.report(project: project, completed: completed)
        try Task.checkCancellation()
        guard let self, self.requests[event]?.id == token,
              event.userID == AppEnvironment.current.currentUser?.id else { return }
        self.completionPipe.input.send(value: (route, completed, value))
      } catch {
        // Counter errors have always been non-user-facing; do not retry a write
        // whose server-side outcome may be unknown.
      }
    }
    self.requests[event] = (token, task)
    return task
  }

  public func release(route: UUID) {
    self.feedRequests.removeValue(forKey: route)?.task.cancel()
    self.feeds[route] = nil
    self.feedSaves[route] = nil
    // Watch writes deliberately continue after their presenting route closes.
    for event in self.requests.keys.filter({ $0.route == route }) {
      self.requests.removeValue(forKey: event)?.task.cancel()
    }
  }
}
