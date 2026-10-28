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
internal final class CommentRepliesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = CommentRepliesViewModel(feature: DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  }, sleep: { _ in try Task.checkCancellation() }))

  private let configureCommentComposerBecomeFirstResponder = TestObserver<Bool, Never>()
  private let configureCommentComposerViewURL = TestObserver<URL?, Never>()
  private let configureCommentComposerViewCanPostComment = TestObserver<Bool, Never>()
  private let didBlockUser = TestObserver<(), Never>()
  private let didBlockUserError = TestObserver<(), Never>()
  private let loadCommentIntoDataSourceComment = TestObserver<Comment, Never>()
  private let loadFailableReplyIntoDataSource = TestObserver<Comment, Never>()
  private let loadFailableCommentIDIntoDataSource = TestObserver<String, Never>()
  private let loadFailableProjectIntoDataSource = TestObserver<Project, Never>()
  private let loadRepliesAndProjectIntoDataSourceProject = TestObserver<Project, Never>()
  private let loadRepliesAndProjectIntoDataSourceReplies = TestObserver<[Comment], Never>()
  private let loadRepliesAndProjectIntoDataSourceTotalCount = TestObserver<Int, Never>()
  private let resetCommentComposer = TestObserver<(), Never>()
  private let scrollToReply = TestObserver<String, Never>()
  private let showPaginationErrorState = TestObserver<(), Never>()

  override func setUp() {
    super.setUp()
    MainActor.assumeIsolated {
      self.vm.outputs.configureCommentComposerViewWithData.map(\.becomeFirstResponder)
        .observe(self.configureCommentComposerBecomeFirstResponder.observer)
      self.vm.outputs.configureCommentComposerViewWithData.map(\.avatarURL)
        .observe(self.configureCommentComposerViewURL.observer)
      self.vm.outputs.configureCommentComposerViewWithData.map(\.canPostComment)
        .observe(self.configureCommentComposerViewCanPostComment.observer)
      self.vm.outputs.loadCommentIntoDataSource.observe(self.loadCommentIntoDataSourceComment.observer)
      self.vm.outputs.didBlockUser.observe(self.didBlockUser.observer)
      self.vm.outputs.didBlockUserError.observe(self.didBlockUserError.observer)
      self.vm.outputs.loadFailableReplyIntoDataSource.map(first)
        .observe(self.loadFailableReplyIntoDataSource.observer)

      self.vm.outputs.loadFailableReplyIntoDataSource.map(second)
        .observe(self.loadFailableCommentIDIntoDataSource.observer)

      self.vm.outputs.loadFailableReplyIntoDataSource.map(third)
        .observe(self.loadFailableProjectIntoDataSource.observer)

      self.vm.outputs.loadRepliesAndProjectIntoDataSource.map(second)
        .observe(self.loadRepliesAndProjectIntoDataSourceProject.observer)
      self.vm.outputs.loadRepliesAndProjectIntoDataSource
        .map(first)
        .map { replies, _ in replies }
        .observe(self.loadRepliesAndProjectIntoDataSourceReplies.observer)
      self.vm.outputs.loadRepliesAndProjectIntoDataSource
        .map(first)
        .map { _, totalCount in totalCount }
        .observe(self.loadRepliesAndProjectIntoDataSourceTotalCount.observer)
      self.vm.outputs.resetCommentComposer.observe(self.resetCommentComposer.observer)
      self.vm.outputs.scrollToReply.observe(self.scrollToReply.observer)
      self.vm.outputs.showPaginationErrorState.observe(self.showPaginationErrorState.observer)
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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([project])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([envelope.totalCount])

      await withEnvironment(
        apiService: MockService(fetchCommentRepliesEnvelopeResult: .success(updatedEnvelope))
      ) {
        self.vm.inputs.paginateOrErrorCellWasTapped()

        await self.vm.waitForLoads()

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

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

          await self.scheduler.advance()
          await self.vm.waitForLoads()
          await self.vm.waitForLoads()
          await self.scheduler.advance()

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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.vm.inputs.dataSourceLoaded()

      await self.vm.waitForLoads()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([envelope.replies])
      self.vm.inputs.dataSourceLoaded()

      await self.vm.waitForLoads()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

        await self.scheduler.advance(by: .seconds(1))
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

        let expectedRetryingSuccessComment = expectedFailedComment
          |> \.status .~ .retrySuccess

        XCTAssertEqual(
          self.loadFailableReplyIntoDataSource.values.last,
          expectedRetryingSuccessComment,
          "Comment is replaced with one with a retry success status after elapsed time."
        )

        await self.vm.waitForLoads()

        await self.scheduler.advance(by: .seconds(3))
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

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

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

      await self.scheduler.advance(by: .seconds(1))
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

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

        await self.scheduler.advance(by: .seconds(1))
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

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

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      self.loadRepliesAndProjectIntoDataSourceProject.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceReplies.assertValues([])
      self.loadRepliesAndProjectIntoDataSourceTotalCount.assertValues([])
      self.showPaginationErrorState.assertDidEmitValue()
      self.showPaginationErrorState.assertValueCount(1)

      await self.vm.waitForLoads()

      await self.scheduler.advance()
      await self.vm.waitForLoads()
      await self.vm.waitForLoads()
      await self.scheduler.advance()

      let mockService2 = MockService(
        fetchCommentRepliesEnvelopeResult: .success(envelope)
      )

      await withEnvironment(apiService: mockService2) {
        self.vm.inputs.retryFirstPage()

        await self.vm.waitForLoads()

        await self.scheduler.advance()
        await self.vm.waitForLoads()
        await self.vm.waitForLoads()
        await self.scheduler.advance()

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
