import Foundation
import KsApi
import Prelude
import ReactiveSwift

/// Read boundary shared by project comments, update comments and reply threads.
@MainActor
public protocol DiscussionProvider {
  func comments(slug: String?, updateID: String?, cursor: String?) async throws -> CommentsEnvelope
  func replies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope
  func project(param: Param) async throws -> Project
  func update(id: Int, project: Param) async throws -> Update
  func post(input: PostCommentInput) async throws -> Comment
  func block(id: String) async throws -> EmptyResponseEnvelope
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

  public func post(input: PostCommentInput) async throws -> Comment {
    try await self.service.submitDiscussionComment(input: input)
  }

  public func block(id: String) async throws -> EmptyResponseEnvelope {
    try await self.service.blockDiscussionUser(id: id)
  }
}

/// Owns discussion reads and durable mutations. Screen release cancels reads,
/// never an admitted write: server cancellation cannot roll back a comment.
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

  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any DiscussionProvider
  // Mutations have stable attempt identity, independent from page routes.
  // Identical text submitted deliberately twice has two operation IDs; retries
  // of one failed comment share its ID while the request is in flight.
  private struct PostIdentity: Hashable {
    let operationID: String
    let body: String
    let commentableID: String
    let parentID: String?
    let userID: Int?
    let generation: Int
  }

  private struct BlockIdentity: Hashable {
    let targetID: String
    let userID: Int?
    let generation: Int
  }

  private var posts: [PostIdentity: Task<Comment, Error>] = [:]
  private var blocks: [BlockIdentity: Task<EmptyResponseEnvelope, Error>] = [:]
  private let postResults = Signal<(PostIdentity, Result<Comment, Error>), Never>.pipe()
  private let blockResults = Signal<(BlockIdentity, Result<EmptyResponseEnvelope, Error>), Never>.pipe()
  private var activePosts = 0
  private var waitingPosts: [CheckedContinuation<Void, Never>] = []

  /// Preserve the existing five-request limit without blocking an executor.
  /// Distinct writes queue FIFO for admission, then may finish independently.
  private func acquirePostSlot() async {
    if self.activePosts < 5 {
      self.activePosts += 1
    } else {
      await withCheckedContinuation { self.waitingPosts.append($0) }
    }
  }

  private func releasePostSlot() {
    if self.waitingPosts.isEmpty {
      self.activePosts -= 1
    } else {
      self.waitingPosts.removeFirst().resume()
    }
  }

  public func post(
    operationID: String, body: String, commentableID: String, parentID: String?
  ) async throws -> Comment {
    try Task.checkCancellation()
    let comment = try await self.requestPost(
      operationID: operationID, body: body, commentableID: commentableID, parentID: parentID
    ).value
    try Task.checkCancellation()
    return comment
  }

  @discardableResult
  public func requestPost(
    operationID: String, body: String, commentableID: String, parentID: String?
  ) -> Task<Comment, Error> {
    let key = PostIdentity(
      operationID: operationID, body: body, commentableID: commentableID,
      parentID: parentID, userID: AppEnvironment.current.currentUser?.id, generation: self.sessionFeature.generation
    )
    // Cancelling a waiter must not cancel a mutation another caller still needs.
    return self.requestPost(key)
  }

  private func requestPost(_ key: PostIdentity) -> Task<Comment, Error> {
    if let task = self.posts[key] { return task }
    let provider = self.makeProvider()
    let task = Task { [self] in
      await self.acquirePostSlot()
      defer {
        self.posts[key] = nil
        self.releasePostSlot()
      }
      let result: Result<Comment, Error>
      do {
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) else { throw CancellationError() }
        let comment = try await provider.post(input: PostCommentInput(
          body: key.body, commentableId: key.commentableID, parentId: key.parentID
        ))
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) else { throw CancellationError() }
        result = .success(comment)
      } catch {
        result = .failure(
          self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) ? error : CancellationError()
        )
      }
      self.postResults.input.send(value: (key, result))
      return try result.get()
    }
    self.posts[key] = task
    return task
  }

  public func blockUser(id: String) async throws -> EmptyResponseEnvelope {
    try Task.checkCancellation()
    let result = try await self.requestBlockUser(id: id).value
    try Task.checkCancellation()
    return result
  }

  @discardableResult
  public func requestBlockUser(id: String) -> Task<EmptyResponseEnvelope, Error> {
    self.requestBlock(BlockIdentity(targetID: id, userID: AppEnvironment.current.currentUser?.id, generation: self.sessionFeature.generation))
  }

  private func requestBlock(_ key: BlockIdentity) -> Task<EmptyResponseEnvelope, Error> {
    if let task = self.blocks[key] { return task }
    let provider = self.makeProvider()
    // Different users are independent writes, not replaceable searches.
    let task = Task { [self] in
      defer { self.blocks[key] = nil }
      let result: Result<EmptyResponseEnvelope, Error>
      do {
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) else { throw CancellationError() }
        let response = try await provider.block(id: key.targetID)
        try Task.checkCancellation()
        guard self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) else { throw CancellationError() }
        result = .success(response)
      } catch {
        result = .failure(
          self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) ? error : CancellationError()
        )
      }
      self.blockResults.input.send(value: (key, result))
      return try result.get()
    }
    self.blocks[key] = task
    return task
  }

  // UIKit compatibility only: subscriptions observe Feature-owned work. Disposal
  // removes delivery, never cancels an admitted write or retries it automatically.
  // Callers start these producers on MainActor, as their ViewModels require.
  private func commentResult(
    operationID: String, body: String, commentableID: String, parentID: String?
  ) -> SignalProducer<Comment, ErrorEnvelope> {
    // Capture before a retry's presentation delay, not when its subscription
    // eventually starts; otherwise an account switch could post old text as a new user.
    let key = PostIdentity(
      operationID: operationID, body: body, commentableID: commentableID,
      parentID: parentID, userID: AppEnvironment.current.currentUser?.id, generation: self.sessionFeature.generation
    )
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.sessionFeature.isCurrent(userID: key.userID, generation: key.generation) else {
          observer.sendInterrupted()
          return
        }
        let subscription = self.postResults.output.filter { $0.0 == key }.take(first: 1)
          .observeValues { _, result in
            switch result {
            case let .success(comment):
              observer.send(value: comment)
              observer.sendCompleted()
            case .failure(is CancellationError): observer.sendInterrupted()
            case let .failure(error): observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
            }
          }
        lifetime.observeEnded { subscription?.dispose() }
        _ = self.requestPost(key)
      }
    }
  }

  /// Keep delayed presentation bound to the initiating session too. A completed
  /// request can otherwise sit on the scheduler until after logout/login.
  func blockUserEvents(id: String) -> SignalProducer<Signal<EmptyResponseEnvelope, ErrorEnvelope>.Event, Never> {
    let userID = self.sessionFeature.currentUser?.id
    let generation = self.sessionFeature.generation
    return self.blockUserResult(id: id)
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .materialize()
      .filter { _ in self.sessionFeature.isCurrent(userID: userID, generation: generation) }
  }

  func blockUserResult(id: String) -> SignalProducer<EmptyResponseEnvelope, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let key = BlockIdentity(targetID: id, userID: AppEnvironment.current.currentUser?.id, generation: self.sessionFeature.generation)
        let subscription = self.blockResults.output.filter { $0.0 == key }.take(first: 1)
          .observeValues { _, result in
            switch result {
            case let .success(response):
              observer.send(value: response)
              observer.sendCompleted()
            case .failure(is CancellationError): observer.sendInterrupted()
            case let .failure(error): observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
            }
          }
        lifetime.observeEnded { subscription?.dispose() }
        _ = self.requestBlock(key)
      }
    }
  }

  /// Test synchronization for the existing scheduler-driven presentation adapters.
  /// Awaiting writes does not advance or bypass their visible status delays.
  func waitForMutations() async {
    let posts = Array(self.posts.values)
    let blocks = Array(self.blocks.values)
    for task in posts { _ = await task.result }
    for task in blocks { _ = await task.result }
  }

  private let sleep: (TimeInterval) async throws -> Void
  private var pages: [UUID: PageRoute] = [:]
  private let pagePipe = Signal<(UUID, [Comment], Int), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let errorPipe = Signal<(UUID, ErrorEnvelope), Never>.pipe()
  public var pageValues: Signal<(UUID, [Comment], Int), Never> { self.pagePipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }
  public var errors: Signal<(UUID, ErrorEnvelope), Never> { self.errorPipe.output }

  public init(
    sessionFeature: SessionFeature,
    makeProvider: @escaping () -> any DiscussionProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
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

extension DiscussionFeature {
  // MARK: Properties

  static let concurrentCommentLimit: UInt = 5

  // MARK: Helpers

  // Preserve optimistic/retry status timing for the existing UIKit screens.
  func retryCommentProducer(
    erroredComment comment: Comment,
    commentableId: String,
    parentId: String?
  ) -> SignalProducer<(Comment, String), Never> {
    // Retry posting the comment.
    let userID = AppEnvironment.current.currentUser?.id
    return self.commentResult(
      operationID: comment.id, body: comment.body, commentableID: commentableId, parentID: parentId
    )
    .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
    // Return a producer with the successful comment that is prefixed by a comment indicating that the
    // retry was successful and then, after a 3 second delay, the actual successful comment is returned.
    .flatMap { successfulComment -> SignalProducer<Comment, ErrorEnvelope> in
      let retrySuccessComment = successfulComment.updatingStatus(to: .retrySuccess)
        |> \.id .~ comment.id // Inject the original errored comment's ID to replace.

      return SignalProducer(value: successfulComment)
        .ksr_delay(.seconds(3), on: AppEnvironment.current.scheduler)
        .prefix(value: retrySuccessComment)
    }
    // Immediately return a comment in a retrying state when this producer starts.
    // Delay further emissions by 1 sec.
    .prefix(
      SignalProducer(value: comment.updatingStatus(to: .retrying))
        .ksr_delay(.seconds(1), on: AppEnvironment.current.scheduler)
        .prefix(value: comment.updatingStatus(to: .retrying))
    )
    // If retrying errors again, return the original comment returning it to its errored state.
    .demoteErrors(replaceErrorWith: comment)
    .filter { _ in AppEnvironment.current.currentUser?.id == userID }
    // Return the comment that will be replaced with the ID to find it by.
    .map { replacementComment in (replacementComment, comment.id) }
  }

  func postCommentProducer(
    project: Project,
    commentableId: String,
    parentId: String?,
    user: User,
    body: String
  ) -> SignalProducer<(Comment, String), Never> {
    let userID = AppEnvironment.current.currentUser?.id
    let failableComment = Comment.failableComment(
      withId: AppEnvironment.current.uuidType.init().uuidString,
      date: AppEnvironment.current.dateType.init().date,
      project: project,
      parentId: parentId,
      user: user,
      body: body
    )
    // Post the new comment or comment reply.
    return self.commentResult(
      operationID: UUID().uuidString, body: body, commentableID: commentableId, parentID: parentId
    )
    .ksr_delay(.seconds(1), on: AppEnvironment.current.scheduler)
    // Immediately return a failable comment with a generated ID.
    .prefix(value: failableComment)
    // If the request errors we return the failableComment in a failed state.
    .flatMapError { _ in
      SignalProducer(value: failableComment.updatingStatus(to: .failed))
        .ksr_delay(.seconds(1), on: AppEnvironment.current.scheduler)
    }
    // Once the request completes return the actual comment and replace it by its ID.
    .filter { _ in AppEnvironment.current.currentUser?.id == userID }
    .map { commentOrFailable in (commentOrFailable, failableComment.id) }
  }
}
