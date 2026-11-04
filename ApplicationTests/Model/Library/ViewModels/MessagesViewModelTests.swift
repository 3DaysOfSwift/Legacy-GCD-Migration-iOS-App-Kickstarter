@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class MessagesViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = MessagingFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncMessagingProvider(service: AppEnvironment.current.apiService) }
  )
  private let discussion = DiscussionFeature(sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }), makeProvider: {
    AsyncDiscussionProvider(service: AppEnvironment.current.apiService)
  })
  private lazy var vm: MessagesViewModel = MessagesViewModel(feature: self.feature, discussion: self.discussion)

  private let backingAndProjectAndIsFromBacking = MessageRecorder<(Backing, Project, Bool)>()
  private let emptyStateIsVisible = MessageRecorder<Bool>()
  private let emptyStateMessage = MessageRecorder<String>()
  private let goToBackingProjectParam = MessageRecorder<Param>()
  private let goToBackingBackingParam = MessageRecorder<Param?>()
  private let goToPledgeManagementViewPledge = MessageRecorder<String>()
  private let goToProject = MessageRecorder<Project>()
  private let goToRefTag = MessageRecorder<RefTag>()
  private let messages = MessageRecorder<[Message]>()
  private let participantPreviouslyBlocked = MessageRecorder<Bool>()
  private let presentMessageDialog = MessageRecorder<MessageThread>()
  private let project = MessageRecorder<Project>()
  private let replyButtonIsEnabled = MessageRecorder<Bool>()
  private let successfullyMarkedAsRead = MessageRecorder<()>()
  private let didBlockUser = MessageRecorder<()>()
  private let didBlockUserError = MessageRecorder<()>()

  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated {
      self.vm.onBacking = { [weak self] in self?.backingAndProjectAndIsFromBacking.values.append(($0, $1, $2)) }
      self.vm.onEmptyState = { [weak self] visible, message in
        self?.emptyStateIsVisible.values.append(visible)
        self?.emptyStateMessage.values.append(message)
      }
      self.vm.onBackingNavigation = { [weak self] params in
        self?.goToBackingProjectParam.values.append(params.projectParam)
        self?.goToBackingBackingParam.values.append(params.backingParam)
      }
      self.vm.onPledgeManagement = { [weak self] in self?.goToPledgeManagementViewPledge.values.append($0) }
      self.vm.onProjectNavigation = { [weak self] project, refTag in
        self?.goToProject.values.append(project)
        self?.goToRefTag.values.append(refTag)
      }
      self.vm.onMessages = { [weak self] in self?.messages.values.append($0) }
      self.vm.onParticipantBlocked = { [weak self] in self?.participantPreviouslyBlocked.values.append($0) }
      self.vm.onReply = { [weak self] thread, _ in self?.presentMessageDialog.values.append(thread) }
      self.vm.onProject = { [weak self] in self?.project.values.append($0) }
      self.vm.onReplyEnabled = { [weak self] in self?.replyButtonIsEnabled.values.append($0) }
      self.vm.onMarkedRead = { [weak self] in self?.successfullyMarkedAsRead.values.append(()) }
      self.vm.onBlockSuccess = { [weak self] in self?.didBlockUser.values.append(()) }
      self.vm.onBlockError = { [weak self] in self?.didBlockUserError.values.append(()) }

      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
    }
  }

  func testOutputs_ConfiguredWithThread() async {
    let messageThread = MessageThread.template

    self.vm.configureWith(data: .left(messageThread))
    self.vm.viewDidLoad()

    await self.settleMessaging()

    self.project.assertValues([messageThread.project])
    self.backingAndProjectAndIsFromBacking.assertValueCount(1)
    self.messages.assertValueCount(1)
  }

  func testOutputs_ConfiguredWithThread_AndBacking() async {
    let messageThread = MessageThread.template

    self.vm.configureWith(data: .left(messageThread))
    self.vm.viewDidLoad()

    await self.settleMessaging()

    self.project.assertValues([messageThread.project])
    self.backingAndProjectAndIsFromBacking.assertValueCount(1)
    self.messages.assertValueCount(1)
  }

  func testOutputs_ConfiguredWithProject() async {
    let project = Project.template |> Project.lens.id .~ 42
    let backing = Backing.template

    let messageThread = .template
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))
      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.project.assertValues([project])
      self.backingAndProjectAndIsFromBacking.assertValueCount(1)
      self.messages.assertValueCount(1)
    }
  }

  func testOutputs_ConfiguredWithProject_Error() async {
    let project = Project.template |> Project.lens.id .~ 42
    let backing = Backing.template

    let errorUnknown = ErrorEnvelope(
      errorMessages: ["Something went wrong yo."],
      ksrCode: .UnknownCode,
      httpCode: 400,
      exception: nil
    )

    let apiService = MockService(fetchMessageThreadResult: Result.failure(errorUnknown))

    await withEnvironment(apiService: apiService, currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))
      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.project.assertValues([project])
      self.backingAndProjectAndIsFromBacking.assertValueCount(0)
      self.messages.assertValueCount(0)
    }
  }

  func testOutputs_ConfiguredWithProject_AndBacking() async {
    let project = Project.template |> Project.lens.id .~ 42
    let backing = Backing.template
    let messageThread = .template
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))
      self.vm.viewWillAppear()
      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.project.assertValues([project])
      self.backingAndProjectAndIsFromBacking.assertValueCount(1)
      self.messages.assertValueCount(1)
    }
  }

  func testGoToProject() async {
    let project = Project.template |> Project.lens.id .~ 42
    let backing = Backing.template

    self.vm.configureWith(data: .right((project: project, backing: backing)))
    self.vm.viewDidLoad()

    await self.settleMessaging()

    self.vm.projectBannerTapped()

    self.goToProject.assertValues([project])
    self.goToRefTag.assertValues([.messageThread])
  }

  func testGoToBacking_CurrentUserIsBacker() async {
    let project = Project.template
      |> Project.lens.id .~ 42
      |> Project.lens.personalization.isBacking .~ true
    let backing = Backing.template
    let currentUser = User.template
      |> \.id .~ 42
    let messageThread = .template
      |> MessageThread.lens.backing .~ backing
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: currentUser) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.backingInfoPressed()

      self.goToBackingProjectParam.assertValues([.slug(project.slug)])
      self.goToBackingBackingParam.assertValues([.id(backing.id)])
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()
    }
  }

  func testGoToBacking_CurrentUserIsNotBacker() async {
    let project = Project.template
      |> Project.lens.id .~ 42
    let backing = Backing.template
    let currentUser = User.template
      |> \.id .~ 42
    let messageThread = .template
      |> MessageThread.lens.backing .~ backing
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: currentUser) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.backingInfoPressed()

      self.goToBackingProjectParam.assertValues([.slug(project.slug)])
      self.goToBackingBackingParam.assertValues([.id(backing.id)])
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()
    }
  }

  func testGoToPledgeManagementWebview_CurrentUserIsBacker() async {
    let project = Project.template
      |> Project.lens.id .~ 42
      |> Project.lens.personalization.isBacking .~ true
    let backing = Backing.templateMadeWithPledgeManagment
    let currentUser = User.template
      |> \.id .~ 42
    let messageThread = .template
      |> MessageThread.lens.backing .~ backing
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    let backingDetailsPageURL = backing.backingDetailsPageRoute

    await withEnvironment(apiService: apiService, currentUser: currentUser) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.vm.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.backingInfoPressed()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertLastValue(backingDetailsPageURL)
    }
  }

  func testReplyFlow_participantIsNotBlocked() async {
    let project = Project.template
      |> Project.lens.id .~ 42
      |> \.creator.isBlocked .~ false
    let backing = Backing.template
    let messageThread = .template
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.replyButtonIsEnabled.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear()

      self.messages.assertValueCount(0)
      self.participantPreviouslyBlocked.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([])
      self.emptyStateIsVisible.assertValues([false])

      await self.settleMessaging()

      self.messages.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([true])
      self.emptyStateIsVisible.assertValues([false], "Empty state does not emit again.")

      self.vm.replyButtonPressed()

      self.presentMessageDialog.assertValueCount(1)

      self.vm.messageSent(Message.template)

      await self.settleMessaging()

      self.messages.assertValueCount(2)
    }
  }

  func testReplyFlow_participantIsBlocked() async {
    let project = Project.template
      |> Project.lens.id .~ 42
      |> \.creator.isBlocked .~ true
    let backing = Backing.template
    let messageThread = .template
      |> MessageThread.lens.project .~ project
      |> MessageThread.lens.participant .~ .template

    let apiService = MockService(fetchMessageThreadResult: Result.success(messageThread))

    await withEnvironment(apiService: apiService, currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.replyButtonIsEnabled.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear()

      self.messages.assertValueCount(0)
      self.participantPreviouslyBlocked.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([])
      self.emptyStateIsVisible.assertValues([false])

      await self.settleMessaging()

      self.messages.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([false])
      self.emptyStateIsVisible.assertValues([false], "Empty state does not emit again.")
    }
  }

  func testParticipantPreviouslyBlockedFlow_True() async {
    let creator = User.projectCreator
      |> \.isBlocked .~ true

    let project = Project.template
      |> Project.lens.id .~ 42
      |> Project.lens.creator .~ creator

    await withEnvironment(currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: Backing.template)))

      self.participantPreviouslyBlocked.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear()

      await self.settleMessaging()

      self.participantPreviouslyBlocked.assertValues([true])
    }
  }

  func testDidBlockUser_EmitsOnSuccess() async {
    let envelope = EmptyResponseEnvelope()

    await withEnvironment(apiService: MockService(blockUserResult: .success(envelope)), currentUser: .template) {
      self.vm.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.blockUser(id: "\(User.template.id)")

      await self.settleMessaging()

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
      self.vm.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.blockUser(id: "\(User.template.id)")

      await self.settleMessaging()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(1)
    }
  }

  func testParticipantPreviouslyBlockedFlow_False() async {
    let creator = User.projectCreator
      |> \.id .~ 20
      |> \.isBlocked .~ false

    let project = Project.template
      |> Project.lens.id .~ 42
      |> Project.lens.creator .~ creator

    await withEnvironment(currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: Backing.template)))

      self.participantPreviouslyBlocked.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear()

      await self.settleMessaging()

      self.participantPreviouslyBlocked.assertValues([false])
    }
  }

  func testTrackUserBlockedFromMessage_EventsEmitted() async {
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
      self.vm.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.viewDidLoad()

      self.vm.blockUser(id: "111")

      await self.settleMessaging()

      XCTAssertEqual(segmentClient.events, ["CTA Clicked", "CTA Clicked"])

      XCTAssertEqual(
        segmentClient.properties(forKey: "session_user_is_logged_in", as: Bool.self),
        [true, true]
      )
      XCTAssertEqual(segmentClient.properties(forKey: "user_uid", as: String.self), ["1", "1"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_cta"), ["block_user", "block_user"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_page"), ["messages", "messages"])
      XCTAssertEqual(segmentClient.properties(forKey: "context_type"), ["initiate", "confirm"])
      XCTAssertEqual(segmentClient.properties(forKey: "interaction_target_uid"), ["111", "111"])
    }
  }

  func testMarkAsRead() async {
    self.vm.configureWith(data: .left(MessageThread.template))
    self.vm.viewDidLoad()

    await self.settleMessaging()

    self.successfullyMarkedAsRead.assertValueCount(1)
  }

  func testEmptyStateIsVisibleAndMessage_CurrentUserIsBacker() async {
    let project = .template
      |> Project.lens.id .~ 42
      |> Project.lens.personalization.isBacking .~ true
      |> Project.lens.creator .. User.lens.id .~ 20

    let backing = Backing.template

    await withEnvironment(currentUser: .template) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.viewDidLoad()

      self.emptyStateIsVisible.assertValues([false])
      self.emptyStateMessage.assertValues([""])

      await self.settleMessaging()

      self.emptyStateIsVisible.assertValues([false, true])
      self.emptyStateMessage.assertValues(["", Strings.messages_empty_state_message_backer()])
    }
  }

  func testEmptyStateIsVisibleAndMessage_CurrentUserIsCreator() async {
    let creator = User.projectCreator |> \.id .~ 20
    let project = .template
      |> Project.lens.id .~ 42
      |> Project.lens.creator .~ creator
      |> Project.lens.memberData.permissions .~ [.post, .viewPledges, .comment]

    await withEnvironment(currentUser: creator) {
      self.vm.configureWith(data: .right((project: project, backing: .template)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.viewDidLoad()

      self.emptyStateIsVisible.assertValues([false])
      self.emptyStateMessage.assertValues([""])

      await self.settleMessaging()

      self.emptyStateIsVisible.assertValues([false, true])
      self.emptyStateMessage.assertValues(["", Strings.messages_empty_state_message_creator()])
    }
  }

  func testEmptyStateIsVisibleAndMessage_CurrentUserIsCollaboratorAndBacker() async {
    let collaborator = User.backer |> \.id .~ 20
    let project = .template
      |> Project.lens.creator .. User.lens.id .~ 40
      |> Project.lens.memberData.permissions .~ [.viewPledges]
    let backing = .template
      |> Backing.lens.backer .~ collaborator

    await withEnvironment(currentUser: collaborator) {
      self.vm.configureWith(data: .right((project: project, backing: backing)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.viewDidLoad()

      self.emptyStateIsVisible.assertValues([false])
      self.emptyStateMessage.assertValues([""])

      await self.settleMessaging()

      self.emptyStateIsVisible.assertValues([false, true])
      self.emptyStateMessage.assertValues(["", Strings.messages_empty_state_message_backer()])
    }
  }

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    await self.discussion.waitForMutations()
    try await super.tearDown()
  }

  private func settleMessaging() async {
    // Await screen-owned requests and the operations they start.
    await self.vm.waitForThread()
    await self.vm.waitForBacking()
    await self.feature.waitForOperations()
    await self.discussion.waitForMutations()
    await self.vm.waitForBlock()
    // Thread delivery can start a backing lookup and read-status command.
    await self.feature.waitForOperations()
    await self.vm.waitForMarkRead()
  }
}

private final class MessageRecorder<Value> {
  var values: [Value] = []
  var lastValue: Value? { self.values.last }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
}
private extension MessageRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, message, file: file, line: line)
  }
}
