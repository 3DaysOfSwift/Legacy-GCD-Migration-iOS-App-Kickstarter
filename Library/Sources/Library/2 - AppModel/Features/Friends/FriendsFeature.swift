import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol FriendsProvider {
  func page(cursor: String?) async throws -> FindFriendsEnvelope
  func statistics() async throws -> FriendStatsEnvelope
  func setFollowing(userID: Int, following: Bool) async throws
  func followAll() async throws
}

@MainActor
public struct AsyncFriendsProvider: FriendsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(cursor: String?) async throws -> FindFriendsEnvelope {
    try await self.service.friendsPage(cursor: cursor)
  }
  public func statistics() async throws -> FriendStatsEnvelope {
    try await self.service.friendStatistics()
  }
  public func setFollowing(userID: Int, following: Bool) async throws {
    if following { _ = try await self.service.followUser(id: userID) }
    else { try await self.service.unfollowUser(id: userID) }
  }
  public func followAll() async throws { try await self.service.followEveryFriend() }
}

/// Owns Find Friends reads and the follow state shared with Activity.
/// Reads belong to a screen; admitted writes settle in account order even when a cell disappears.
@MainActor
public final class FriendsFeature {
  public struct Snapshot {
    public fileprivate(set) var users: [User] = []
    public fileprivate(set) var statistics: FriendStatsEnvelope?
    public fileprivate(set) var pageError: Error?
    public fileprivate(set) var statisticsError: Error?
  }
  private struct Session: Hashable {
    let userID: Int?
    let generation: Int
  }
  private final class Route {
    let session: Session
    var snapshot = Snapshot()
    var cursor: String?
    var started = false
    var page: (id: UUID, cursor: String?, task: Task<Void, Never>)?
    var statistics: (id: UUID, task: Task<Void, Never>)?
    init(session: Session) { self.session = session }
  }
  private enum Command: Equatable {
    case follow(Int, Bool)
    case all
  }
  private struct Pending {
    let id: UUID
    let command: Command
    let task: Task<Void, Error>
  }

  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any FriendsProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var routes: [UUID: Route] = [:]
  private var following: [Int: Bool] = [:]
  private var cacheSession: Session?
  private var tails: [Session: Pending] = [:]
  private var commands: [UUID: Task<Void, Error>] = [:]
  private var reads: [UUID: Task<Void, Never>] = [:]
  private var observations: [UUID: Task<Void, Never>] = [:]
  private let pagePipe = Signal<(UUID, [User]), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let statisticsPipe = Signal<(UUID, FriendStatsEnvelope), Never>.pipe()
  public var pageValues: Signal<(UUID, [User]), Never> { self.pagePipe.output }
  public var loadingValues: Signal<(UUID, Bool), Never> { self.loadingPipe.output }
  public var statisticsValues: Signal<(UUID, FriendStatsEnvelope), Never> { self.statisticsPipe.output }

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any FriendsProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private func requireCurrent(_ session: Session) throws {
    try Task.checkCancellation()
    guard self.session == session else { throw CancellationError() }
  }
  public func cached(_ user: User) -> User {
    if self.cacheSession != self.session {
      self.following.removeAll()
      self.cacheSession = self.session
    }
    var value = user
    if let following = self.following[user.id] { value.isFriend = following }
    return value
  }
  public func snapshot(route: UUID) -> Snapshot {
    guard let state = self.routes[route], state.session == self.session else { return Snapshot() }
    var snapshot = state.snapshot
    snapshot.users = snapshot.users.map(self.cached)
    return snapshot
  }
  private func state(route: UUID) -> Route {
    if let state = self.routes[route], state.session == self.session { return state }
    self.release(route: route)
    let state = Route(session: self.session)
    self.routes[route] = state
    return state
  }
  public func release(route: UUID) {
    self.routes[route]?.page?.task.cancel()
    self.routes[route]?.statistics?.task.cancel()
    self.routes[route] = nil
  }
  public func reset() {
    for route in Array(self.routes.keys) { self.release(route: route) }
    self.following.removeAll()
    self.cacheSession = self.session
    for task in self.observations.values { task.cancel() }
  }

  public func refresh(route: UUID) async { await self.requestPage(route: route)?.value }
  public func loadNextPage(route: UUID) async { await self.requestPage(route: route, next: true)?.value }

