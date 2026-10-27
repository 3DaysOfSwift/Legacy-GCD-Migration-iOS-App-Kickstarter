import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol ProfileProvider {
  func page(type: ProfileProjectsType, cursor: String?) async throws -> ProfileFeature.Page
}

@MainActor
public struct AsyncProfileProvider: ProfileProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(type: ProfileProjectsType, cursor: String?) async throws -> ProfileFeature.Page {
    switch type {
    case .backed:
      let data = try await self.service.profileBackedProjects(cursor: cursor)
      return ProfileFeature.Page(
        projects: data.projects?.nodes?.compactMap { $0?.fragments.projectCardFragment }
          .compactMap(ProjectCardProperties.init) ?? [],
        cursor: data.projects?.pageInfo.hasNextPage == true ? data.projects?.pageInfo.endCursor : nil
      )
    case .saved:
      let data = try await self.service.profileSavedProjects(cursor: cursor)
      return ProfileFeature.Page(
        projects: data.projects?.nodes?.compactMap { $0?.fragments.projectCardFragment }
          .compactMap(ProjectCardProperties.init) ?? [],
        cursor: data.projects?.pageInfo.hasNextPage == true ? data.projects?.pageInfo.endCursor : nil
      )
    }
  }
}

/// Owns Profile's backed/saved collections and header refresh composition.
/// Header reads remain concurrent and fail independently.
@MainActor
public final class ProfileFeature {
  public struct Page {
    public let projects: [ProjectCardProperties]
    public let cursor: String?
    public init(projects: [ProjectCardProperties], cursor: String?) {
      self.projects = projects
      self.cursor = cursor
    }
  }

  public struct Snapshot {
    public fileprivate(set) var projects: [ProjectCardProperties] = []
    public fileprivate(set) var error: Error?
    public fileprivate(set) var isLoading = false
  }

  private final class Route {
    let userID: Int?
    let generation: Int
    var snapshot = Snapshot()
    var cursor: String?
    var request: (token: UUID, cursor: String?, task: Task<Void, Never>)?
    init(userID: Int?, generation: Int) { self.userID = userID; self.generation = generation }
  }

  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any ProfileProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var pages: [ProfileProjectsType: Route] = [:]
  private var headerRequest: (userID: Int?, generation: Int, token: UUID, task: Task<Void, Never>)?
  public private(set) var userError: Error?
  public private(set) var graphUserError: Error?
  private let userPipe = Signal<User, Never>.pipe()
  private let graphUserPipe = Signal<User, Never>.pipe()
  private let combinedUserPipe = Signal<User, Never>.pipe()
  private let projectsPipe = Signal<(ProfileProjectsType, [ProjectCardProperties]), Never>.pipe()
  private let loadingPipe = Signal<(ProfileProjectsType, Bool), Never>.pipe()
  public var userValues: Signal<User, Never> { self.userPipe.output }
  public var graphUserValues: Signal<User, Never> { self.graphUserPipe.output }
  public var combinedUserValues: Signal<User, Never> { self.combinedUserPipe.output }
  public var projectValues: Signal<(ProfileProjectsType, [ProjectCardProperties]), Never> {
    self.projectsPipe.output
  }

  public var loadingValues: Signal<(ProfileProjectsType, Bool), Never> { self.loadingPipe.output }

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any ProfileProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  public func reset() {
    self.headerRequest?.task.cancel()
    self.headerRequest = nil
    for page in self.pages.values { page.request?.task.cancel() }
    self.pages.removeAll()
    self.userError = nil
    self.graphUserError = nil
  }

  public func snapshot(for type: ProfileProjectsType) -> Snapshot {
    guard let page = self.pages[type],
          self.sessionFeature.isCurrent(userID: page.userID, generation: page.generation)
    else { return Snapshot() }
    return page.snapshot
  }

  public func projectCount(for type: ProfileProjectsType) -> Int {
    switch type {
    case .backed: return self.sessionFeature.currentUser?.stats.backedProjectsCount ?? 0
    case .saved: return self.sessionFeature.currentUser?.stats.starredProjectsCount ?? 0
    }
  }

