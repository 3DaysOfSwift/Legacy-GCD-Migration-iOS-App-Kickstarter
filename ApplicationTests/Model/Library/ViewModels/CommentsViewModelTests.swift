@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class CommentsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = CommentsViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }, sleep: { _ in try Task.checkCancellation() }))

  private let beginOrEndRefreshing = CommentsRecorder<Bool>()
  private let cellSeparatorHidden = CommentsRecorder<Bool>()
  private let commentComposerViewHidden = CommentsRecorder<Bool>()
  private let configureCommentComposerViewURL = CommentsRecorder<URL?>()
  private let configureCommentComposerViewCanPostComment = CommentsRecorder<Bool>()
  private let configureFooterViewWithState = CommentsRecorder<CommentTableViewFooterViewState>()
  private let didBlockUser = CommentsRecorder<()>()
  private let didBlockUserError = CommentsRecorder<()>()
  private let goToCommentRepliesComment = CommentsRecorder<Comment>()
  private let goToCommentRepliesProject = CommentsRecorder<Project>()
  private let goToCommentRepliesUpdate = CommentsRecorder<Update?>()
  private let goToCommentRepliesShowKeyboard = CommentsRecorder<Bool>()
  private let loadCommentsAndProjectIntoDataSourceComments = CommentsRecorder<[Comment]>()
  private let loadCommentsAndProjectIntoDataSourceShouldShowErrorState = CommentsRecorder<Bool>()
  private let loadCommentsAndProjectIntoDataSourceProject = CommentsRecorder<Project>()
  private let showHelpWebViewController = CommentsRecorder<HelpType>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {
      self.vm.outputs.onRefreshing = { [weak self] in self?.beginOrEndRefreshing.record($0) }
      self.vm.outputs.onSeparatorHidden = { [weak self] in self?.cellSeparatorHidden.record($0) }
      self.vm.outputs.onConfigureComposer = { [weak self] data in
        self?.commentComposerViewHidden.record(data.hidden)
        self?.configureCommentComposerViewURL.record(data.avatarURL)
        self?.configureCommentComposerViewCanPostComment.record(data.canPostComment)
      }
      self.vm.outputs.onDidBlockUser = { [weak self] in self?.didBlockUser.record(()) }
      self.vm.outputs.onDidBlockUserError = { [weak self] in self?.didBlockUserError.record(()) }
      self.vm.outputs.onFooterState = { [weak self] in self?.configureFooterViewWithState.record($0) }
      self.vm.outputs.onShowReplies = { [weak self] comment, project, update, firstResponder in
        self?.goToCommentRepliesComment.record(comment)
        self?.goToCommentRepliesProject.record(project)
        self?.goToCommentRepliesUpdate.record(update)
        self?.goToCommentRepliesShowKeyboard.record(firstResponder)
      }
      self.vm.outputs.onLoadComments = { [weak self] comments, project, error in
        self?.loadCommentsAndProjectIntoDataSourceComments.record(comments)
        self?.loadCommentsAndProjectIntoDataSourceProject.record(project)
        self?.loadCommentsAndProjectIntoDataSourceShouldShowErrorState.record(error)
      }
      self.vm.outputs.onShowHelp = { [weak self] in self?.showHelpWebViewController.record($0) }
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

    await withEnvironment(
      apiService: MockService(blockUserResult: .success(envelope)),
      currentUser: .template
    ) {
      self.vm.inputs.configureWith(project: .template, update: nil)

      self.vm.inputs.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.inputs.blockUser(id: "\(User.template.id)")

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.showHelpWebViewController.assertDidNotEmitValue()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.vm.inputs.commentRemovedCellDidTapURL(url)

      self.showHelpWebViewController
        .assertValue(.community, ".community is emitted after commentRemovedCellDidTapURL is called.")
    }
  }

  func testSubmittingCommentResetsComposer() {
    var resets = 0
    self.vm.outputs.onResetComposerAndScrollToTop = { resets += 1 }
    self.vm.inputs.commentComposerDidSubmitText("hello")
    XCTAssertEqual(resets, 1)
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

  func testReplyTapBeforeConfigurationWaitsForProject() {
    self.vm.inputs.commentCellDidTapReply(comment: .template)
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.vm.inputs.configureWith(project: .template, update: nil)
    self.goToCommentRepliesComment.assertDidNotEmitValue()
    self.vm.inputs.viewDidLoad()
    self.goToCommentRepliesComment.assertValues([.template])
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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await withEnvironment(
        apiService: MockService(fetchUpdateCommentsEnvelopeResult: .success(updatedEnvelope))
      ) {
        self.vm.inputs.willDisplayRow(3, outOf: 4)

        self.loadCommentsAndProjectIntoDataSourceComments.assertValues(
          [envelope.comments],
          "No new comments are emitted."
        )
        self.loadCommentsAndProjectIntoDataSourceProject.assertValues([.template])
        self.beginOrEndRefreshing.assertValues([true, false, true])
        self.configureFooterViewWithState.assertValues([.hidden, .activity])

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        let expectedRetryingSuccessComment = expectedFailedComment
          |> \.body .~ bodyText
          |> \.status .~ .retrySuccess

        XCTAssertTrue(
          self.loadCommentsAndProjectIntoDataSourceComments.values.contains { $0.first == expectedRetryingSuccessComment },
          "Comment passes through the retry success status before completion."
        )

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadCommentsAndProjectIntoDataSourceShouldShowErrorState.assertValues([true])

      await withEnvironment(apiService: MockService(fetchProjectCommentsEnvelopeResult: .success(envelope))) {
        self.vm.inputs.commentTableViewFooterViewDidTapRetry()

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.configureFooterViewWithState.assertValues([.hidden])

      let updatedEnvelope = CommentsEnvelope.multipleCommentTemplate

      await withEnvironment(apiService: MockService(
        fetchProjectCommentsEnvelopeResult: .success(updatedEnvelope)
      )) {
        self.vm.inputs.willDisplayRow(3, outOf: 4)

        self.configureFooterViewWithState.assertValues(
          [.hidden, .activity], "Activity is shown during paging."
        )

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


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

          await self.vm.waitForLoads()

          await self.vm.waitForLoads()
          await self.vm.waitForLoads()


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

            await self.vm.waitForLoads()

            await self.vm.waitForLoads()
            await self.vm.waitForLoads()


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

@MainActor
private final class CommentsRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}

private extension CommentsRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, [expected], message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}
