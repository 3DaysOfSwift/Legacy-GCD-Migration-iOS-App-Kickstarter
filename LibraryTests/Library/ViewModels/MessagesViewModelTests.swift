@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
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
  private lazy var vm: MessagesViewModelType = MessagesViewModel(feature: self.feature, discussion: self.discussion)

  private let backingAndProjectAndIsFromBacking = TestObserver<(Backing, Project, Bool), Never>()
  private let emptyStateIsVisible = TestObserver<Bool, Never>()
  private let emptyStateMessage = TestObserver<String, Never>()
  private let goToBackingProjectParam = TestObserver<Param, Never>()
  private let goToBackingBackingParam = TestObserver<Param?, Never>()
  private let goToPledgeManagementViewPledge = TestObserver<String, Never>()
  private let goToProject = TestObserver<Project, Never>()
  private let goToRefTag = TestObserver<RefTag, Never>()
  private let messages = TestObserver<[Message], Never>()
  private let participantPreviouslyBlocked = TestObserver<Bool, Never>()
  private let presentMessageDialog = TestObserver<MessageThread, Never>()
  private let project = TestObserver<Project, Never>()
  private let replyButtonIsEnabled = TestObserver<Bool, Never>()
  private let successfullyMarkedAsRead = TestObserver<(), Never>()
  private let didBlockUser = TestObserver<(), Never>()
  private let didBlockUserError = TestObserver<(), Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.backingAndProjectAndIsFromBacking.observe(self.backingAndProjectAndIsFromBacking.observer)
      self.vm.outputs.emptyStateIsVisibleAndMessageToUser.map { $0.0 }
        .observe(self.emptyStateIsVisible.observer)
      self.vm.outputs.emptyStateIsVisibleAndMessageToUser.map { $0.1 }.observe(self.emptyStateMessage.observer)
      self.vm.outputs.goToBacking.map(first).observe(self.goToBackingProjectParam.observer)
      self.vm.outputs.goToBacking.map(second).observe(self.goToBackingBackingParam.observer)
      self.vm.outputs.goToPledgeManagementViewPledge.observe(self.goToPledgeManagementViewPledge.observer)
      self.vm.outputs.goToProject.map { $0.0 }.observe(self.goToProject.observer)
      self.vm.outputs.goToProject.map { $0.1 }.observe(self.goToRefTag.observer)
      self.vm.outputs.messages.observe(self.messages.observer)
      self.vm.outputs.participantPreviouslyBlocked.observe(self.participantPreviouslyBlocked.observer)
      self.vm.outputs.presentMessageDialog.map { $0.0 }.observe(self.presentMessageDialog.observer)
      self.vm.outputs.project.observe(self.project.observer)
      self.vm.outputs.replyButtonIsEnabled.observe(self.replyButtonIsEnabled.observer)
      self.vm.outputs.successfullyMarkedAsRead.observe(self.successfullyMarkedAsRead.observer)
      self.vm.outputs.didBlockUser.observe(self.didBlockUser.observer)
      self.vm.outputs.didBlockUserError.observe(self.didBlockUserError.observer)

      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: User.template))
    }
  }

  func testOutputs_ConfiguredWithThread() async {
    let messageThread = MessageThread.template

    self.vm.inputs.configureWith(data: .left(messageThread))
    self.vm.inputs.viewDidLoad()

    await self.settleMessaging()

    self.project.assertValues([messageThread.project])
    self.backingAndProjectAndIsFromBacking.assertValueCount(1)
    self.messages.assertValueCount(1)
  }

  func testOutputs_ConfiguredWithThread_AndBacking() async {
    let messageThread = MessageThread.template

    self.vm.inputs.configureWith(data: .left(messageThread))
    self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))
      self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))
      self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))
      self.vm.inputs.viewWillAppear()
      self.vm.inputs.viewDidLoad()

      await self.settleMessaging()

      self.project.assertValues([project])
      self.backingAndProjectAndIsFromBacking.assertValueCount(1)
      self.messages.assertValueCount(1)
    }
  }

  func testGoToProject() async {
    let project = Project.template |> Project.lens.id .~ 42
    let backing = Backing.template

    self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))
    self.vm.inputs.viewDidLoad()

    await self.settleMessaging()

    self.vm.inputs.projectBannerTapped()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.vm.inputs.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.inputs.backingInfoPressed()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.vm.inputs.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.inputs.backingInfoPressed()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.vm.inputs.viewDidLoad()

      await self.settleMessaging()

      self.goToBackingProjectParam.assertDidNotEmitValue()
      self.goToBackingBackingParam.assertDidNotEmitValue()
      self.goToPledgeManagementViewPledge.assertDidNotEmitValue()

      self.vm.inputs.backingInfoPressed()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.replyButtonIsEnabled.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      self.messages.assertValueCount(0)
      self.participantPreviouslyBlocked.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([])
      self.emptyStateIsVisible.assertValues([false])

      await self.settleMessaging()

      self.messages.assertValueCount(1)
      self.replyButtonIsEnabled.assertValues([true])
      self.emptyStateIsVisible.assertValues([false], "Empty state does not emit again.")

      self.vm.inputs.replyButtonPressed()

      self.presentMessageDialog.assertValueCount(1)

      self.vm.inputs.messageSent(Message.template)

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.replyButtonIsEnabled.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: Backing.template)))

      self.participantPreviouslyBlocked.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

      await self.settleMessaging()

      self.participantPreviouslyBlocked.assertValues([true])
    }
  }

  func testDidBlockUser_EmitsOnSuccess() async {
    let envelope = EmptyResponseEnvelope()

    await withEnvironment(apiService: MockService(blockUserResult: .success(envelope)), currentUser: .template) {
      self.vm.inputs.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.inputs.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.inputs.blockUser(id: "\(User.template.id)")

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
      self.vm.inputs.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.inputs.viewDidLoad()

      self.didBlockUser.assertValueCount(0)
      self.didBlockUserError.assertValueCount(0)

      self.vm.inputs.blockUser(id: "\(User.template.id)")

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: Backing.template)))

      self.participantPreviouslyBlocked.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear()

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
      self.vm.inputs.configureWith(data: .right((project: .template, backing: .template)))

      self.vm.inputs.viewDidLoad()

      self.vm.inputs.blockUser(id: "111")

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
    self.vm.inputs.configureWith(data: .left(MessageThread.template))
    self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: .template)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

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
      self.vm.inputs.configureWith(data: .right((project: project, backing: backing)))

      self.emptyStateIsVisible.assertValueCount(0)

      self.vm.inputs.viewDidLoad()

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
    // Start debounced requests, await native work, then deliver the presentation delay.
    await self.scheduler.advance()
    await self.feature.waitForOperations()
    await self.discussion.waitForMutations()
    await self.scheduler.advance()
    // Thread delivery starts backing lookup and read-status commands.
    await self.feature.waitForOperations()
    await self.scheduler.advance()
  }
}