  public func refreshHeader() async { await self.requestHeader().value }
  @discardableResult
  public func requestHeader(replacing: Bool = false) -> Task<Void, Never> {
    let userID = self.sessionFeature.currentUser?.id
    guard userID != nil else { self.reset(); return Task {} }
    let generation = self.sessionFeature.generation
    if !replacing, let request = self.headerRequest, request.userID == userID,
       request.generation == generation { return request.task }
    self.headerRequest?.task.cancel()
    if replacing { self.sessionFeature.invalidateReads() }
    let token = UUID()
    let userTask = self.sessionFeature.request(.user)
    let graphTask = self.sessionFeature.request(.graphUser)
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.userError = nil
    self.graphUserError = nil
    if let user = self.sessionFeature.currentUser { self.userPipe.input.send(value: user) }
    let task = Task { [weak self] in
      guard let self else { return }
      defer { if self.headerRequest?.token == token { self.headerRequest = nil } }
      async let user = self.publishHeader(
        userTask,
        graph: false,
        userID: userID,
        generation: generation,
        delay: delay
      )
      async let graph = self.publishHeader(
        graphTask,
        graph: true,
        userID: userID,
        generation: generation,
        delay: delay
      )
      let (restUser, graphUser) = await (user, graph)
      guard !Task.isCancelled, self.headerRequest?.token == token,
            self.sessionFeature.isCurrent(userID: userID, generation: generation),
            var merged = restUser, let graphUser else { return }
      merged.stats.starredProjectsCount = graphUser.stats.starredProjectsCount
      self.combinedUserPipe.input.send(value: merged)
    }
    self.headerRequest = (userID, generation, token, task)
    return task
  }

  private func publishHeader(
    _ task: Task<User, Error>, graph: Bool, userID: Int?, generation: Int, delay: TimeInterval
  ) async -> User? {
    do {
      let user = try await task.value
      try await self.sleep(delay)
      try Task.checkCancellation()
      guard self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return nil }
      if graph { self.graphUserPipe.input.send(value: user) }
      else { self.userPipe.input.send(value: user) }
      return user
    } catch {
      guard !Task.isCancelled, !(error is CancellationError), self.sessionFeature.isCurrent(
        userID: userID,
        generation: generation
      ) else { return nil }
      if graph { self.graphUserError = error } else { self.userError = error }
      return nil
    }
  }

  public func refresh(type: ProfileProjectsType) async { await self.requestPage(type: type)?.value }
  public func loadNextPage(type: ProfileProjectsType) async {
    await self.requestPage(type: type, next: true)?.value
  }

  @discardableResult
  public func requestPage(type: ProfileProjectsType, next: Bool = false) -> Task<Void, Never>? {
    let userID = self.sessionFeature.currentUser?.id
    guard userID != nil else { self.reset(); return nil }
    let generation = self.sessionFeature.generation
    let page: Route
    if let existing = self.pages[type], existing.userID == userID, existing.generation == generation {
      page = existing
    } else {
      self.pages[type]?.request?.task.cancel()
      page = Route(userID: userID, generation: generation)
      self.pages[type] = page
    }
    if let request = page.request, next || request.cursor == nil { return request.task }
    guard !next || page.cursor != nil else { return nil }
    page.request?.task.cancel()
    let cursor = next ? page.cursor : nil
    let token = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    page.snapshot.isLoading = true
    page.snapshot.error = nil
    let task = Task { [weak self, sleep] in
      guard let self else { return }
      defer {
        if page.request?.token == token {
          page.request = nil
          page.snapshot.isLoading = false
          if self.pages[type] === page { self.loadingPipe.input.send(value: (type, false)) }
        }
      }
      do {
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        let result = try await provider.page(type: type, cursor: cursor)
        try await sleep(delay)
        try Task.checkCancellation()
        guard self.pages[type] === page, page.request?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        page.cursor = result.projects.isEmpty ? nil : result.cursor
        page.snapshot.projects = cursor == nil ? result.projects : page.snapshot.projects + result.projects
        self.projectsPipe.input.send(value: (type, page.snapshot.projects))
      } catch {
        guard !Task.isCancelled, !(error is CancellationError), self.pages[type] === page,
              page.request?.token == token,
              self.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        page.snapshot.error = error
      }
    }
    page.request = (token, cursor, task)
    self.loadingPipe.input.send(value: (type, true))
    return task
  }
}
