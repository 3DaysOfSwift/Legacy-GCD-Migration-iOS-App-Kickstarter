import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

@MainActor
public protocol CommentRepliesViewModelInputs {
  /// Call when block user is tapped
  func blockUser(id: String)

  /**
    Call with the comment and project that we are viewing replies for. `Comment` can be provided to minimize
    the number of API requests made (ie. no need to find the comment id), but this is for viewing the replies for the root comment.

     - parameter comment: The `Comment` we are viewing the replies.
     - parameter project: The `Project` the comment replies are for.
     - parameter update: The `Update?` the comment replies are for.
     - parameter inputAreaBecomeFirstResponder: A Bool that determines if the composer should become first responder.
     - parameter replyId: A `String?` that determines which cell to scroll to, if visible on the first page.
   **/
  func configureWith(
    comment: Comment,
    project: Project,
    update: Update?,
    inputAreaBecomeFirstResponder: Bool,
    replyId: String?
  )

  /// Call when the User is posting a comment or reply.
  func commentComposerDidSubmitText(_ text: String)

  /// Call with a `Comment` when it is selected.
  func didSelectComment(_ comment: Comment)

  /// Call in `didSelectRow` when either a `ViewMoreRepliesCell` or `CommentViewMoreRepliesFailedCell` is tapped.
  func paginateOrErrorCellWasTapped()

  /// Call after the data source is loaded and the tableView reloads.
  func dataSourceLoaded()

  /// Call when there is a failure in requesting the first page of the data and the `CommentViewMoreRepliesFailedCell` is tapped.
  func retryFirstPage()

  /// Call when the view appears.
  func viewDidAppear()

  /// Call when the view loads.
  func viewDidLoad()
}

@MainActor
public protocol CommentRepliesViewModelOutputs: AnyObject {
  /// Emits data to configure comment composer view.
  var onConfigureComposer: ((CommentComposerViewData) -> Void)? { get set }

  /// Emits a root `Comment`s  to load into the data source.
  var onLoadRootComment: ((Comment) -> Void)? { get set }

  /// Emits a tuple of (`Comment`,`Int`) and a `Project` to load into the data source
  var onLoadReplies: ((([Comment], Int), Project) -> Void)? { get set }

  /// Emits a `Comment`, `String` and `Project` to replace an optimistically posted comment after a network request completes.
  var onLoadFailableReply: ((Comment, String, Project) -> Void)? { get set }

  /// Emits when a comment has been posted reset the composer.
  var onResetCommentComposer: (() -> Void)? { get set }

  /// Emits when a replyId is supplied to the view controller configuration and we want to scroll to a specific index.
  var onScrollToReply: ((String) -> Void)? { get set }

  /// Emits when a pagination error has occurred.
  var onPaginationError: (() -> Void)? { get set }

  /// Emits when a block user request is successful.
  var onDidBlockUser: (() -> Void)? { get set }

  /// Emits when a block user request fails.
  var onDidBlockUserError: (() -> Void)? { get set }
}

@MainActor
public protocol CommentRepliesViewModelType {
  var inputs: CommentRepliesViewModelInputs { get }
  var outputs: CommentRepliesViewModelOutputs { get }
}

