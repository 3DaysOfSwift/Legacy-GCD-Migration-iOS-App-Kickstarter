@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class CommentsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = CommentsViewModel(feature: DiscussionFeature(makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }, sleep: { _ in try Task.checkCancellation() }))

  private let beginOrEndRefreshing = TestObserver<Bool, Never>()
  private let cellSeparatorHidden = TestObserver<Bool, Never>()
  private let commentComposerViewHidden = TestObserver<Bool, Never>()
  private let configureCommentComposerViewURL = TestObserver<URL?, Never>()
  private let configureCommentComposerViewCanPostComment = TestObserver<Bool, Never>()
  private let configureFooterViewWithState = TestObserver<CommentTableViewFooterViewState, Never>()
  private let didBlockUser = TestObserver<(), Never>()
  private let didBlockUserError = TestObserver<(), Never>()
  private let goToCommentRepliesComment = TestObserver<Comment, Never>()
  private let goToCommentRepliesProject = TestObserver<Project, Never>()
  private let goToCommentRepliesUpdate = TestObserver<Update?, Never>()
  private let goToCommentRepliesShowKeyboard = TestObserver<Bool, Never>()
  private let loadCommentsAndProjectIntoDataSourceComments = TestObserver<[Comment], Never>()
  private let loadCommentsAndProjectIntoDataSourceShouldShowErrorState = TestObserver<Bool, Never>()
  private let loadCommentsAndProjectIntoDataSourceProject = TestObserver<Project, Never>()
  private let showHelpWebViewController = TestObserver<HelpType, Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      self.vm.outputs.beginOrEndRefreshing.observe(self.beginOrEndRefreshing.observer)
      self.vm.outputs.cellSeparatorHidden.observe(self.cellSeparatorHidden.observer)
      self.vm.outputs.configureCommentComposerViewWithData.map(\.hidden)
        .observe(self.commentComposerViewHidden.observer)
      self.vm.outputs.configureCommentComposerViewWithData.map(\.avatarURL)
        .observe(self.configureCommentComposerViewURL.observer)
      self.vm.outputs.configureCommentComposerViewWithData.map(\.canPostComment)
        .observe(self.configureCommentComposerViewCanPostComment.observer)
      self.vm.outputs.didBlockUser.observe(self.didBlockUser.observer)
      self.vm.outputs.didBlockUserError.observe(self.didBlockUserError.observer)
      self.vm.outputs.configureFooterViewWithState.observe(self.configureFooterViewWithState.observer)
      self.vm.outputs.goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder.map { $0.0 }
        .observe(self.goToCommentRepliesComment.observer)
      self.vm.outputs.goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder.map { $0.1 }
        .observe(self.goToCommentRepliesProject.observer)
      self.vm.outputs.goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder.map { $0.2 }
        .observe(self.goToCommentRepliesUpdate.observer)
      self.vm.outputs.goToRepliesWithCommentProjectUpdateAndBecomeFirstResponder.map { $0.3 }
        .observe(self.goToCommentRepliesShowKeyboard.observer)
      self.vm.outputs.loadCommentsAndProjectIntoDataSource.map(first)
        .observe(self.loadCommentsAndProjectIntoDataSourceComments.observer)
      self.vm.outputs.loadCommentsAndProjectIntoDataSource.map(second)
        .observe(self.loadCommentsAndProjectIntoDataSourceProject.observer)
      self.vm.outputs.loadCommentsAndProjectIntoDataSource.map(third)
        .observe(self.loadCommentsAndProjectIntoDataSourceShouldShowErrorState.observer)
      self.vm.outputs.showHelpWebViewController.observe(self.showHelpWebViewController.observer)
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedOut() async {
    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: nil) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureCommentComposerViewURL
        .assertValues([nil], "nil is emitted because the user is not logged in.")
      self.configureCommentComposerViewCanPostComment
        .assertValues([false], "false is emitted because the project is not backed.")
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsBacking_False() async {
    let user = User.template |> \.id .~ 12_345

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: user) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureCommentComposerViewURL
        .assertValues(
          [URL(string: "http://www.kickstarter.com/medium.jpg")],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerViewCanPostComment
        .assertValues([false], "false is emitted because the project is not backed.")
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsBacking_True() async {
    let project = Project.template
      |> \.personalization.isBacking .~ true

    let user = User.template |> \.id .~ 12_345

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: user) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureCommentComposerViewURL
        .assertValues(
          [URL(string: "http://www.kickstarter.com/medium.jpg")],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerViewCanPostComment
        .assertValues([true], "true is emitted because the project is backed.")
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsCreatorOrCollaborator_True() async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureCommentComposerViewURL
        .assertValues(
          [URL(string: "http://www.kickstarter.com/medium.jpg")],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerViewCanPostComment
        .assertValues([true], "true is emitted because current user is creator or collaborator.")
    }
  }

  func testCommentComposerHidden_WhenUserIsLoggedIn() async {
    await withEnvironment(currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      self.commentComposerViewHidden.assertValue(false)
    }
  }

  func testDidBlockUser_EmitsOnSuccess() async {
    let envelope = EmptyResponseEnvelope()

    await withEnvironment(apiService: MockService(blockUserResult: .success(envelope)), currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)

      self.vm.inputs.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.inputs.blockUser(id: "\(User.template.id)")

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.didBlockUser.assertValueCount(1)
      self.didBlockUserError.assertValueCount(0)
    }
  }

  func testDidBlockUserError_EmitsOnFailure() async {
    let error = ErrorEnvelope(
      errorMessages: ["block user request error"],
      ksrCode: .GraphQLError,
      httpCode: 401,
      exception: nil
    )

    await withEnvironment(apiService: MockService(blockUserResult: .failure(error)), currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)

      self.vm.inputs.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.inputs.blockUser(id: "\(User.template.id)")

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(1)
    }
  }

  func testTrackUserBlockedFromComment_EventsEmitted() async {
    let segmentClient = MockTrackingClient()
    let ksrAnalytics = KSRAnalytics(
      config: .template,
      loggedInUser: User.template,
      segmentClient: segmentClient,
      appTrackingTransparency: MockAppTrackingTransparency()
    )

    await withEnvironment(
      apiService: MockService(blockUserResult: .success(EmptyResponseEnvelope())),
      currentUser: .template,
      ksrAnalytics: ksrAnalytics
    ) {
      self.vm.inputs.configureWith(project: .template, update: nil)

      self.vm.inputs.viewDidLoad()

      self.vm.inputs.blockUser(id: "111")

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      XCTAssertEqual(segmentClient.events, ["CTA Clicked", "CTA Clicked"])

      XCTAssertEqual(
        segmentClient.properties(forKey: "session_user_is_logged_in", as: Bool.self),
        [true, true]
      )
      XCTAssertEqual(segmentClient.properties(forKey: "user_uid", as: String.self), ["1", "1"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_cta"), ["block_user", "block_user"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_page"), ["project", "project"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_section"), ["comments", "comments"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_type"), ["initiate", "confirm"])
      XCTAssertEqual(segmentClient.properties(forKey: "interaction_target_uid"), ["111", "111"])
    }
  }

  func testCommentComposerHidden_WhenUserIsNotLoggedIn() async {
    await withEnvironment(currentUser: nil) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      self.commentComposerViewHidden.assertValue(true)
    }
  }

  func testOutput_ShowHelpWebViewController() async {
    var url = AppEnvironment.current.apiService.serverConfig.webBaseUrl
    url.appendPathComponent("help/community")

    self.showHelpWebViewController.assertDidNotEmitValue()

    await withEnvironment {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.showHelpWebViewController.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.vm.inputs.commentRemovedCellDidTapURL(url)

      self.showHelpWebViewController
        .assertValue(.community, ".community is emitted after commentRemovedCellDidTapURL is called.")
    }
  }

  func testGoToCommentReplies_ReplyComment_HasShownKeyboard() async {
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    let project = Project.template

    let comment = Comment.template
      |> \.replyCount .~ 1
      |> \.status .~ .success

    self.vm.inputs.configureWith(project: project, update: nil)
    self.vm.inputs.viewDidLoad()

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    self.vm.inputs.commentCellDidTapReply(comment: comment)

    self.goToCommentRepliesComment.assertValues([comment])
    self.goToCommentRepliesProject.assertValues([project])
    self.goToCommentRepliesUpdate.assertValues([nil])
    self.goToCommentRepliesShowKeyboard.assertValues([true])
  }

  func testGoToCommentReplies_CommentHasReplies_GoToEmits_HasNotShownKeyboard() async {
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    let project = Project.template
    let comment = Comment.template
      |> \.replyCount .~ 1
      |> \.status .~ .success

    self.vm.inputs.configureWith(project: project, update: .template)
    self.vm.inputs.viewDidLoad()

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    self.vm.inputs.commentCellDidTapViewReplies(comment)

    self.goToCommentRepliesComment.assertValues([comment])
    self.goToCommentRepliesProject.assertValues([project])
    self.goToCommentRepliesUpdate.assertValues([.template])
    self.goToCommentRepliesShowKeyboard.assertValues([false])
    self.goToCommentRepliesComment
      .assertValues([comment])
  }

  func testGoToCommentReplies_CommentHasReplies_IsDeleted_GoToDoesNotEmit_HasNotShownKeyboard() async {
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    let project = Project.template
    let comment = Comment.template
      |> \.replyCount .~ 1
      |> \.isDeleted .~ true

    self.vm.inputs.configureWith(project: project, update: nil)
    self.vm.inputs.viewDidLoad()

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    self.vm.inputs.didSelectComment(comment)

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()
  }

  func testGoToCommentReplies_CommentHasReplies_IsErrored_GoToDoesNotEmit() async {
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    let project = Project.template
    let comment = Comment.template
      |> \.replyCount .~ 1
      |> \.status .~ .failed

    self.vm.inputs.configureWith(project: project, update: nil)
    self.vm.inputs.viewDidLoad()

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    self.vm.inputs.didSelectComment(comment)

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()
  }

  func testGoToCommentReplies_CommentHasNoReplies_GoToDoesNotEmit_HasNotShownKeyboard() async {
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    let project = Project.template
    let comment = Comment.template
      |> \.replyCount .~ 0

    self.vm.inputs.configureWith(project: project, update: nil)
    self.vm.inputs.viewDidLoad()

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()

    self.vm.inputs.didSelectComment(comment)

    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.goToCommentRepliesProject.assertDidNotEmitValue()
    self.goToCommentRepliesUpdate.assertDidNotEmitValue()
    self.goToCommentRepliesShowKeyboard.assertDidNotEmitValue()
  }

  func testLoggedOut_ViewingComments_CommentsAreLoadedIntoDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ false

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        project: project,
        update: nil
      )

      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([project])
    }
  }

  func testLoggedInNonBacker_ViewingComments_CommentsAreLoadedIntoDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let user = User.template
    let accessToken = AccessTokenEnvelope(accessToken: "deadbeef", user: user)
    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ false

    await withEnvironment(
      apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(.singleCommentTemplate))
    ) {
      AppEnvironment.login(accessToken)

      self.vm.inputs.configureWith(
        project: project,
        update: nil
      )
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([project])
    }
  }

  func testLoggedInBacker_ViewingComments_CommentsAreLoadedIntoDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let user = User.template
    let accessToken = AccessTokenEnvelope(accessToken: "deadbeef", user: user)
    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ true

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      AppEnvironment.login(accessToken)

      self.vm.inputs.configureWith(
        project: project,
        update: nil
      )
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments
        .assertValues([envelope.comments], "New comments are emitted")
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([project], "New project is emitted")
    }
  }

  func testRefreshing_WhenNewCommentAdded_CommentsAreUpdatedInDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let project = Project.template
    let envelope = CommentsEnvelope.singleCommentTemplate

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments
        .assertValues([envelope.comments], "New comments are emitted")
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([project], "New project is emitted")

      let updatedEnvelope = CommentsEnvelope.multipleCommentTemplate

      await withEnvironment(apiService: MockService(
        fetchProjectCommentsEnvelopeResult: .success(updatedEnvelope)
      )) {
        self.vm.inputs.refresh()

        self.loadCommentsAndProjectIntoDataSourceComments
          .assertValues([envelope.comments], "No new comments are emitted")
        self.loadCommentsAndProjectIntoDataSourceProject
          .assertValues([project], "No new projects are emitted")

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        self.loadCommentsAndProjectIntoDataSourceComments
          .assertValues([envelope.comments, updatedEnvelope.comments], "New comments are emitted")
        self.loadCommentsAndProjectIntoDataSourceProject
          .assertValues([project, project], "Same project is emitted again")
      }
    }
  }

  func testProjectPagination_WhenLimitReached_CommentsAreUpdatedInDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
    self.beginOrEndRefreshing.assertDidNotEmitValue()
    self.configureFooterViewWithState.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
      self.beginOrEndRefreshing.assertValues([true])
      self.configureFooterViewWithState.assertValues([.hidden])

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
        [envelope.comments],
        "A set of comments is emitted."
      )
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template])
      self.beginOrEndRefreshing.assertValues([true, false])
      self.configureFooterViewWithState.assertValues([.hidden])

      let updatedEnvelope = CommentsEnvelope.multipleCommentTemplate

      await withEnvironment(apiService: MockService(
        fetchProjectCommentsEnvelopeResult: .success(updatedEnvelope)
      )) {
        self.vm.inputs.willDisplayRow(3, outOf: 4)

        self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
          [envelope.comments],
          "No new comments are emitted."
        )
        self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template])
        self.beginOrEndRefreshing.assertValues([true, false, true])
        self.configureFooterViewWithState.assertValues([.hidden, .activity])

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        self.loadCommentsAndProjectIntoDataSourceComments.assertValueCount(2)

        self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
          [envelope.comments, envelope.comments + updatedEnvelope.comments],
          "New comments are emitted."
        )
        self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template, .template])
        self.beginOrEndRefreshing.assertValues([true, false, true, false])
        self.configureFooterViewWithState.assertValues([.hidden, .activity, .hidden])
      }
    }
  }

  func testUpdatePagination_WhenLimitReached_CommentsAreLoadedIntoDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
    self.beginOrEndRefreshing.assertDidNotEmitValue()
    self.configureFooterViewWithState.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
      |> \.slug .~ nil
      |> \.updateID .~ "1"
    let update = Update.template

    await withEnvironment(apiService: MockService(
      fetchUpdateCommentsEnvelopeResult: .success(envelope),
      fetchProjectResult: .success(.template)
    )) {
      self.vm.inputs.configureWith(project: nil, update: update)
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
      self.beginOrEndRefreshing.assertValues([true])
      self.configureFooterViewWithState.assertValues([.hidden])

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
        [envelope.comments],
        "A set of comments is emitted."
      )
      self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template])
      self.beginOrEndRefreshing.assertValues([true, false])
      self.configureFooterViewWithState.assertValues([.hidden])

      let updatedEnvelope = CommentsEnvelope.multipleCommentTemplate
        |> \.slug .~ nil
        |> \.updateID .~ "1"

      await withEnvironment(apiService: MockService(fetchUpdateCommentsEnvelopeResult: .success(updatedEnvelope))) {
        self.vm.inputs.willDisplayRow(3, outOf: 4)

        self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
          [envelope.comments],
          "No new comments are emitted."
        )
        self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template])
        self.beginOrEndRefreshing.assertValues([true, false, true])
        self.configureFooterViewWithState.assertValues([.hidden, .activity])

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        self.loadCommentsAndProjectIntoDataSourceComments.assertValueCount(2)

        self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
          [envelope.comments, envelope.comments + updatedEnvelope.comments],
          "New comments are emitted."
        )
        self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template, .template])
        self.beginOrEndRefreshing.assertValues([true, false, true, false])
        self.configureFooterViewWithState.assertValues([.hidden, .activity, .hidden])
      }
    }
  }

  func testComments_WhenOnlyUpdate_CommentsAreUpdatedInDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let update = Update.template

    await withEnvironment(apiService: MockService(
      fetchUpdateCommentsEnvelopeResult: .success(envelope),
      fetchProjectResult: .success(.template)
    )) {
      self.vm.inputs.configureWith(
        project: nil,
        update: update
      )
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
      self.beginOrEndRefreshing.assertValues([true], "loading begins")

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments
        .assertValues([envelope.comments], "New comments are emitted")
      self.loadCommentsAndProjectIntoDataSourceProject
        .assertValues([.template], "Same project is emitted again")
      self.beginOrEndRefreshing.assertValues([true, false], "loading ends")
    }
  }

  func testComments_WhenNoProjectOrUpdate_CommentsAreNotUpdatedInDataSource() async {
    self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        project: nil,
        update: nil
      )
      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
      self.beginOrEndRefreshing.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()
      self.beginOrEndRefreshing.assertDidNotEmitValue()
    }
  }

  func testPostNewCommentFlow_Success() async {
    let envelope = CommentsEnvelope.singleCommentTemplate
    let expectedSuccessfulPostResponse = Comment.template

    let mockService = MockService(
      fetchProjectCommentsEnvelopeResult: .success(envelope),
      postCommentResult: .success(expectedSuccessfulPostResponse)
    )

    await withEnvironment(apiService: mockService, currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])

      let bodyText = "I just posted a comment."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableComment = Comment.failableComment(
        withId: self.uuidType.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: nil,
        user: .template,
        body: bodyText
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailableComment,
        "Failable temporary comment is emitted first."
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.count,
        2,
        "The amount of comments in the data source doesn't change."
      )

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedSuccessfulPostResponse,
        "After the request the actual comment is inserted, replacing the failable one."
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.count,
        2,
        "The amount of comments in the data source doesn't change."
      )
    }
  }

  func testPostNewCommentFlow_Error() async {
    let envelope = CommentsEnvelope.singleCommentTemplate

    let mockService = MockService(
      fetchProjectCommentsEnvelopeResult: .success(envelope),
      postCommentResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService, currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])

      let bodyText = "I just posted a comment."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableComment = Comment.failableComment(
        withId: self.uuidType.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: nil,
        user: .template,
        body: bodyText
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailableComment,
        "Failable temporary comment is emitted first."
      )

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      let expectedFailedComment = expectedFailableComment
        |> \.status .~ .failed

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailedComment,
        "If the request fails the failable comment is placed back in the data source with a failed status."
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.count,
        2,
        "The amount of comments in the data source doesn't change."
      )
    }
  }

  func testRetryCommentFlow_Success() async {
    let envelope = CommentsEnvelope.singleCommentTemplate

    let mockService1 = MockService(
      fetchProjectCommentsEnvelopeResult: .success(envelope),
      postCommentResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService1, currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])

      let bodyText = "I just posted a comment."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableComment = Comment.failableComment(
        withId: self.uuidType.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: nil,
        user: .template,
        body: bodyText
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailableComment,
        "Failable temporary comment is emitted first."
      )

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      let expectedFailedComment = expectedFailableComment
        |> \.status .~ .failed

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailedComment,
        "If the request fails the failable comment is placed back in the data source with a failed status."
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.count,
        2,
        "The amount of comments in the data source doesn't change."
      )

      let expectedSuccessfulPostedComment = expectedFailableComment
        |> \.status .~ .success

      let mockService2 = MockService(
        fetchProjectCommentsEnvelopeResult: .success(envelope),
        postCommentResult: .success(expectedSuccessfulPostedComment)
      )

      await withEnvironment(apiService: mockService2) {
        // Tap on the failed comment to retry
        self.vm.inputs.didSelectComment(expectedFailedComment)

        // Tapping repeatedly is ignored (in the case where retries may be in flight).
        self.vm.inputs.didSelectComment(expectedFailedComment)
        self.vm.inputs.didSelectComment(expectedFailedComment)
        self.vm.inputs.didSelectComment(expectedFailedComment)

        let expectedRetryingComment = expectedFailedComment
          |> \.status .~ .retrying

        XCTAssertEqual(
          self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
          expectedRetryingComment,
          "Comment is replaced with one with a retrying status."
        )

        await self.scheduler.advance(by: .seconds(1))
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        let expectedRetryingSuccessComment = expectedFailedComment
          |> \.body .~ bodyText
          |> \.status .~ .retrySuccess

        XCTAssertEqual(
          self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
          expectedRetryingSuccessComment,
          "Comment is replaced with one with a retrySuccess status after elapsed time."
        )

        await self.scheduler.advance(by: .seconds(3))
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        XCTAssertEqual(
          self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
          expectedSuccessfulPostedComment,
          "Comment is replaced with one with a success status after elapsed time."
        )
      }
    }
  }

  func testRetryCommentFlow_Error() async {
    let envelope = CommentsEnvelope.singleCommentTemplate

    let mockService1 = MockService(
      fetchProjectCommentsEnvelopeResult: .success(envelope),
      postCommentResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService1, currentUser: .template) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])

      let bodyText = "I just posted a comment."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableComment = Comment.failableComment(
        withId: self.uuidType.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: nil,
        user: .template,
        body: bodyText
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailableComment,
        "Failable temporary comment is emitted first."
      )

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      let expectedFailedComment = expectedFailableComment
        |> \.status .~ .failed

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
        expectedFailedComment,
        "If the request fails the failable comment is placed back in the data source with a failed status."
      )

      XCTAssertEqual(
        self.loadCommentsAndProjectIntoDataSourceComments.values.last?.count,
        2,
        "The amount of comments in the data source doesn't change."
      )

      let mockService2 = MockService(
        fetchProjectCommentsEnvelopeResult: .success(envelope),
        postCommentResult: .failure(.couldNotParseJSON)
      )

      await withEnvironment(apiService: mockService2) {
        // Tap on the failed comment to retry
        self.vm.inputs.didSelectComment(expectedFailedComment)

        let expectedRetryingComment = expectedFailedComment
          |> \.status .~ .retrying

        XCTAssertEqual(
          self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
          expectedRetryingComment,
          "Comment is replaced with one with a retrying status."
        )

        await self.scheduler.advance(by: .seconds(1))
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        XCTAssertEqual(
          self.loadCommentsAndProjectIntoDataSourceComments.values.last?.first,
          expectedFailedComment,
          "Comment is replaced with original failed comment."
        )
      }
    }
  }

  func testViewingComments_WithNoComments_ShouldHaveCellSeparator() async {
    self.cellSeparatorHidden.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.emptyCommentsTemplate
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ false

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        project: project,
        update: nil
      )

      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.cellSeparatorHidden.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])
      self.cellSeparatorHidden.assertValue(true)
    }
  }

  func testViewingComments_WithComments_ShouldHaveCellSeparator() async {
    self.cellSeparatorHidden.assertDidNotEmitValue()
    self.loadCommentsAndProjectIntoDataSourceProject.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template
      |> Project.lens.personalization.isBacking .~ false

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        project: project,
        update: nil
      )

      self.vm.inputs.viewDidLoad()

      self.loadCommentsAndProjectIntoDataSourceComments.assertDidNotEmitValue()
      self.cellSeparatorHidden.assertDidNotEmitValue()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceComments.assertValues([envelope.comments])
      self.cellSeparatorHidden.assertValue(false)
    }
  }

  func testConfigureFooterViewWithState_HiddenOnViewDidLoad() async {
    self.configureFooterViewWithState.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureFooterViewWithState.assertValues([.hidden])
    }
  }

  func testDataSourceState_ErrorOnFirstPage() async {
    self.configureFooterViewWithState.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate
    let project = Project.template

    await withEnvironment(
      apiService: MockService(fetchProjectCommentsEnvelopeResult: .failure(.couldNotParseJSON))
    ) {
      self.vm.inputs.configureWith(project: project, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureFooterViewWithState.assertValues([.hidden])

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadCommentsAndProjectIntoDataSourceShouldShowErrorState.assertValues([true])

      await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
        self.vm.inputs.commentTableViewFooterViewDidTapRetry()

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        self.loadCommentsAndProjectIntoDataSourceShouldShowErrorState.assertLastValue(false)
      }
    }
  }

  func testConfigureFooterViewWithState_ErrorOnNextPage() async {
    self.configureFooterViewWithState.assertDidNotEmitValue()

    let envelope = CommentsEnvelope.singleCommentTemplate

    await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(project: .template, update: nil)
      self.vm.inputs.viewDidLoad()

      self.configureFooterViewWithState.assertValues([.hidden])

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.configureFooterViewWithState.assertValues([.hidden])

      let updatedEnvelope = CommentsEnvelope.multipleCommentTemplate

      await withEnvironment(apiService: MockService(
        fetchProjectCommentsEnvelopeResult: .success(updatedEnvelope)
      )) {
        self.vm.inputs.willDisplayRow(3, outOf: 4)

        self.configureFooterViewWithState.assertValues(
          [.hidden, .activity], "Activity is shown during paging."
        )

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        self.configureFooterViewWithState.assertValues(
          [.hidden, .activity, .hidden], "Returns to hidden."
        )

        // "Scrolling"
        self.vm.inputs.willDisplayRow(5, outOf: 10)

        await withEnvironment(
          apiService: MockService(fetchProjectCommentsEnvelopeResult: .failure(.couldNotParseJSON))
        ) {
          self.vm.inputs.willDisplayRow(9, outOf: 10)

          self.configureFooterViewWithState.assertValues(
            [.hidden, .activity, .hidden, .activity], "Activity is shown during paging."
          )

          await self.scheduler.advance()
          await self.vm.waitForLoads()
          await self.scheduler.advance()

          self.configureFooterViewWithState.assertValues(
            [.hidden, .activity, .hidden, .activity, .error], "Emits error state."
          )

          await withEnvironment(
            apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(.singleCommentTemplate))
          ) {
            // Retry
            self.vm.inputs.commentTableViewFooterViewDidTapRetry()

            self.configureFooterViewWithState.assertValues(
              [.hidden, .activity, .hidden, .activity, .error, .activity],
              "Activity is shown during paging."
            )

            await self.scheduler.advance()
            await self.vm.waitForLoads()
            await self.scheduler.advance()

            self.configureFooterViewWithState.assertValues(
              [.hidden, .activity, .hidden, .activity, .error, .activity, .hidden],
              "Returns to hidden."
            )
          }
        }
      }
    }
  }
}
