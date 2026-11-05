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
  var configureCommentComposerViewWithData: Signal<CommentComposerViewData, Never> { get }

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
  private var latestReplies: ([Comment], Int)?
  private var latestFailableReply: (Comment, String)?
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


    let currentUser = self.viewDidLoadProperty.signal
      .map { _ in AppEnvironment.current.currentUser }

    let inputAreaBecomeFirstResponder = Signal.merge(
      rootCommentProject
        .map(third)
        .takeWhen(self.viewDidAppearProperty.signal),
      self.viewDidLoadProperty.signal.mapConst(false)
    ).skipRepeats()

    self.configureCommentComposerViewWithData = Signal
      .combineLatest(
        project,
        currentUser.signal,
        self.viewDidLoadProperty.signal,
        inputAreaBecomeFirstResponder
      )
      .map { ($0.0, $0.1, $0.3) }
      .map { project, currentUser, inputAreaBecomeFirstResponder in
        let isBacker = userIsBackingProject(project)
        let isCreatorOrCollaborator = !project.memberData.permissions.isEmpty && !isBacker
        let canPostComment = isBacker || isCreatorOrCollaborator

        guard let user = currentUser else {
          return (
            avatarURL: nil,
            canPostComment: false,
            hidden: true,
            becomeFirstResponder: false
          )
        }

        let url = URL(string: user.avatar.medium)
        return (url, canPostComment, false, inputAreaBecomeFirstResponder)
      }

    let commentCellTapped = self.didSelectCommentProperty.signal.skipNil()
    let erroredCommentTapped = commentCellTapped.filter { comment in comment.status == .failed }



    let commentComposerDidSubmitText = self.commentComposerDidSubmitTextProperty.signal.skipNil()

    // If the Update is non-nil we send the FreeformPost format, otherwise we send the Project graphID
    let commentableId = self.updateProperty.signal.combineLatest(with: project)
      .map { update, project -> String in
        guard let update = update else {
          return project.graphID
        }
        return encodeToBase64("FreeformPost-\(update.id)")
      }

    let parentId = rootComment.flatMap { comment in
      SignalProducer.init(value: comment.id)
    }

    let failablePostReplyCommentConfigData:
      Signal<(project: Project, commentableId: String, parentId: String, user: User), Never> = Signal
      .combineLatest(
        project,
        commentableId,
        parentId,
        currentUser.skipNil()
      ).map { project, commentableId, parentId, user in
        (project, commentableId, parentId, user)
      }

    let failableCommentWithReplacementId = failablePostReplyCommentConfigData
      .takePairWhen(commentComposerDidSubmitText)
      .map { data in
        let ((project, commentableId, parentId, user), text) = data
        return (project, commentableId, parentId, user, text)
      }
      .flatMap(
        .concurrent(limit: DiscussionFeature.concurrentCommentLimit),
        feature.postCommentProducer
      )

    let currentlyRetrying = MutableProperty<Set<String>>([])

    let newErroredCommentTapped = erroredCommentTapped
      // Check that we are not currently retrying this comment.
      .filter { [currentlyRetrying] comment in !currentlyRetrying.value.contains(comment.id) }
      // If we pass the filter add it to our set of retrying comments.
      .on(value: { [currentlyRetrying] comment in
        currentlyRetrying.value.insert(comment.id)
      })

    let retryingComment = commentableId
      .takePairWhen(newErroredCommentTapped)
      .map { commentableId, comment in
        (comment, commentableId, comment.parentId)
      }
      .flatMap(
        .concurrent(limit: DiscussionFeature.concurrentCommentLimit),
        feature.retryCommentProducer
      )
      // Once we've emitted a value here the comment has been retried and can be removed.
      .on(value: { [currentlyRetrying] comment, id in
        if comment.status == .success || comment.status == .failed {
          currentlyRetrying.value.remove(id)
        }
      })

    let failableOrRetriedComment = Signal.merge(retryingComment, failableCommentWithReplacementId)



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
      if let replies = self.latestReplies { self.onLoadReplies?(replies, project) }
      if let (comment, id) = self.latestFailableReply { self.onLoadFailableReply?(comment, id, project) }
    }
    self.disposables += failableOrRetriedComment.observeValues { [weak self] comment, id in
      guard let self else { return }
      self.latestFailableReply = (comment, id)
      if let project = self.latestProject { self.onLoadFailableReply?(comment, id, project) }
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

  private let didSelectCommentProperty = MutableProperty<Comment?>(nil)
  public func didSelectComment(_ comment: Comment) {
    self.didSelectCommentProperty.value = comment
  }

  fileprivate let commentComposerDidSubmitTextProperty = MutableProperty<String?>(nil)
  public func commentComposerDidSubmitText(_ text: String) {
    self.onResetCommentComposer?()
    self.commentComposerDidSubmitTextProperty.value = text
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

  fileprivate let viewDidAppearProperty = MutableProperty(())
  public func viewDidAppear() {
    self.viewDidAppearProperty.value = ()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  public let configureCommentComposerViewWithData: Signal<CommentComposerViewData, Never>
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
    await self.blockPresentation.wait()
  }

  public var inputs: CommentRepliesViewModelInputs { return self }
  public var outputs: CommentRepliesViewModelOutputs { return self }
}
