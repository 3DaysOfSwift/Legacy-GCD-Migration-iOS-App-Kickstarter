@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class CommentRepliesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = CommentRepliesViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }, sleep: { _ in try Task.checkCancellation() }))

  private let configureCommentComposerBecomeFirstResponder = ReplyRecorder<Bool>()
  private let configureCommentComposerViewURL = ReplyRecorder<URL?>()
  private let configureCommentComposerViewCanPostComment = ReplyRecorder<Bool>()
  private let didBlockUser = ReplyRecorder<()>()
  private let didBlockUserError = ReplyRecorder<()>()
  private let loadCommentIntoDataSourceComment = ReplyRecorder<Comment>()
  private let loadFailableReplyIntoDataSource = ReplyRecorder<Comment>()
  private let loadFailableCommentIDIntoDataSource = ReplyRecorder<String>()
  private let loadFailableProjectIntoDataSource = ReplyRecorder<Project>()
  private let loadRepliesAndProjectIntoDataSourceProject = ReplyRecorder<Project>()
  private let loadRepliesAndProjectIntoDataSourceReplies = ReplyRecorder<[Comment]>()
  private let loadRepliesAndProjectIntoDataSourceTotalCount = ReplyRecorder<Int>()
  private let resetCommentComposer = ReplyRecorder<()>()
  private let scrollToReply = ReplyRecorder<String>()
  private let showPaginationErrorState = ReplyRecorder<()>()

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated {
      self.vm.outputs.onConfigureComposer = { [weak self] data in
        self?.configureCommentComposerBecomeFirstResponder.record(data.becomeFirstResponder)
        self?.configureCommentComposerViewURL.record(data.avatarURL)
        self?.configureCommentComposerViewCanPostComment.record(data.canPostComment)
      }
      self.vm.outputs.onLoadRootComment = { [weak self] comment in self?.loadCommentIntoDataSourceComment.record(comment) }
      self.vm.outputs.onDidBlockUser = { [weak self] in self?.didBlockUser.record(()) }
      self.vm.outputs.onDidBlockUserError = { [weak self] in self?.didBlockUserError.record(()) }
      self.vm.outputs.onLoadFailableReply = { [weak self] comment, id, project in
        self?.loadFailableReplyIntoDataSource.record(comment)
        self?.loadFailableCommentIDIntoDataSource.record(id)
        self?.loadFailableProjectIntoDataSource.record(project)
      }

      self.vm.outputs.onLoadReplies = { [weak self] repliesAndCount, project in
        self?.loadRepliesAndProjectIntoDataSourceProject.record(project)
        self?.loadRepliesAndProjectIntoDataSourceReplies.record(repliesAndCount.0)
        self?.loadRepliesAndProjectIntoDataSourceTotalCount.record(repliesAndCount.1)
      }
      self.vm.outputs.onResetCommentComposer = { [weak self] in self?.resetCommentComposer.record(()) }
      self.vm.outputs.onScrollToReply = { [weak self] id in self?.scrollToReply.record(id) }
      self.vm.outputs.onPaginationError = { [weak self] in self?.showPaginationErrorState.record(()) }
    }
  }

  func testDataSource_WithComment_HasComment() async {
    self.loadCommentIntoDataSourceComment.assertDidNotEmitValue()

    let rootComment = Comment.template

    await withEnvironment {
      self.vm.inputs.configureWith(
        comment: rootComment,
        project: .template,
        update: nil,
        inputAreaBecomeFirstResponder: false,
        replyId: nil
      )

      self.loadCommentIntoDataSourceComment.assertDidNotEmitValue()

      self.vm.inputs.viewDidLoad()

      self.loadCommentIntoDataSourceComment.assertValue(rootComment)
    }
  }

  func testConfiguringAfterViewLoadsPublishesRootComment() async {
    await withEnvironment {
      self.vm.inputs.viewDidLoad()
      self.loadCommentIntoDataSourceComment.assertDidNotEmitValue()
      self.vm.inputs.configureWith(
        comment: .template, project: .template, update: nil,
        inputAreaBecomeFirstResponder: false, replyId: nil
      )
      self.loadCommentIntoDataSourceComment.assertValue(.template)
      await self.vm.waitForLoads()
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedOut_HasNoCommentComposer() async {
    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()
    self.configureCommentComposerBecomeFirstResponder.assertDidNotEmitValue()

    await withEnvironment(currentUser: nil) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

      self.configureCommentComposerViewURL
        .assertValues([nil], "nil is emitted because the user is not logged in.")
      self.configureCommentComposerViewCanPostComment
        .assertValues([false], "false is emitted because the project is not backed.")
      self.configureCommentComposerBecomeFirstResponder.assertValues(
        [false],
        "false is emitted because the user is not logged in."
      )
    }
  }

  func testDidBlockUser_EmitsOnSuccess() async {
    let envelope = EmptyResponseEnvelope()

    await withEnvironment(
      apiService: MockService(blockUserResult: .success(envelope)),
      currentUser: .template
    ) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

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
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

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
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

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

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsBacking_False_HasBlockedCommentComposer(
  ) async {
    let user = User.template |> \.id .~ 12_345

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: user) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

      self.configureCommentComposerViewURL
        .assertValues(
          [URL(string: "http://www.kickstarter.com/medium.jpg")],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerViewCanPostComment
        .assertValues([false], "false is emitted because the project is not backed.")
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsBacking_True_HasCommentComposer() async {
    let project = Project.template
      |> \.personalization.isBacking .~ true

    let user = User.template |> \.id .~ 12_345

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: user) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
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

  func testOutput_ConfigureCommentComposerViewWithData_IsLoggedIn_IsCreatorOrCollaborator_True_HasCommentComposer(
  ) async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
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

  func testOutput_ConfigureCommentComposerViewWithData_IsFromReplyComment_HasShownKeyboard() async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

      self.configureCommentComposerViewURL
        .assertValues(
          [
            URL(string: "http://www.kickstarter.com/medium.jpg"),
            URL(string: "http://www.kickstarter.com/medium.jpg")
          ],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerBecomeFirstResponder
        .assertValues([false, true], "true is emitted because the user clicked on reply on the root comment")
    }
  }

  func testOutput_ConfigureCommentComposerViewWithData_IsFromViewReplies_HasNotShownKeyboard() async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    self.configureCommentComposerViewURL.assertDidNotEmitValue()
    self.configureCommentComposerViewCanPostComment.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: false,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewDidAppear()

      self.configureCommentComposerViewURL
        .assertValues(
          [URL(string: "http://www.kickstarter.com/medium.jpg")],
          "An URL is emitted because the user is logged in."
        )
      self.configureCommentComposerBecomeFirstResponder
        .assertValues(
          [false],
          "false is emitted because the user clicked on view replies on the root comment"
        )
    }
  }

  func testOutput_LoadRepliesProjectAndTotalCountIntoDataSource_PaginationSuccessful() async {
    let project = Project.template
    let envelope = CommentRepliesEnvelope.successfulRepliesTemplate
    let updatedEnvelope = CommentRepliesEnvelope(
      comment: .template,
      cursor: "nextCursor",
      hasPreviousPage: false,
      replies: [
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate
      ],
      totalCount: 14
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        comment: .template,
        project: project,
        update: nil,
        inputAreaBecomeFirstResponder: false,
        replyId: nil
      )

      self.vm.inputs.viewDidLoad()

      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([])

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([envelope.totalCount])

      await withEnvironment(
        apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(updatedEnvelope))
      ) {
        self.vm.inputs.paginateOrErrorCellWasTapped()

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project, project])
        self.loadRepliesAndProjectIntoDataSourceReplies
          .assertValues([envelope.replies, updatedEnvelope.replies])
        self.loadRepliesAndProjectIntoDataSourceTotalCount
          .assertValues([updatedEnvelope.totalCount, updatedEnvelope.totalCount])
      }
    }
  }

  func testOutput_LoadRepliesProjectAndTotalCountIntoDataSource_PaginationFailedThenSuccesful() async {
    let project = Project.template
    let envelope = CommentRepliesEnvelope.successfulRepliesTemplate
    let updatedEnvelope = CommentRepliesEnvelope(
      comment: .template,
      cursor: "nextCursor",
      hasPreviousPage: false,
      replies: [
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate,
        .collaboratorTemplate
      ],
      totalCount: 14
    )

    await withEnvironment(apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(envelope))) {
      self.vm.inputs.configureWith(
        comment: .template,
        project: project,
        update: nil,
        inputAreaBecomeFirstResponder: false,
        replyId: nil
      )

      self.vm.inputs.viewDidLoad()

      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([])
      self.showPaginationErrorState.assertDidNotEmitValue()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([envelope.totalCount])
      self.showPaginationErrorState.assertDidNotEmitValue()
      self.showPaginationErrorState.assertValueCount(0)

      await withEnvironment(
        apiService: MockService(fetchCommentRepliesEnvelopeResult: .failure(.couldNotParseJSON))
      ) {
        self.vm.inputs.paginateOrErrorCellWasTapped()

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project])
        self.loadRepliesAndProjectIntoDataSourceReplies
          .assertValues([envelope.replies])
        self.loadRepliesAndProjectIntoDataSourceTotalCount
          .assertValues([envelope.totalCount])
        self.showPaginationErrorState.assertDidEmitValue()
        self.showPaginationErrorState.assertValueCount(1)

        await withEnvironment(
          apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(updatedEnvelope))
        ) {
          self.vm.inputs.paginateOrErrorCellWasTapped()

          await self.vm.waitForLoads()

          await self.vm.waitForLoads()
          await self.vm.waitForLoads()


          self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project, project])
          self.loadRepliesAndProjectIntoDataSourceReplies
            .assertValues([envelope.replies, updatedEnvelope.replies])
          self.loadRepliesAndProjectIntoDataSourceTotalCount
            .assertValues([envelope.totalCount, updatedEnvelope.totalCount])
          self.showPaginationErrorState.assertValueCount(1)
        }
      }
    }
  }

  func testOutput_ScrollToReply_Emits() async {
    let envelope = CommentRepliesEnvelope.singleReplyTemplate
    let mockService = MockService(fetchCommentRepliesEnvelopeResult: .success(envelope))
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    await withEnvironment(apiService: mockService, currentUser: .template) {
      self.scrollToReply.assertDidNotEmitValue()

      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: envelope.replies[0].id
        )
      self.vm.inputs.viewDidLoad()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.vm.inputs.dataSourceLoaded()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.scrollToReply.assertValue(envelope.replies[0].id)
    }
  }

  func testOutput_ScrollToReply_DoesNotEmit() async {
    let envelope = CommentRepliesEnvelope.singleReplyTemplate
    let mockService = MockService(fetchCommentRepliesEnvelopeResult: .success(envelope))
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    await withEnvironment(apiService: mockService, currentUser: .template) {
      self.scrollToReply.assertDidNotEmitValue()

      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.vm.inputs.dataSourceLoaded()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.scrollToReply.assertDidNotEmitValue()
    }
  }

  func testOutput_SubmitText_FromCommentComposer_ResetsCommentComposerTextInput() async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    self.resetCommentComposer.assertDidNotEmitValue()

    await withEnvironment(currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: project,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()

      self.resetCommentComposer.assertDidNotEmitValue()

      self.vm.inputs.commentComposerDidSubmitText("Text")

      self.resetCommentComposer.assertDidEmitValue()
    }
  }

  func testOutput_SubmitText_FromCommentComposer_ReturnsFailableCommentAndSuccessfulComment() async {
    let project = Project.template
      |> \.personalization.isBacking .~ false
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    let mockService = MockService(
      postCommentResult: .success(.replyTemplate)
    )

    self.loadFailableReplyIntoDataSource.assertDidNotEmitValue()
    self.loadFailableProjectIntoDataSource.assertDidNotEmitValue()
    self.loadFailableCommentIDIntoDataSource.assertDidNotEmitValue()

    await withEnvironment(apiService: mockService, currentUser: .template) {
      self.vm.inputs.configureWith(
        comment: .replyRootCommentTemplate,
        project: project,
        update: nil,
        inputAreaBecomeFirstResponder: true,
        replyId: nil
      )
      self.vm.inputs.viewDidLoad()

      self.loadFailableReplyIntoDataSource.assertDidNotEmitValue()
      self.loadFailableProjectIntoDataSource.assertDidNotEmitValue()
      self.loadFailableCommentIDIntoDataSource.assertDidNotEmitValue()

      self.vm.inputs.commentComposerDidSubmitText("Text")

      self.loadFailableReplyIntoDataSource.assertValueCount(1)
      self.loadFailableProjectIntoDataSource.assertLastValue(project)
      self.loadFailableCommentIDIntoDataSource.assertLastValue(MockUUID().uuidString)

      XCTAssertEqual(self.loadFailableReplyIntoDataSource.lastValue!.body, "Text")
      XCTAssertEqual(self.loadFailableReplyIntoDataSource.lastValue!.author.id, "\(User.template.id)")
      XCTAssertEqual(
        self.loadFailableReplyIntoDataSource.lastValue!.parentId!,
        Comment.replyRootCommentTemplate.id
      )

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadFailableReplyIntoDataSource.assertValueCount(2)
      self.loadFailableReplyIntoDataSource.assertLastValue(.replyTemplate)
      self.loadFailableProjectIntoDataSource.assertLastValue(project)
      self.loadFailableCommentIDIntoDataSource.assertLastValue(MockUUID().uuidString)
    }
  }

  func testRetryCommentFlow_Success() async {
    let envelope = CommentRepliesEnvelope.singleReplyTemplate

    let mockService1 = MockService(
      fetchCommentRepliesEnvelopeResult: .success(envelope),
      postCommentResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService1, currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])

      let bodyText = "I just posted a reply."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableReply = Comment.failableComment(
        withId: MockUUID.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: Comment.template.id,
        user: .template,
        body: bodyText
      )

      // optimistically posted failable comment
      XCTAssertEqual(
        self.loadFailableReplyIntoDataSource.values.last,
        expectedFailableReply,
        "Failable temporary reply is emitted first."
      )

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      let expectedFailedComment = expectedFailableReply
        |> \.status .~ .failed

      // failed comment after network request fails.
      XCTAssertEqual(
        self.loadFailableReplyIntoDataSource.values.last,
        expectedFailedComment,
        "If the request fails the failable reply is placed back in the data source with a failed status."
      )

      let expectedSuccessfulPostedComment = expectedFailedComment
        |> \.status .~ .success

      let mockService2 = MockService(
        fetchCommentRepliesEnvelopeResult: .success(envelope),
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

        // previously failed comment is in retrying status
        XCTAssertEqual(
          self.loadFailableReplyIntoDataSource.values.last,
          expectedRetryingComment,
          "Comment is replaced with one with a retrying status."
        )

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        let expectedRetryingSuccessComment = expectedFailedComment
          |> \.status .~ .retrySuccess

        XCTAssertTrue(
          self.loadFailableReplyIntoDataSource.values.contains(expectedRetryingSuccessComment),
          "Comment passes through the retry success status before completion."
        )

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        // comment posts and is successful
        XCTAssertEqual(
          self.loadFailableReplyIntoDataSource.values.last,
          expectedSuccessfulPostedComment,
          "Comment is replaced with one with a success status after elapsed time."
        )
      }
    }
  }

  func testRetryCommentFlow_Error() async {
    let envelope = CommentRepliesEnvelope.singleReplyTemplate

    let mockService1 = MockService(
      fetchCommentRepliesEnvelopeResult: .success(envelope),
      postCommentResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService1, currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])

      let bodyText = "I just posted a reply."

      self.vm.inputs.commentComposerDidSubmitText(bodyText)

      let expectedFailableReply = Comment.failableComment(
        withId: MockUUID.init().uuidString,
        date: MockDate().date,
        project: .template,
        parentId: Comment.template.id,
        user: .template,
        body: bodyText
      )

      // optimistically posted failable comment
      XCTAssertEqual(
        self.loadFailableReplyIntoDataSource.values.last,
        expectedFailableReply,
        "Failable temporary reply is emitted first."
      )

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      let expectedFailedReply = expectedFailableReply
        |> \.status .~ .failed

      // failed comment after network request fails.
      XCTAssertEqual(
        self.loadFailableReplyIntoDataSource.values.last,
        expectedFailedReply,
        "If the request fails the failable reply is placed back in the data source with a failed status."
      )

      let mockService2 = MockService(
        fetchCommentRepliesEnvelopeResult: .success(envelope),
        postCommentResult: .failure(.couldNotParseJSON)
      )

      await withEnvironment(apiService: mockService2) {
        // Tap on the failed comment to retry
        self.vm.inputs.didSelectComment(expectedFailedReply)

        let expectedRetryingReply = expectedFailedReply
          |> \.status .~ .retrying

        // failed comment shows retrying when posting again.
        XCTAssertEqual(
          self.loadFailableReplyIntoDataSource.values.last,
          expectedRetryingReply,
          "Reply is replaced with one with a retrying status."
        )

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        // retry fails so original failed comment placed back
        XCTAssertEqual(
          self.loadFailableReplyIntoDataSource.values.last,
          expectedFailedReply,
          "Reply is replaced with original failed comment."
        )
      }
    }
  }

  func testRetryFirstPage_Success() async {
    let envelope = CommentRepliesEnvelope.successfulRepliesTemplate

    let mockService1 = MockService(
      fetchCommentRepliesEnvelopeResult: .failure(.couldNotParseJSON)
    )

    await withEnvironment(apiService: mockService1, currentUser: .template) {
      self.vm.inputs
        .configureWith(
          comment: .template,
          project: .template,
          update: nil,
          inputAreaBecomeFirstResponder: true,
          replyId: nil
        )
      self.vm.inputs.viewDidLoad()

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([])
      self.showPaginationErrorState.assertDidEmitValue()
      self.showPaginationErrorState.assertValueCount(1)

      await self.vm.waitForLoads()

      await self.vm.waitForLoads()
      await self.vm.waitForLoads()


      let mockService2 = MockService(
        fetchCommentRepliesEnvelopeResult: .success(envelope)
      )

      await withEnvironment(apiService: mockService2) {
        self.vm.inputs.retryFirstPage()

        await self.vm.waitForLoads()

        await self.vm.waitForLoads()
        await self.vm.waitForLoads()


        self.loadRepliesAndProjectIntoDataSourceProject.assertValues([.template])
        self.loadRepliesAndProjectIntoDataSourceReplies
          .assertValues([envelope.replies])
        self.loadRepliesAndProjectIntoDataSourceTotalCount
          .assertValues([envelope.totalCount])
        self.showPaginationErrorState.assertValueCount(1)
      }
    }
  }
}

@MainActor
private final class ReplyRecorder<Value> {
  private(set) var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func record(_ value: Value) { self.values.append(value) }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertDidEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(self.values.isEmpty, message, file: file, line: line)
  }
}

private extension ReplyRecorder where Value: Equatable {
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
