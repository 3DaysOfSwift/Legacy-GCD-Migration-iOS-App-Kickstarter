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
  var beginOrEndRefreshing: Signal<Bool, Never> { get }

  /// Emits a boolean that determines if cell separator is to be hidden.
  var cellSeparatorHidden: Signal<Bool, Never> { get }

  /// Emits data to configure comment composer view.
  var configureCommentComposerViewWithData: Signal<CommentComposerViewData, Never> { get }

  /// Configures the footer view with the current state.
  var configureFooterViewWithState: Signal<CommentTableViewFooterViewState, Never> { get }

  /// Emits the selected `Comment`, `Project`, `Update?` and a `Bool` to determine if keyboard should show when user to navigate to replies.
  var goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder: Signal<
    (Comment, Project, Update?, Bool),
    Never
  > { get }

  /// Emits a list of `Comments`, the `Project` to load into the data source and whether an error state should be displayed.
  var loadCommentsAndProjectIntoDataSource: Signal<([Comment], Project, Bool), Never> { get }

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
  private let pagePipe = Signal<(UUID, [Comment], Int), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  private let errorPipe = Signal<(UUID, ErrorEnvelope), Never>.pipe()
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

    let currentUser = self.viewDidLoadProperty.signal
      .map { _ in AppEnvironment.current.currentUser }

    let resolvedProject = Signal<Project, Never>.pipe()
    let initialProject = Signal.merge(
      projectOrUpdate.compactMap { value -> Project? in
        value.ifLeft({ $0 }, ifRight: { _ in nil })
      },
      resolvedProject.output
    )

    self.configureCommentComposerViewWithData = Signal
      .combineLatest(initialProject, currentUser.signal, self.viewDidLoadProperty.signal.ignoreValues())
      .map { ($0.0, $0.1) }
      .map { project, currentUser in
        let isBacker = userIsBackingProject(project)
        let isCreatorOrCollaborator = !project.memberData.permissions.isEmpty && !isBacker
        let canPostComment = isBacker || isCreatorOrCollaborator

        guard let user = currentUser else {
          return (nil, false, true, false)
        }

        let url = URL(string: user.avatar.medium)
        return (url, canPostComment, false, false)
      }

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

    let currentComments = self.currentComments.signal.skipNil()

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
    let comments = self.pagePipe.output.filter { $0.0 == route }.map { $0.1 }.skipRepeats()
    let isLoading = self.loadingPipe.output.filter { $0.0 == route }.map { $0.1 }
    let errors = self.errorPipe.output.filter { $0.0 == route }.map { $0.1 }

    let commentsWithRetryingComment = currentComments
      .takePairWhen(self.retryingComment.signal.skipNil())
      .map(unpack)
      .map(commentsReplacingCommentById)

    let commentsWithFailableOrComment = currentComments
      .takePairWhen(self.failableOrComment.signal.skipNil())
      .map(unpack)
      .map(commentsReplacingCommentById)

    let paginatedComments = Signal.merge(
      // Pull to refresh, clear comments cache.
      pullToRefresh.mapConst(([], true)),
      // Regular paged comments, don't clear accumulator.
      comments.map { comments in (comments, false) },
      // Comments with a retrying comment, replace our current comments cache with this.
      commentsWithRetryingComment.map { comments in (comments, true) },
      // Comments with a failable or new comment, replace our current comments cache with this.
      commentsWithFailableOrComment.map { comments in (comments, true) }
    )
    .scan([]) { accum, value -> [Comment] in
      let (comments, clear) = value
      guard clear == false else { return comments }
      return accum + comments
    }

    let commentsAndProject = Signal.combineLatest(
      paginatedComments,
      initialProject
    )

    self.currentComments <~ commentsAndProject.map(first)
      // Thread hop so that we don't circularly buffer.
      .ksr_debounce(.nanoseconds(0), on: AppEnvironment.current.scheduler)

    // Allow empty arrays from the first emission.
    let emptyCommentsWithInitialProject = Signal.zip(comments, initialProject)
      .filter { comments, _ in comments.isEmpty }
      .map { comments, project in (comments, project, false) }

    // Continue to paginate normally without empty comments.
    let paginatedCommentsAndProject = commentsAndProject
      .filter { comments, _ in comments.isEmpty == false }
      .map { comments, project in (comments, project, false) }

    // If there are errors emit empty comments array, project and error boolean.
    let errorsAndHasRequestedNextPage: Signal<([Comment], Project, Bool), Never> = Signal
      .combineLatest(errors, hasRequestedNextPage)
      .filter(second >>> isFalse)
      .map(first)
      .withLatestFrom(initialProject).map { ([], $1, true) }

    self.loadCommentsAndProjectIntoDataSource = Signal.merge(
      emptyCommentsWithInitialProject,
      paginatedCommentsAndProject,
      errorsAndHasRequestedNextPage
    )

    self.beginOrEndRefreshing = isLoading
    self.cellSeparatorHidden = commentsAndProject.map(first).map { $0.count == .zero }

    let viewCommentReplies = self.commentCellDidTapViewRepliesProperty.signal
      .skipNil()
      .filter { comment in
        guard let replyCount = comment.replyCount else {
          return false
        }
        return replyCount > 0
      }

    let update = self.projectAndUpdateProperty.signal
      .skipNil()
      .map(second)

    let commentsWithRepliesAndProject = Signal.combineLatest(
      viewCommentReplies, initialProject, update
    )

    let replyCommentWithProject = Signal.combineLatest(
      self.commentCellDidTapReplyProperty.signal.skipNil(),
      initialProject,
      update
    )

    self.goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder =
      Signal.merge(
        commentsWithRepliesAndProject.map { ($0, $1, $2, false) },
        replyCommentWithProject.map { ($0, $1, $2, true) }
      )

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
      self.loadCommentsAndProjectIntoDataSource.ignoreValues()
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

    self.configureFooterViewWithState = Signal.merge(
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


    self.disposables += initialProject.observeValues { [weak self] project in
      self?.latestPostingProject = project
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
      let source = value.ifLeft(
        { DiscussionFeature.Source.project($0.slug) },
        ifRight: { .update(String($0.id)) }
      )
      self?.loadingTask = feature.requestFirstPage(route: route, source: source, refresh: true)
    }
    self.disposables += requestNextPage.observeValues { [weak self] in
      self?.loadingTask = feature.requestNextPage(route: route)
    }
    self.pageObservation = feature.observePages { [weak self] update in
      guard let self else { return }
      switch update {
      case let .page(route, comments, count): self.pagePipe.input.send(value: (route, comments, count))
      case let .loading(route, loading): self.loadingPipe.input.send(value: (route, loading))
      case let .error(route, error): self.errorPipe.input.send(value: (route, error))
      }
    }
  }

  // Properties to assist with injecting these values into the existing data streams.
  private let currentComments = MutableProperty<[Comment]?>(nil)
  private let retryingComment = MutableProperty<(Comment, String)?>(nil)
  private let failableOrComment = MutableProperty<(Comment, String)?>(nil)

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

  private let commentCellDidTapViewRepliesProperty = MutableProperty<Comment?>(nil)
  public func commentCellDidTapViewReplies(_ comment: Comment) {
    self.commentCellDidTapViewRepliesProperty.value = comment
  }

  public func didSelectComment(_ comment: Comment) {
    guard comment.status == .failed, self.retryTasks[comment.id] == nil,
          let commentableID = self.latestCommentableID else { return }
    let task = self.feature.beginRetry(comment: comment, commentableID: commentableID, parentID: nil) { [weak self] replacement, id in
      self?.retryingComment.value = (replacement, id)
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
      self?.failableOrComment.value = (comment, replacementID)
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

  fileprivate let commentCellDidTapReplyProperty = MutableProperty<Comment?>(nil)
  public func commentCellDidTapReply(comment: Comment) {
    self.commentCellDidTapReplyProperty.value = comment
  }

  private let commentTableViewFooterViewDidTapRetryProperty = MutableProperty(())
  public func commentTableViewFooterViewDidTapRetry() {
    self.commentTableViewFooterViewDidTapRetryProperty.value = ()
  }

  fileprivate let projectAndUpdateProperty = MutableProperty<(Project?, Update?)?>(nil)
  public func configureWith(project: Project?, update: Update?) {
    self.projectAndUpdateProperty.value = (project, update)
  }

  fileprivate let refreshProperty = MutableProperty(())
  public func refresh() {
    self.refreshProperty.value = ()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.postingUser = AppEnvironment.current.currentUser
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let willDisplayRowProperty = MutableProperty<(row: Int, total: Int)?>(nil)
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    self.willDisplayRowProperty.value = (row, totalRows)
  }

  public let beginOrEndRefreshing: Signal<Bool, Never>
  public let cellSeparatorHidden: Signal<Bool, Never>
  public let configureCommentComposerViewWithData: Signal<CommentComposerViewData, Never>
  public let configureFooterViewWithState: Signal<CommentTableViewFooterViewState, Never>
  public let goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder: Signal<
    (Comment, Project, Update?, Bool),
    Never
  >
  public let loadCommentsAndProjectIntoDataSource: Signal<([Comment], Project, Bool), Never>
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
