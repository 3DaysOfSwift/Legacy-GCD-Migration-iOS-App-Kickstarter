import Foundation
import KsApi
import Prelude

@MainActor
public protocol CommentsViewModelInputs {
  /// Call when block user is tapped
  func blockUser(id: String)

  /// Call when the delegate method for the CommentCellDelegate is called.
  func commentCellDidTapReply(comment: Comment)

  /// Call when the delegate method for the CommentCellDelegate is called.
  func commentCellDidTapViewReplies(_ comment: Comment)

  /// Call when the User is posting a comment or reply.
  func commentComposerDidSubmitText(_ text: String)

  /// Call when the delegate method for the CommentRemovedCellDelegate is called.
  func commentRemovedCellDidTapURL(_ url: URL)

  /// Call when the user tapped to retry after failed pagination.
  func commentTableViewFooterViewDidTapRetry()

  /// Call with the project/update that we are viewing comments for. Both can be provided to minimize
  /// the number of API requests made, but it will be assumed we are viewing the comments for the update.
  func configureWith(project: Project?, update: Update?)

  /// Call with a `Comment` when it is selected.
  func didSelectComment(_ comment: Comment)

  ///  Call when pull-to-refresh is invoked.
  func refresh()

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when a new row is displayed.
  func willDisplayRow(_ row: Int, outOf totalRows: Int)
}

@MainActor
public protocol CommentsViewModelOutputs: AnyObject {
  /// Emits a boolean that determines if comments are currently loading.
  var onRefreshing: ((Bool) -> Void)? { get set }

  /// Emits a boolean that determines if cell separator is to be hidden.
  var onSeparatorHidden: ((Bool) -> Void)? { get set }

  /// Emits data to configure comment composer view.
  var onConfigureComposer: ((CommentComposerViewData) -> Void)? { get set }

  /// Configures the footer view with the current state.
  var onFooterState: ((CommentTableViewFooterViewState) -> Void)? { get set }

  /// Emits the selected `Comment`, `Project`, `Update?` and a `Bool` to determine if keyboard should show when user to navigate to replies.
  var onShowReplies: ((Comment, Project, Update?, Bool) -> Void)? { get set }

  /// Emits a list of `Comments`, the `Project` to load into the data source and whether an error state should be displayed.
  var onLoadComments: (([Comment], Project, Bool) -> Void)? { get set }

  /// Emits a HelpType to use when presenting a HelpWebViewController.
  var onShowHelp: ((HelpType) -> Void)? { get set }

  /// Emits when a comment has been posted and we should scroll to top and reset the composer.
  var onResetComposerAndScrollToTop: (() -> Void)? { get set }

  /// Emits when a block user request is successful.
  var onDidBlockUser: (() -> Void)? { get set }

  /// Emits when a block user request fails.
  var onDidBlockUserError: (() -> Void)? { get set }
}

@MainActor
public protocol CommentsViewModelType {
  var inputs: CommentsViewModelInputs { get }
  var outputs: CommentsViewModelOutputs { get }
}

