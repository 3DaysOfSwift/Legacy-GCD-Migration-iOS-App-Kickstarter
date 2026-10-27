import Foundation
import KsApi
import ReactiveSwift

/// Read boundary shared by project comments, update comments and reply threads.
@MainActor
public protocol DiscussionProvider {
  func comments(slug: String?, updateID: String?, cursor: String?) async throws -> CommentsEnvelope
  func replies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope
  func project(param: Param) async throws -> Project
  func update(id: Int, project: Param) async throws -> Update
}

@MainActor
public struct AsyncDiscussionProvider: DiscussionProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func comments(slug: String?, updateID: String?, cursor: String?) async throws -> CommentsEnvelope {
    try await self.service.discussionComments(slug: slug, updateID: updateID, cursor: cursor)
  }

  public func replies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope {
    try await self.service.discussionReplies(id: id, cursor: cursor)
  }

  public func project(param: Param) async throws -> Project {
    try await self.service.discussionProject(param: param)
  }

  public func update(id: Int, project: Param) async throws -> Update {
    try await self.service.projectUpdate(id: id, project: project)
  }
}

/// Owns read identity, page cursors and cancellation. Optimistic comment writes
/// remain on the legacy transaction path until their separate migration.
@MainActor
public final class DiscussionFeature {
  public enum Source: Equatable {
    case project(String)
    case update(String)
    case replies(String)
  }

  public struct PageSnapshot {
    public fileprivate(set) var comments: [Comment] = []
    public fileprivate(set) var totalCount = 0
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
  }

  private final class PageRoute {
    var source: Source
    let userID: Int?
    var nextSource: Source?
    var cursor: String?
    var snapshot = PageSnapshot()
    var hasReceivedPage = false
    var request: (id: UUID, task: Task<Void, Never>)?
    init(source: Source, userID: Int?) {
      self.source = source
      self.userID = userID
    }
  }

  private let makeProvider: () -> any DiscussionProvider
  private let sleep: (TimeInterval) async throws -> Void
  private var pages: [UUID: PageRoute] = [:]
  private let pagePipe = Signal<(UUID, [Comment], Int), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let errorPipe = Signal<(UUID, ErrorEnvelope), Never>.pipe()
  public var pageValues: Signal<(UUID, [Comment], Int), Never> { self.pagePipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }
  public var errors: Signal<(UUID, ErrorEnvelope), Never> { self.errorPipe.output }