  @discardableResult
  public func requestPage(route: UUID, next: Bool = false) -> Task<Void, Never>? {
    let state = self.state(route: route)
    if let pending = state.page, next || pending.cursor == nil { return pending.task }
    guard !next || state.cursor != nil else { return nil }
    state.page?.task.cancel()
    let cursor = next ? state.cursor : nil
    if !next, state.started {
      state.snapshot.users = []
      self.pagePipe.input.send(value: (route, []))
    }
    state.started = true
    state.snapshot.pageError = nil
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    // A new read waits for already-admitted writes. Reads never cancel writes.
    let predecessor = self.tails[state.session]?.task
    let task = Task { [self] in
      defer {
        self.reads[id] = nil
        if state.page?.id == id {
          state.page = nil
          if self.routes[route] === state, self.session == state.session {
            self.loadingPipe.input.send(value: (route, false))
          }
        }
      }
      do {
        if let predecessor { _ = await predecessor.result }
        try self.requireCurrent(state.session)
        let page = try await provider.page(cursor: cursor)
        try await self.sleep(delay)
        try self.requireCurrent(state.session)
        guard self.routes[route] === state, state.page?.id == id else { return }
        state.cursor = page.users.isEmpty ? nil : page.urls.api.moreUsers
        let users = page.users.map(self.cached)
        state.snapshot.users = cursor == nil ? users : state.snapshot.users + users
        self.pagePipe.input.send(value: (route, state.snapshot.users))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.session == state.session,
              self.routes[route] === state, state.page?.id == id else { return }
        state.snapshot.pageError = error
      }
    }
    state.page = (id, cursor, task)
    self.reads[id] = task
    self.loadingPipe.input.send(value: (route, true))
    return task
  }

  public func refreshStatistics(route: UUID) async { await self.requestStatistics(route: route).value }
  @discardableResult
  public func requestStatistics(route: UUID) -> Task<Void, Never> {
    let state = self.state(route: route)
    if let pending = state.statistics { return pending.task }
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    state.snapshot.statisticsError = nil
    let task = Task { [self] in
      defer {
        self.reads[id] = nil
        if state.statistics?.id == id { state.statistics = nil }
      }
      do {
        try self.requireCurrent(state.session)
        let statistics = try await provider.statistics()
        try await self.sleep(delay)
        try self.requireCurrent(state.session)
        guard self.routes[route] === state, state.statistics?.id == id else { return }
        state.snapshot.statistics = statistics
        self.statisticsPipe.input.send(value: (route, statistics))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.session == state.session,
              self.routes[route] === state, state.statistics?.id == id else { return }
        state.snapshot.statisticsError = error
      }
    }
    state.statistics = (id, task)
    self.reads[id] = task
    return task
  }

  private func request(_ command: Command) -> Task<Void, Error> {
    let session = self.session
    let previous = self.tails[session]
    if let previous, previous.command == command { return previous.task }
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.commands[id] = nil
        if self.tails[session]?.id == id { self.tails[session] = nil }
      }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(session)
      do {
        switch command {
        case .follow(let userID, let following):
          try await provider.setFollowing(userID: userID, following: following)
        case .all: try await provider.followAll()
        }
        try self.requireCurrent(session)
        if self.cacheSession != session { self.following.removeAll(); self.cacheSession = session }
        switch command {
        case .follow(let userID, let following): self.following[userID] = following
        case .all:
          self.following.removeAll()
          // A pre-write page cannot repopulate the list during the delayed refresh.
          for state in self.routes.values where state.session == session {
            state.page?.task.cancel()
            state.page = nil
            state.cursor = nil
            state.snapshot.users = []
          }
        }
      } catch {
        try self.requireCurrent(session)
        throw error
      }
    }
    self.tails[session] = Pending(id: id, command: command, task: task)
    self.commands[id] = task
    return task
  }

  private func execute(_ command: Command) async throws {
    try Task.checkCancellation()
    let session = self.session
    do {
      try await self.request(command).value
      try self.requireCurrent(session)
    } catch {
      try self.requireCurrent(session)
      throw error
    }
  }

  public func setFollowing(user: User, following: Bool) async throws -> User {
    try await self.execute(.follow(user.id, following))
    var value = user
    value.isFriend = following
    return value
  }
  public func followAll() async throws { try await self.execute(.all) }

  // Compatibility outputs carry values only; the Feature owns native async execution.
  public func setFollowingResult(user: User, following: Bool) -> SignalProducer<User, ErrorEnvelope> {
    self.result(.follow(user.id, following)).map {
      var value = user
      value.isFriend = following
      return value
    }
  }
  public func followAllResult() -> SignalProducer<Void, ErrorEnvelope> { self.result(.all) }
  private func result(_ command: Command) -> SignalProducer<Void, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else { observer.sendInterrupted(); return }
        let commandTask = self.request(command)
        let id = UUID()
        let task = Task { [self] in
          defer { self.observations[id] = nil }
          do {
            try await commandTask.value
            try self.requireCurrent(session)
            observer.send(value: ())
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session else {
              observer.sendInterrupted()
              return
            }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  /// Retains the established UI delay without allowing a previous account's delayed output through.
  public func delayed<Value>(_ producer: SignalProducer<Value, ErrorEnvelope>)
    -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return producer.ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .materialize()
      .filter { _ in MainActor.assumeIsolated { self.session == session } }
      .dematerialize()
  }

  public func waitForOperations() async {
    while !self.commands.isEmpty || !self.observations.isEmpty || !self.reads.isEmpty {
      for task in Array(self.commands.values) { _ = await task.result }
      for task in Array(self.reads.values) { await task.value }
      for task in Array(self.observations.values) { await task.value }
    }
  }
}
