import Foundation
import KsApi
import Observation
import ReactiveSwift

@MainActor
public protocol ProjectMediaProvider {
  func report(project: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope
  func feed() async throws -> [VideoFeedItem]
  func setWatched(id: String, watched: Bool) async throws -> WatchProjectResponseEnvelope
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

  public func setWatched(id: String, watched: Bool) async throws -> WatchProjectResponseEnvelope {
    try await self.service.setProjectWatched(id: id, watched: watched)
  }
}

/// Playback counter requests are independent events, not replaceable searches.
/// Start and completion may both be in flight; neither cancels the other.
@MainActor
public final class ProjectMediaFeature {
  private struct PreparationKey: Hashable { let route: UUID; let slot: String }
  private struct Preparation {
    let id: UUID
    let url: URL
    let thumbnail: URL?
    let task: Task<PreparedProjectMedia, Error>
  }
  private var preparations: [PreparationKey: Preparation] = [:]
  private let preparePlayback: @MainActor (URL, URL?) async throws -> PreparedProjectMedia

  /// Each page/element owns an independent player. Equivalent requests for that
  /// slot share pending work; changed URLs replace it without affecting other rows.
  public func requestPreparation(
    route: UUID, slot: String, url: URL, thumbnail: URL?
  ) -> Task<PreparedProjectMedia, Error> {
    let key = PreparationKey(route: route, slot: slot)
    if let pending = self.preparations[key], pending.url == url, pending.thumbnail == thumbnail {
      return pending.task
    }
    self.preparations[key]?.task.cancel()
    let id = UUID()
    let prepare = self.preparePlayback
    let task = Task { [self] in
      defer { if self.preparations[key]?.id == id { self.preparations[key] = nil } }
      try Task.checkCancellation()
      let result = try await prepare(url, thumbnail)
      try Task.checkCancellation()
      guard self.preparations[key]?.id == id else { throw CancellationError() }
      return result
    }
    self.preparations[key] = Preparation(id: id, url: url, thumbnail: thumbnail, task: task)
    return task
  }

  public func cancelPreparations(route: UUID) {
    for key in Array(self.preparations.keys) where key.route == route {
      self.preparations.removeValue(forKey: key)?.task.cancel()
    }
  }

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

  fileprivate struct WatchIdentity: Hashable {
    let projectID: String
    let userID: Int?
    let generation: Int
  }

  private var watchWrites: [WatchIdentity: (watched: Bool, token: UUID, task: Task<WatchProjectResponseEnvelope, Error>)] = [:]

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
  public func requestWatch(projectID: String, watched: Bool) -> Task<WatchProjectResponseEnvelope, Error> {
    let key = self.watchIdentity(projectID)
    if let pending = self.watchWrites[key], pending.watched == watched { return pending.task }
    let predecessor = self.watchWrites[key]?.task
    let provider = self.makeProvider()
    let token = UUID()
    let task = Task<WatchProjectResponseEnvelope, Error> { [self] in
      defer { if self.watchWrites[key]?.token == token { self.watchWrites[key] = nil } }
      if let predecessor { _ = await predecessor.result }
      try Task.checkCancellation()
      guard self.isCurrent(key) else { throw CancellationError() }
      let result = try await provider.setWatched(id: projectID, watched: watched)
      try Task.checkCancellation()
      guard self.isCurrent(key) else { throw CancellationError() }
      return result
    }
    self.watchWrites[key] = (watched, token, task)
    return task
  }

  public struct WatchIntent {
    fileprivate let key: WatchIdentity
    fileprivate let token: UUID
    public let watched: Bool
    fileprivate let previous: Bool
  }
  private var watchIntents: [WatchIdentity: (token: UUID, admitted: Bool)] = [:]
  private var watchSettlements: [UUID: Task<WatchProjectResponseEnvelope, Error>] = [:]
  private var watchObservations: [UUID: Task<Void, Never>] = [:]
  private var cacheIdentity: WatchIdentity?