@MainActor
public final class CommentsViewModel: CommentsViewModelType,
  CommentsViewModelInputs,
  CommentsViewModelOutputs {
  // MARK: Initializers

  private let feature: DiscussionFeature
  private var pageObservation: MainActorObservation?
  private let route = UUID()
  private(set) var loadingTask: Task<Void, Never>?
  private(set) var contextTask: Task<Void, Never>?
  private var contextRevision = 0
  private var configuration: (project: Project?, update: Update?)?
  private var loaded = false
  private var currentSource: DiscussionFeature.Source?
  private var lastCloseToBottom: Bool?
  private var hasReachedBottom = false
  private var loading = false
  private var footerState: CommentTableViewFooterViewState?
  private var retryTasks: [String: Task<Void, Never>] = [:]
  private var postTasks: [UUID: Task<Void, Never>] = [:]
  private var latestPostingProject: Project?
  private var postingUser: User?
  private var latestCommentableID: String?
  private var accumulatedComments: [Comment] = []
  private var lastPage: [Comment]?
  private var hasReceivedComments = false
  private var hasRequestedPage = false
  private var clearingForRefresh = false
  private var latestNavigationUpdate: Update?
  private var hasNavigationConfiguration = false
  private var lastViewedReplyComment: Comment?
  private var lastReplyComment: Comment?

  public init(feature: DiscussionFeature? = nil) {
    let feature = feature ?? AppModel.shared.discussionFeature
    self.feature = feature
    let route = self.route
    self.blockAnalytics.onInitiate = { project, blockedUserId in
      AppEnvironment.current.ksrAnalytics.trackBlockedUser(
        project, page: .project, sectionContext: .comments,
        typeContext: .initiate, targetUserId: "\(blockedUserId)"
      )
    }
    self.pageObservation = feature.observePages { [weak self] update in
      guard let self else { return }
      switch update {
      case let .page(route, comments, _):
        guard route == self.route, self.lastPage != comments else { return }
        self.lastPage = comments
        if self.clearingForRefresh && comments.isEmpty { return }
        self.clearingForRefresh = false
        self.hasReceivedComments = true
        self.accumulatedComments += comments
        self.publishCommentsIfAvailable()
      case let .loading(route, loading):
        guard route == self.route else { return }
        self.loading = loading
        if loading && self.hasReachedBottom { self.publishFooter(.activity) }
        self.onRefreshing?(loading)
      case let .error(route, _):
        guard route == self.route else { return }
        self.publishFooter(self.hasRequestedPage ? .error : .hidden)
        if !self.hasRequestedPage, let project = self.latestPostingProject {
          self.onLoadComments?([], project, true)
          self.publishFooter(.hidden)
        }
      }
    }
  }

  private var currentComments: [Comment]?

  private func applyComment(_ comment: Comment, replacing id: String) {
    guard let currentComments = self.currentComments else { return }
    let comments = commentsReplacingCommentById(currentComments, replacingComment: comment, withId: id)
    self.accumulatedComments = comments
    self.currentComments = comments
    self.publishCommentsIfAvailable()
  }

  private func publishCommentsIfAvailable() {
    guard self.hasReceivedComments, let project = self.latestPostingProject else { return }
    self.currentComments = self.accumulatedComments
    self.onSeparatorHidden?(self.accumulatedComments.isEmpty)
    self.onLoadComments?(self.accumulatedComments, project, false)
    self.publishFooter(.hidden)
  }

  private let blockPresentation = DiscussionBlockPresentation()
  private let blockAnalytics = BlockUserAnalyticsContext()
  public func blockUser(id: String) {
    self.blockAnalytics.receive(userID: "\(id)")
    self.blockPresentation.start(feature: self.feature, id: id) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success:
        NotificationCenter.default.post(.init(name: .ksr_blockedUser))
        self.onDidBlockUser?()
        if let (project, blockedUserId) = self.blockAnalytics.latest {
          AppEnvironment.current.ksrAnalytics.trackBlockedUser(
            project,
            page: .project,
            sectionContext: .comments,
            typeContext: .confirm,
            targetUserId: blockedUserId
          )
        }
      case .failure:
        self.onDidBlockUserError?()
      }
    }
  }

  public func commentCellDidTapViewReplies(_ comment: Comment) {
    guard let count = comment.replyCount, count > 0 else { return }
    self.lastViewedReplyComment = comment
    self.publishNavigation(comment, firstResponder: false)
  }

  public func didSelectComment(_ comment: Comment) {
    guard comment.status == .failed, self.retryTasks[comment.id] == nil,
          let commentableID = self.latestCommentableID else { return }
    let task = self.feature.beginRetry(comment: comment, commentableID: commentableID, parentID: nil) { [weak self] replacement, id in
      self?.applyComment(replacement, replacing: id)
    }
    self.retryTasks[comment.id] = task
    Task { [weak self] in
      await task.value
      self?.retryTasks[comment.id] = nil
    }
  }

  public func commentComposerDidSubmitText(_ text: String) {
    self.onResetComposerAndScrollToTop?()
    guard let project = self.latestPostingProject, let commentableID = self.latestCommentableID,
          let user = self.postingUser else { return }
    let id = UUID()
    let task = self.feature.beginPresentedPost(project: project, commentableID: commentableID, parentID: nil, user: user, body: text) { [weak self] comment, replacementID in
      self?.applyComment(comment, replacing: replacementID)
    }
    self.postTasks[id] = task
    Task { [weak self] in
      await task.value
      self?.postTasks[id] = nil
    }
  }

  public func commentRemovedCellDidTapURL(_ url: URL) {
    if let type = HelpType.helpType(from: url) { self.onShowHelp?(type) }
  }

  public func commentCellDidTapReply(comment: Comment) {
    self.lastReplyComment = comment
    self.publishNavigation(comment, firstResponder: true)
  }

  private func publishNavigation(_ comment: Comment, firstResponder: Bool) {
    guard self.hasNavigationConfiguration, let project = self.latestPostingProject else { return }
    self.onShowReplies?(comment, project, self.latestNavigationUpdate, firstResponder)
  }

  private func publishPendingNavigation() {
    if let comment = self.lastViewedReplyComment { self.publishNavigation(comment, firstResponder: false) }
    if let comment = self.lastReplyComment { self.publishNavigation(comment, firstResponder: true) }
  }

  public func commentTableViewFooterViewDidTapRetry() {
    if self.hasReachedBottom { self.requestNextPage() }
    else { self.requestFirstPage() }
  }

  public func configureWith(project: Project?, update: Update?) {
    self.configuration = (project, update)
    if self.loaded { self.applyConfiguration() }
    self.latestNavigationUpdate = update
    self.hasNavigationConfiguration = true
    self.publishPendingNavigation()
  }

  public func refresh() {
    self.clearingForRefresh = true
    self.accumulatedComments = []
    if self.currentComments != nil {
      self.currentComments = []
      self.onSeparatorHidden?(true)
    }
    guard let source = self.currentSource else { return }
    self.hasRequestedPage = false
    let feature = self.feature
    let route = self.route
    self.loadingTask = Task {
      await Task.yield()
      await feature.requestFirstPage(route: route, source: source, refresh: true).value
    }
  }

  public func viewDidLoad() {
    self.loaded = true
    self.postingUser = AppEnvironment.current.currentUser
    if let project = self.latestPostingProject { self.publishComposer(for: project) }
    self.applyConfiguration()
  }

  private func applyConfiguration() {
    guard let configuration = self.configuration else { return }
    self.contextRevision += 1
    let revision = self.contextRevision
    if let project = configuration.project {
      self.currentSource = .project(project.slug)
      self.latestCommentableID = project.graphID
      self.feature.cancelProject(route: self.route)
      self.receiveProject(project)
    } else if let update = configuration.update {
      self.currentSource = .update(String(update.id))
      self.latestCommentableID = encodeToBase64("FreeformPost-\(update.id)")
      let request = self.feature.requestProject(route: self.route, param: .id(update.projectId))
      self.contextTask = Task { [weak self] in
        guard let project = await request.value, !Task.isCancelled,
              let self, self.contextRevision == revision else { return }
        self.receiveProject(project)
      }
    } else {
      return
    }
    self.publishFooter(.hidden)
    self.requestFirstPage()
  }

  private func receiveProject(_ project: Project) {
    self.blockAnalytics.receive(project: project)
    self.latestPostingProject = project
    self.publishCommentsIfAvailable()
    self.publishComposer(for: project)
    self.publishPendingNavigation()
  }

  private func requestFirstPage() {
    guard let source = self.currentSource else { return }
    self.hasRequestedPage = false
    self.loadingTask = self.feature.requestFirstPage(route: self.route, source: source, refresh: true)
  }

  private func requestNextPage() {
    self.hasRequestedPage = true
    self.loadingTask = self.feature.requestNextPage(route: self.route)
  }

  private func publishFooter(_ state: CommentTableViewFooterViewState) {
    guard self.footerState != state else { return }
    self.footerState = state
    self.onFooterState?(state)
  }

  private func publishComposer(for project: Project) {
    guard let user = self.postingUser else {
      self.onConfigureComposer?((nil, false, true, false))
      return
    }
    let canPost = userIsBackingProject(project) || !project.memberData.permissions.isEmpty
    self.onConfigureComposer?((URL(string: user.avatar.medium), canPost, false, false))
  }

  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    let close = totalRows > 1 && row >= totalRows - 3
    guard self.lastCloseToBottom != close else { return }
    self.lastCloseToBottom = close
    guard close else { return }
    self.hasReachedBottom = true
    if self.loading { self.publishFooter(.activity) }
    self.requestNextPage()
  }

  public var onRefreshing: ((Bool) -> Void)?
  public var onSeparatorHidden: ((Bool) -> Void)?
  public var onConfigureComposer: ((CommentComposerViewData) -> Void)?
  public var onFooterState: ((CommentTableViewFooterViewState) -> Void)?
  public var onShowReplies: ((Comment, Project, Update?, Bool) -> Void)?
  public var onLoadComments: (([Comment], Project, Bool) -> Void)?
  public var onShowHelp: ((HelpType) -> Void)?
  public var onResetComposerAndScrollToTop: (() -> Void)?
  public var onDidBlockUser: (() -> Void)?
  public var onDidBlockUserError: (() -> Void)?

  deinit {
    self.loadingTask?.cancel()
    self.contextTask?.cancel()
    self.retryTasks.values.forEach { $0.cancel() }
    self.postTasks.values.forEach { $0.cancel() }

    let feature = self.feature
    let route = self.route
    Task { @MainActor in
      feature.release(route: route)
    }
  }

  func waitForLoads() async {
    await self.contextTask?.value
    await self.loadingTask?.value
    await self.feature.waitForMutations()
    for task in self.retryTasks.values { await task.value }
    for task in self.postTasks.values { await task.value }
    await self.blockPresentation.wait()
  }

  public var inputs: CommentsViewModelInputs { return self }
  public var outputs: CommentsViewModelOutputs { return self }
}