@MainActor
public final class CommentRepliesViewModel: CommentRepliesViewModelType,
  CommentRepliesViewModelInputs,
  CommentRepliesViewModelOutputs {
  private let feature: DiscussionFeature
  private var latestRootComment: Comment?
  private var latestProject: Project?
  private var composerUser: User?
  private var composerFirstResponder = false
  private var requestedFirstResponder = false
  private var composerLoaded = false
  private var latestReplies: ([Comment], Int)?
  private var latestFailableReply: (Comment, String)?
  private var retryTasks: [String: Task<Void, Never>] = [:]
  private var postTasks: [UUID: Task<Void, Never>] = [:]
  private var pageObservation: MainActorObservation?
  private let route = UUID()
  private let disposables = ScopedDisposable(CompositeDisposable())
  private(set) var loadingTask: Task<Void, Never>?
  private(set) var contextTask: Task<Void, Never>?

  public init(feature: DiscussionFeature? = nil) {
    let feature = feature ?? AppModel.shared.discussionFeature
    self.feature = feature
    let route = self.route
    let rootCommentProject = Signal.combineLatest(
      self.commentProjectProperty.signal.skipNil(),
      self.viewDidLoadProperty.signal
    )
    .map(first)

    let rootComment = rootCommentProject.map(first)

    let project = rootCommentProject.map(second)


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
    _ = project.observeValues { project in
      blockAnalytics.receive(project: project)
    }


    self.disposables += project.observeValues { [weak self] project in
      guard let self else { return }
      self.latestProject = project
      self.updateComposer()
      if let replies = self.latestReplies { self.onLoadReplies?(replies, project) }
      if let (comment, id) = self.latestFailableReply { self.onLoadFailableReply?(comment, id, project) }
    }
    self.disposables += rootComment.observeValues { [weak self] comment in
      guard let self else { return }
      self.latestRootComment = comment
      self.onLoadRootComment?(comment)
      self.loadingTask = feature.requestFirstPage(route: route, source: .replies(comment.id), refresh: true)
    }
    self.pageObservation = feature.observePages { [weak self] update in
      guard let self else { return }
      switch update {
      case let .page(eventRoute, comments, count):
        guard eventRoute == route, self.latestReplies?.0 != comments else { return }
        self.latestReplies = (comments, count)
        if let project = self.latestProject { self.onLoadReplies?((comments, count), project) }
      case .loading: break
      case let .error(eventRoute, _):
        if eventRoute == route { self.onPaginationError?() }
      }
    }
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

  public func didSelectComment(_ comment: Comment) {
    guard comment.status == .failed, self.retryTasks[comment.id] == nil,
          let project = self.latestProject, self.latestRootComment != nil else { return }
    let commentableID = self.updateProperty.value.map { encodeToBase64("FreeformPost-\($0.id)") } ?? project.graphID
    let task = self.feature.beginRetry(comment: comment, commentableID: commentableID, parentID: comment.parentId) { [weak self] replacement, id in
      guard let self else { return }
      self.latestFailableReply = (replacement, id)
      if let project = self.latestProject { self.onLoadFailableReply?(replacement, id, project) }
    }
    self.retryTasks[comment.id] = task
    Task { [weak self] in
      await task.value
      self?.retryTasks[comment.id] = nil
    }
  }

  public func commentComposerDidSubmitText(_ text: String) {
    self.onResetCommentComposer?()
    guard let project = self.latestProject, let root = self.latestRootComment,
          let user = self.composerUser else { return }
    let commentableID = self.updateProperty.value.map { encodeToBase64("FreeformPost-\($0.id)") } ?? project.graphID
    let id = UUID()
    let task = self.feature.beginPresentedPost(project: project, commentableID: commentableID, parentID: root.id, user: user, body: text) { [weak self] comment, replacementID in
      guard let self else { return }
      self.latestFailableReply = (comment, replacementID)
      if let project = self.latestProject { self.onLoadFailableReply?(comment, replacementID, project) }
    }
    self.postTasks[id] = task
    Task { [weak self] in
      await task.value
      self?.postTasks[id] = nil
    }
  }

  fileprivate let commentProjectProperty = MutableProperty<(Comment, Project, Bool)?>(nil)
  fileprivate let updateProperty = MutableProperty<Update?>(nil)
  private var replyID: String?
  public func configureWith(
    comment: Comment,
    project: Project,
    update: Update?,
    inputAreaBecomeFirstResponder: Bool,
    replyId: String?
  ) {
    self.requestedFirstResponder = inputAreaBecomeFirstResponder
    self.commentProjectProperty.value = (comment, project, inputAreaBecomeFirstResponder)
    self.updateProperty.value = update
    if let replyId { self.replyID = replyId }
  }

  public func paginateOrErrorCellWasTapped() {
    self.loadingTask = self.feature.requestNextPage(route: self.route)
  }

  public func retryFirstPage() {
    guard let comment = self.latestRootComment else { return }
    self.loadingTask = self.feature.requestFirstPage(route: self.route, source: .replies(comment.id), refresh: true)
  }

  public func dataSourceLoaded() {
    if let replyID = self.replyID { self.onScrollToReply?(replyID) }
  }

  public func viewDidAppear() {
    guard self.composerLoaded, self.latestProject != nil,
          self.composerFirstResponder != self.requestedFirstResponder else { return }
    self.composerFirstResponder = self.requestedFirstResponder
    self.updateComposer()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.composerLoaded = true
    self.composerUser = AppEnvironment.current.currentUser
    self.composerFirstResponder = false
    self.viewDidLoadProperty.value = ()
  }

  private func updateComposer() {
    guard self.composerLoaded, let project = self.latestProject else { return }
    guard let user = self.composerUser else {
      self.onConfigureComposer?((nil, false, true, false))
      return
    }
    let isBacker = userIsBackingProject(project)
    let canPost = isBacker || !project.memberData.permissions.isEmpty
    self.onConfigureComposer?((URL(string: user.avatar.medium), canPost, false, self.composerFirstResponder))
  }

  public var onConfigureComposer: ((CommentComposerViewData) -> Void)?
  public var onLoadRootComment: ((Comment) -> Void)?
  public var onLoadReplies: ((([Comment], Int), Project) -> Void)?
  public var onLoadFailableReply: ((Comment, String, Project) -> Void)?
  public var onResetCommentComposer: (() -> Void)?
  public var onScrollToReply: ((String) -> Void)?
  public var onPaginationError: (() -> Void)?
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

  public var inputs: CommentRepliesViewModelInputs { return self }
  public var outputs: CommentRepliesViewModelOutputs { return self }
}
