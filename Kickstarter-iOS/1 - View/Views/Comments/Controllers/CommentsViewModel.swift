import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

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
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let errorPipe = Signal<(UUID, ErrorEnvelope), Never>.pipe()
  private let displayPipe = Signal<Void, Never>.pipe()
  private var pageObservation: MainActorObservation?
  private let route = UUID()
  private let disposables = ScopedDisposable(CompositeDisposable())
  private(set) var loadingTask: Task<Void, Never>?
  private(set) var contextTask: Task<Void, Never>?
  private var contextRevision = 0
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
    let projectOrUpdate = Signal.combineLatest(
      self.projectAndUpdateProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal
    )
    .map(first)
    .flatMap { project, update in
      SignalProducer(value: project.map(Either.left) ?? update.map(Either.right))
        .skipNil()
    }

    let resolvedProject = Signal<Project, Never>.pipe()
    let initialProject = Signal.merge(
      projectOrUpdate.compactMap { value -> Project? in
        value.ifLeft({ $0 }, ifRight: { _ in nil })
      },
      resolvedProject.output
    )

    let isCloseToBottom = self.willDisplayRowProperty.signal.skipNil()
      .map { row, total -> Bool in
        // TODO: ensure this does not page when cells are less than threshold.
        // Prevent paging when only the empty state cell is shown.
        guard total > 1 else { return false }
        return row >= total - 3
      }
      .skipRepeats()
      .filter(isTrue)
      .ignoreValues()

    let tappedToRetry = self.commentTableViewFooterViewDidTapRetryProperty.signal
    // Retry the next page if we've paged before at least once and tapped to retry.
    let retryNextPage = Signal.combineLatest(
      isCloseToBottom.take(first: 1),
      tappedToRetry
    )

    // Don't retry the first page if we've paged before.
    let retryFirstPage = tappedToRetry
      .take(until: isCloseToBottom)

    let requestNextPage = Signal.merge(
      isCloseToBottom.ignoreValues(),
      retryNextPage.ignoreValues()
    )

    let pullToRefresh = self.refreshProperty.signal

    let requestFirstPageWith = Signal.merge(
      projectOrUpdate,
      projectOrUpdate.takeWhen(retryFirstPage),
      projectOrUpdate.takeWhen(pullToRefresh)
        // Thread hop so that we can clear our comments buffer before newly paginated results.
        .ksr_debounce(.nanoseconds(0), on: AppEnvironment.current.scheduler)
    )
    let hasRequestedNextPage = Signal.merge(
      requestFirstPageWith.mapConst(false),
      requestNextPage.mapConst(true)
    )
    let isLoading = self.loadingPipe.output.filter { $0.0 == route }.map { $0.1 }
    let errors = self.errorPipe.output.filter { $0.0 == route }.map { $0.1 }

    // get an id needed to post a comment to either a project or a project update
    let commentableId = projectOrUpdate
      .flatMap { projectOrUpdate in
        projectOrUpdate.ifLeft { project in
          SignalProducer.init(value: project.graphID)
        } ifRight: { update in
          SignalProducer.init(value: encodeToBase64("FreeformPost-\(update.id)"))
        }
      }

    let footerViewActivityState = Signal
      .combineLatest(isCloseToBottom, isLoading)
      .filter(second >>> isTrue)

    let initialLoadOrReload = Signal.merge(
      projectOrUpdate.ignoreValues(),
      self.displayPipe.output
    )

    // Footer view would be hidden if there is an error at
    // initial loading stage or when comments are refreshed
    let hideFooterView: Signal<CommentTableViewFooterViewState, Never> = Signal.merge(
      initialLoadOrReload.mapConst(.hidden),
      errors
        .mapConst(.hidden)
        .withLatestFrom(hasRequestedNextPage)
        .filter(second >>> isFalse)
        .map(first)
    )

    let footerState = Signal.merge(
      hideFooterView,
      footerViewActivityState.mapConst(.activity),
      // Footer view would be only be visible if there is an error for pagination responses.
      errors
        .mapConst(.error)
        .withLatestFrom(hasRequestedNextPage)
        .filter(second >>> isTrue)
        .map(first)
    )
    .skipRepeats()


    // MARK: User Blocking Analytics

    let blockAnalytics = self.blockAnalytics
    blockAnalytics.onInitiate = { project, blockedUserId in
        AppEnvironment.current.ksrAnalytics
          .trackBlockedUser(
            project,
            page: .project,
            sectionContext: .comments,
            typeContext: .initiate,
            targetUserId: "\(blockedUserId)"
          )
    }
    _ = initialProject.observeValues { project in
      blockAnalytics.receive(project: project)
    }


    self.disposables += footerState.observeValues { [weak self] state in
      self?.onFooterState?(state)
    }
    self.disposables += initialProject.observeValues { [weak self] project in
      self?.latestPostingProject = project
      self?.publishCommentsIfAvailable()
      self?.publishComposer(for: project)
      self?.publishPendingNavigation()
    }
    self.disposables += commentableId.observeValues { [weak self] id in
      self?.latestCommentableID = id
    }

    self.disposables += projectOrUpdate.observeValues { [weak self] value in
      guard let self else { return }
      self.contextRevision += 1
      let revision = self.contextRevision
      value.ifLeft({ _ in feature.cancelProject(route: route) }, ifRight: { update in
        let request = feature.requestProject(route: route, param: .id(update.projectId))
        self.contextTask = Task { [weak self] in
          guard let project = await request.value, !Task.isCancelled,
                self?.contextRevision == revision else { return }
          resolvedProject.input.send(value: project)
        }
      })
    }
    self.disposables += requestFirstPageWith.observeValues { [weak self] value in
      self?.hasRequestedPage = false
      let source = value.ifLeft(
        { DiscussionFeature.Source.project($0.slug) },
        ifRight: { .update(String($0.id)) }
      )
      self?.loadingTask = feature.requestFirstPage(route: route, source: source, refresh: true)
    }
    self.disposables += requestNextPage.observeValues { [weak self] in
      self?.hasRequestedPage = true
      self?.loadingTask = feature.requestNextPage(route: route)
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
        self.loadingPipe.input.send(value: (route, loading))
        if route == self.route { self.onRefreshing?(loading) }
      case let .error(route, error):
        self.errorPipe.input.send(value: (route, error))
        if route == self.route, !self.hasRequestedPage, let project = self.latestPostingProject {
          self.onLoadComments?([], project, true)
          self.displayPipe.input.send(value: ())
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
    self.displayPipe.input.send(value: ())
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

  private let commentTableViewFooterViewDidTapRetryProperty = MutableProperty(())
  public func commentTableViewFooterViewDidTapRetry() {
    self.commentTableViewFooterViewDidTapRetryProperty.value = ()
  }

  fileprivate let projectAndUpdateProperty = MutableProperty<(Project?, Update?)?>(nil)
  public func configureWith(project: Project?, update: Update?) {
    self.projectAndUpdateProperty.value = (project, update)
    self.latestNavigationUpdate = update
    self.hasNavigationConfiguration = true
    self.publishPendingNavigation()
  }

  fileprivate let refreshProperty = MutableProperty(())
  public func refresh() {
    self.clearingForRefresh = true
    self.accumulatedComments = []
    if self.currentComments != nil {
      self.currentComments = []
      self.onSeparatorHidden?(true)
    }
    self.refreshProperty.value = ()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.postingUser = AppEnvironment.current.currentUser
    if let project = self.latestPostingProject { self.publishComposer(for: project) }
    self.viewDidLoadProperty.value = ()
  }

  private func publishComposer(for project: Project) {
    guard let user = self.postingUser else {
      self.onConfigureComposer?((nil, false, true, false))
      return
    }
    let canPost = userIsBackingProject(project) || !project.memberData.permissions.isEmpty
    self.onConfigureComposer?((URL(string: user.avatar.medium), canPost, false, false))
  }

  fileprivate let willDisplayRowProperty = MutableProperty<(row: Int, total: Int)?>(nil)
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    self.willDisplayRowProperty.value = (row, totalRows)
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