private func commentsReplacingCommentById(
  _ comments: [Comment],
  replacingComment: Comment,
  withId id: String
) -> [Comment] {
  // TODO: We may need to introduce optimizations here if this becomes problematic for projects that have
  /// thousands of comments. Consider an accompanying `Set` to track membership or replacing entirely
  /// with an `OrderedSet`.
  guard let commentIndex = comments.firstIndex(where: { $0.id == id }) else {
    // If the comment we're replacing is not found, it's new, prepend it.
    return [replacingComment] + comments
  }

  var mutableComments = comments
  mutableComments[commentIndex] = replacingComment

  return mutableComments
}

/// Owns one screen's wait while the Feature retains the admitted block write.
@MainActor
internal final class DiscussionBlockPresentation {
  private var task: Task<Void, Never>?
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  init(sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) { self.sleep = sleep }
  func start(feature: DiscussionFeature, id: String, deliver: @escaping (Result<EmptyResponseEnvelope, ErrorEnvelope>) -> Void) {
    self.task?.cancel()
    let userID = feature.sessionFeature.currentUser?.id
    let generation = feature.sessionFeature.generation
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let request = feature.requestBlockUser(id: id)
    let sleep = self.sleep
    self.task = Task { @MainActor in
      let result = await request.result
      do {
        try Task.checkCancellation()
        try await sleep(delay)
        try Task.checkCancellation()
        guard feature.sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        switch result {
        case let .success(value): deliver(.success(value))
        case let .failure(error):
          guard !(error is CancellationError) else { return }
          deliver(.failure((error as? ErrorEnvelope) ?? .couldNotParseJSON))
        }
      } catch { /* A replaced or released screen must not receive a late result. */ }
    }
  }
  func wait() async { await self.task?.value }
  deinit { self.task?.cancel() }
}

@MainActor
internal final class BlockUserAnalyticsContext {
  var onInitiate: ((Project, String) -> Void)?
  private var project: Project?
  private var userID: String?
  var latest: (Project, String)? {
    guard let project, let userID else { return nil }
    return (project, userID)
  }

  func receive(project: Project) {
    self.project = project
    self.trackInitiation()
  }

  func receive(userID: String) {
    self.userID = userID
    self.trackInitiation()
  }

  private func trackInitiation() {
    guard let (project, userID) = self.latest else { return }
    self.onInitiate?(project, userID)
  }
}