  public init(
    makeProvider: @escaping () -> any DiscussionProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  public func snapshot(for route: UUID) -> PageSnapshot {
    self.pages[route]?.snapshot ?? PageSnapshot()
  }

  public func loadFirstPage(route: UUID, source: Source, refresh: Bool = false) async {
    guard !Task.isCancelled else { return }
    await self.requestFirstPage(route: route, source: source, refresh: refresh).value
  }

  /// Equivalent initial reads share work. Explicit refresh/retry replaces only
  /// this route, including a page request that was still in flight.
  @discardableResult
  public func requestFirstPage(route: UUID, source: Source, refresh: Bool = false) -> Task<Void, Never> {
    let userID = AppEnvironment.current.currentUser?.id
    let previous = self.pages[route]
    if !refresh, let previous, previous.source == source, previous.userID == userID,
       let request = previous.request { return request.task }
    previous?.request?.task.cancel()
    let page = PageRoute(source: source, userID: userID)
    self.pages[route] = page
    // paginate(clearOnNewRequest:) suppressed the first clear but emitted later clears.
    if let previous {
      if case .replies = source {
        // The reply adapter's total-count signal had no value until the first
        // successful envelope. A retry after an initial failure emitted no clear.
        page.hasReceivedPage = previous.hasReceivedPage
        page.snapshot.totalCount = previous.snapshot.totalCount
        if previous.hasReceivedPage {
          self.pagePipe.input.send(value: (route, [], previous.snapshot.totalCount))
        }
      } else {
        self.pagePipe.input.send(value: (route, [], 0))
      }
    }
    return self.startPage(route: route, page: page, source: source, cursor: nil)
  }

  public func loadNextPage(route: UUID) async {
    guard !Task.isCancelled else { return }
    await self.requestNextPage(route: route)?.value
  }

  @discardableResult
  public func requestNextPage(route: UUID) -> Task<Void, Never>? {
    guard let page = self.pages[route],
          page.userID == AppEnvironment.current.currentUser?.id else { return nil }
    if let request = page.request { return request.task }
    guard let source = page.nextSource else { return nil }
    return self.startPage(route: route, page: page, source: source, cursor: page.cursor)
  }

  private func startPage(
    route: UUID, page: PageRoute, source: Source, cursor: String?
  ) -> Task<Void, Never> {
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let sleep = self.sleep
    let requestID = UUID()
    page.snapshot.isLoading = true
    page.snapshot.error = nil
    let task = Task { [weak self] in
      defer {
        if let self, self.pages[route]?.request?.id == requestID {
          page.request = nil
          page.snapshot.isLoading = false
          self.loadingPipe.input.send(value: (route, false))
        }
      }
      do {
        try Task.checkCancellation()
        guard page.userID == AppEnvironment.current.currentUser?.id else { throw CancellationError() }
        let comments: [Comment]
        let count: Int
        let nextSource: Source?
        let nextCursor: String?
        switch source {
        case let .replies(id):
          let envelope = try await provider.replies(id: id, cursor: cursor)
          comments = envelope.replies
          count = envelope.totalCount
          nextCursor = envelope.cursor
          nextSource = .replies(envelope.comment.id)
        case .project, .update:
          let slug: String?
          let updateID: String?
          switch source {
          case let .project(value): slug = value; updateID = nil
          case let .update(value): slug = nil; updateID = value
          case .replies: throw ErrorEnvelope.couldNotParseJSON
          }
          let envelope = try await provider.comments(slug: slug, updateID: updateID, cursor: cursor)
          comments = envelope.comments
          count = envelope.totalCount
          nextCursor = envelope.cursor
          nextSource = envelope.slug.map(Source.project) ?? envelope.updateID.map(Source.update)
        }
        try await sleep(delay)
        try Task.checkCancellation()
        guard let self, self.pages[route]?.request?.id == requestID,
              page.userID == AppEnvironment.current.currentUser?.id else { return }
        page.snapshot.comments = comments
        page.hasReceivedPage = true
        page.snapshot.totalCount = count
        page.cursor = nextCursor
        // Preserve the existing empty-page sentinel (not the envelope flags).
        page.nextSource = comments.isEmpty ? nil : nextSource
        self.pagePipe.input.send(value: (route, comments, count))
      } catch is CancellationError {
        // Navigation, refresh and account changes never become visible errors.
      } catch DiscussionResponseError.missingEnvelope {
        // The legacy decoder completed silently: retain data/cursor and finish
        // loading without inventing either an empty page or a visible error.
      } catch {
        do { try await sleep(delay) } catch { return }
        guard !Task.isCancelled, let self, self.pages[route]?.request?.id == requestID,
              page.userID == AppEnvironment.current.currentUser?.id else { return }
        let failure = (error as? ErrorEnvelope) ?? .couldNotParseJSON
        page.snapshot.error = failure
        self.errorPipe.input.send(value: (route, failure))
      }
    }
    page.request = (requestID, task)
    self.loadingPipe.input.send(value: (route, true))
    return task
  }

  // Independent read routes preserve the update-list's distinct update/comments
  // navigation streams and the comment screen's project-context request.
  private struct UpdateIdentity: Equatable {
    let project: Param
    let id: Int
    let userID: Int?
  }

  private var updates: [UUID: (identity: UpdateIdentity, id: UUID, task: Task<Void, Never>)] = [:]
  private var projects: [UUID: (param: Param, userID: Int?, id: UUID, task: Task<Void, Never>)] = [:]
  private let updatePipe = Signal<(UUID, Update), Never>.pipe()
  private let projectPipe = Signal<(UUID, Project), Never>.pipe()
  public var updateValues: Signal<(UUID, Update), Never> { self.updatePipe.output }
  public var projectValues: Signal<(UUID, Project), Never> { self.projectPipe.output }

  public func loadUpdate(route: UUID, id: Int, project: Param) async {
    guard !Task.isCancelled else { return }
    await self.requestUpdate(route: route, id: id, project: project).value
  }

  @discardableResult
  public func requestUpdate(route: UUID, id: Int, project: Param) -> Task<Void, Never> {
    let identity = UpdateIdentity(project: project, id: id, userID: AppEnvironment.current.currentUser?.id)
    if let existing = self.updates[route], existing.identity == identity { return existing.task }
    self.updates[route]?.task.cancel()
    let provider = self.makeProvider()
    let token = UUID()
    let task = Task { [weak self] in
      defer { if self?.updates[route]?.id == token { self?.updates[route] = nil } }
      do {
        try Task.checkCancellation()
        guard identity.userID == AppEnvironment.current.currentUser?.id else { return }
        let update = try await provider.update(id: id, project: project)
        try Task.checkCancellation()
        guard let self, self.updates[route]?.id == token,
              identity.userID == AppEnvironment.current.currentUser?.id else { return }
        self.updatePipe.input.send(value: (route, update))
      } catch {
        // Existing navigation silently demotes lookup errors.
      }
    }
    self.updates[route] = (identity, token, task)
    return task
  }

  public func loadProject(route: UUID, param: Param) async {
    guard !Task.isCancelled else { return }
    await self.requestProject(route: route, param: param).value
  }

  @discardableResult
  public func requestProject(route: UUID, param: Param) -> Task<Void, Never> {
    let userID = AppEnvironment.current.currentUser?.id
    if let existing = self.projects[route], existing.param == param, existing.userID == userID {
      return existing.task
    }
    self.projects[route]?.task.cancel()
    let provider = self.makeProvider()
    let token = UUID()
    let task = Task { [weak self] in
      defer { if self?.projects[route]?.id == token { self?.projects[route] = nil } }
      do {
        try Task.checkCancellation()
        guard userID == AppEnvironment.current.currentUser?.id else { return }
        let project = try await provider.project(param: param)
        try Task.checkCancellation()
        guard let self, self.projects[route]?.id == token,
              userID == AppEnvironment.current.currentUser?.id else { return }
        self.projectPipe.input.send(value: (route, project))
      } catch {
        // Preserve the legacy context lookup's silent error delivery.
      }
    }
    self.projects[route] = (param, userID, token, task)
    return task
  }

  public func release(route: UUID) {
    self.pages.removeValue(forKey: route)?.request?.task.cancel()
    self.updates.removeValue(forKey: route)?.task.cancel()
    self.projects.removeValue(forKey: route)?.task.cancel()
  }

  public func cancelProject(route: UUID) {
    self.projects.removeValue(forKey: route)?.task.cancel()
  }
}