  private func watchIdentity(_ projectID: String) -> WatchIdentity {
    WatchIdentity(projectID: projectID, userID: self.sessionFeature.currentUser?.id,
                  generation: self.sessionFeature.generation)
  }
  private func isCurrent(_ key: WatchIdentity) -> Bool {
    key.userID == self.sessionFeature.currentUser?.id && key.generation == self.sessionFeature.generation
  }
  private func prepareCache() {
    let identity = self.watchIdentity("")
    if let previous = self.cacheIdentity, previous != identity {
      AppEnvironment.current.cache[KSCache.ksr_projectSaved] = [Int: Bool]()
      self.watchIntents.removeAll()
    }
    self.cacheIdentity = identity
  }
  public func cached(_ project: Project) -> Project {
    self.prepareCache()
    var project = project
    if let cache = AppEnvironment.current.cache[KSCache.ksr_projectSaved] as? [Int: Bool],
       let saved = cache[project.id] { project.personalization.isStarred = saved }
    return project
  }
  private func cache(_ saved: Bool, for key: WatchIdentity) {
    guard self.isCurrent(key), let id = decompose(id: key.projectID) else { return }
    self.prepareCache()
    var cache = AppEnvironment.current.cache[KSCache.ksr_projectSaved] as? [Int: Bool] ?? [:]
    cache[id] = saved
    AppEnvironment.current.cache[KSCache.ksr_projectSaved] = cache
  }
  public func prepareWatch(projectID: String, watched: Bool, previous: Bool) -> WatchIntent {
    self.prepareCache()
    let intent = WatchIntent(key: self.watchIdentity(projectID), token: UUID(), watched: watched, previous: previous)
    self.watchIntents[intent.key] = (intent.token, false)
    self.cache(watched, for: intent.key)
    return intent
  }
  public func isCurrentIntent(_ intent: WatchIntent) -> Bool {
    self.isCurrent(intent.key) && self.watchIntents[intent.key]?.token == intent.token
  }
  public func cancelPreparedWatch(_ intent: WatchIntent) {
    guard self.isCurrentIntent(intent), self.watchIntents[intent.key]?.admitted == false else { return }
    self.cache(intent.previous, for: intent.key)
    self.watchIntents[intent.key] = nil
  }
  public func submitWatch(_ intent: WatchIntent) -> Task<WatchProjectResponseEnvelope, Error> {
    if let pending = self.watchSettlements[intent.token] { return pending }
    guard self.isCurrentIntent(intent) else { return Task { throw CancellationError() } }
    self.watchIntents[intent.key]?.admitted = true
    let command = self.requestWatch(projectID: intent.key.projectID, watched: intent.watched)
    let task = Task { [self] in
      defer { self.watchSettlements[intent.token] = nil }
      do {
        let value = try await command.value
        guard self.isCurrent(intent.key) else { throw CancellationError() }
        if self.isCurrentIntent(intent) { self.cache(intent.watched, for: intent.key) }
        return value
      } catch {
        guard self.isCurrent(intent.key) else { throw CancellationError() }
        if self.isCurrentIntent(intent) { self.cache(intent.previous, for: intent.key) }
        throw error
      }
    }
    self.watchSettlements[intent.token] = task
    return task
  }

  /// Ordinary save buttons retain their debounce and optimistic UI. Both entry
  /// points submit to the same account/project queue and settle the shared cache.
  public func watchResult(project: Project, intent: WatchIntent) -> SignalProducer<Project, Never> {
    let result = SignalProducer<Project, Never> { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.isCurrentIntent(intent) else { observer.sendInterrupted(); return }
        let command = self.submitWatch(intent)
        let id = UUID()
        let task = Task { [self] in
          defer { self.watchObservations[id] = nil }
          var project = project
          do {
            let response = try await command.value
            try Task.checkCancellation()
            guard self.isCurrentIntent(intent) else { observer.sendInterrupted(); return }
            project.watchesCount = response.watchProject.project.watchesCount
            project.personalization.isStarred = intent.watched
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.isCurrentIntent(intent) else {
              observer.sendInterrupted(); return
            }
            project.personalization.isStarred = intent.previous
          }
          observer.send(value: project)
          observer.sendCompleted()
        }
        self.watchObservations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
    return result.ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { _ in MainActor.assumeIsolated { self.isCurrentIntent(intent) } }
  }

  public func waitForOperations() async {
    while !self.watchWrites.isEmpty || !self.watchSettlements.isEmpty || !self.watchObservations.isEmpty {
      for pending in Array(self.watchWrites.values) { _ = await pending.task.result }
      for task in Array(self.watchSettlements.values) { _ = await task.result }
      for task in Array(self.watchObservations.values) { await task.value }
    }
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
    let intent = self.prepareWatch(projectID: item.projectId, watched: !wasSaved, previous: wasSaved)
    let mutation = self.submitWatch(intent)
    let token = UUID()
    let task = Task { [self] in
      defer {
        if self.feedSaves[route]?[projectID]?.token == token {
          self.feedSaves[route]?[projectID] = nil
        }
      }
      do {
        _ = try await mutation.value
      } catch {
        guard !(error is CancellationError), self.feeds[route] === feed,
              self.feedSaves[route]?[projectID]?.token == token,
              userID == AppEnvironment.current.currentUser?.id, self.isCurrentIntent(intent),
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
    self.prepareCache()
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

  public let sessionFeature: SessionFeature
  public init(
    sessionFeature: SessionFeature? = nil,
    preparePlayback: (@MainActor (URL, URL?) async throws -> PreparedProjectMedia)? = nil,
    makeProvider: @escaping () -> any ProjectMediaProvider
  ) {
    self.preparePlayback = preparePlayback ?? { try await ProjectMediaPreparation.load(url: $0, thumbnailURL: $1) }
    self.sessionFeature = sessionFeature ?? SessionFeature(makeProvider: {
      AsyncSessionProvider(service: AppEnvironment.current.apiService)
    })
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
