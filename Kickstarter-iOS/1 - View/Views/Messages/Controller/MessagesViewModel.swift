import Foundation
import Foundation
import KsApi
import Prelude
import ReactiveSwift

@MainActor
public protocol MessagesViewModelInputs {
  /// Call when the backing button is pressed.
  func backingInfoPressed()

  /// Call when block user is tapped
  func blockUser(id: String)

  /// Configures the view model with either a message thread or a project and a backing.
  func configureWith(data: Either<MessageThread, (project: Project, backing: Backing)>)

  /// Call when the message dialog has told us that a message was successfully posted.
  func messageSent(_ message: Message)

  /// Call when the project banner is tapped.
  func projectBannerTapped()

  /// Call when the reply button is pressed.
  func replyButtonPressed()

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when the view will appear.
  func viewWillAppear()
}

@MainActor
public protocol MessagesViewModelOutputs {
  /**
   Emits a Backing and Project that can be used to populate the BackingCell.
   The boolean tells if navigation to this screen occurred from the backing info screen.
   */
  var backingAndProjectAndIsFromBacking: Signal<(Backing, Project, Bool), Never> { get }

  /// Emits a boolean that determines if the empty state is visible and a message to display.
  var emptyStateIsVisibleAndMessageToUser: Signal<(Bool, String), Never> { get }

  /// Emits when we should go to the backing screen.
  var goToBacking: Signal<ManagePledgeViewParamConfigData, Never> { get }

  /// Emits when we should go to the Pledge Management View Pledge webview.
  var goToPledgeManagementViewPledge: Signal<String, Never> { get }

  /// Emits a list of messages to be displayed.
  var messages: Signal<[Message], Never> { get }

  /// Emits a bool whether the message participant has previously been blocked on viewWillAppear
  var participantPreviouslyBlocked: Signal<Bool, Never> { get }

  /// Emits the project we are viewing the messages for.
  var project: Signal<Project, Never> { get }

  /// Emits a bool whether the reply button is enabled.
  var replyButtonIsEnabled: Signal<Bool, Never> { get }

}

@MainActor
public protocol MessagesViewModelType {
  var inputs: MessagesViewModelInputs { get }
  var outputs: MessagesViewModelOutputs { get }
}

@MainActor
public final class MessagesViewModel: MessagesViewModelType, MessagesViewModelInputs,
  MessagesViewModelOutputs {
  private let feature: MessagingFeature
  private let discussion: DiscussionFeature
  private var blockTask: Task<Void, Never>?
  private var threadTask: Task<Void, Never>?
  private var threadVersion = UUID()
  private let threadPipe = Signal<MessageThreadEnvelope?, Never>.pipe()
  private let backingPipe = Signal<(Backing, Project, Bool), Never>.pipe()
  private var backingTask: Task<Void, Never>?
  private var backingVersion = UUID()
  private var markReadTask: Task<Void, Never>?
  private var markReadVersion = UUID()
  var onMarkedRead: (() -> Void)?
  private var blockVersion = UUID()
  private var latestBlockedID: String?
  var onBlockSuccess: (() -> Void)?
  var onBlockError: (() -> Void)?
  public convenience init() {
    self.init(feature: AppModel.shared.messagingFeature, discussion: AppModel.shared.discussionFeature)
  }
  public init(feature: MessagingFeature, discussion: DiscussionFeature) {
    self.feature = feature
    self.discussion = discussion
    let configData = self.configData.signal.skipNil()
      .takeWhen(self.viewDidLoadProperty.signal)

    let configBacking = configData.map { $0.right?.backing }

    let configThread = configData.map { $0.left }
      .skipNil()

    let currentUser = self.viewDidLoadProperty.signal
      .map { AppEnvironment.current.currentUser }
      .skipNil()

    self.project = configData
      .map {
        switch $0 {
        case let .left(thread):
          return thread.project
        case let .right((project, _)):
          return project
        }
      }

    let backingOrThread = Signal.merge(
      configBacking.skipNil().map(Either.left),
      configThread.map(Either.right)
    )

    let threadRequests = Signal.merge(
      backingOrThread,
      backingOrThread.takeWhen(self.messageSentProperty.signal)
    )
    let messageThreadEnvelopeEvent = self.threadPipe.output
    let messageThreadEnvelope = messageThreadEnvelopeEvent.skipNil()

    let participant = messageThreadEnvelope.map { $0.messageThread.participant }

    let backingRequests = Signal.combineLatest(
      configBacking, self.project, participant, currentUser, messageThreadEnvelope
    )
    self.backingAndProjectAndIsFromBacking = self.backingPipe.output

    let projectAndBacking = self.backingAndProjectAndIsFromBacking.map { backing, project, _ -> (
      Project,
      Backing
    ) in
      (project, backing)
    }

    self.viewPledgeUseCase = .init(with: projectAndBacking)

    self.messages = messageThreadEnvelope
      .map { $0.messages }
      .sort { $0.id > $1.id }

    self.emptyStateIsVisibleAndMessageToUser = Signal.merge(
      self.viewDidLoadProperty.signal.mapConst((false, "")),
      Signal.combineLatest(
        messageThreadEnvelopeEvent.filter(isNil),
        configBacking.skipNil(),
        self.project
      )
      .map { _, backing, project in
        let isCreatorOrCollaborator = !project.memberData.permissions.isEmpty
          && backing.backer?.id != AppEnvironment.current.currentUser?.id
        let message = isCreatorOrCollaborator
          ? Strings.messages_empty_state_message_creator()
          : Strings.messages_empty_state_message_backer()
        return (true, message)
      }
    )

    self.participantPreviouslyBlocked = self.project
      .map { $0.creator.isBlocked }
      .takeWhen(self.viewWillAppearProperty.signal)

    self.replyButtonIsEnabled = Signal.combineLatest(
      self.messages.map { !$0.isEmpty },
      self.participantPreviouslyBlocked
    )
    .map { messages, isBlocked in
      messages && !isBlocked
    }

    threadRequests.observeValues { [weak self] in self?.loadThread($0) }
    backingRequests.observeValues { [weak self] backing, project, participant, currentUser, envelope in
      self?.loadBacking(backing, project: project, participant: participant, currentUser: currentUser, envelope: envelope)
    }
    self.project.observeValues { [weak self] project in
      guard let self else { return }
      self.latestProject = project
      if let id = self.latestBlockedID { self.trackBlockedUser(id: id, project: project, confirmed: false) }
    }
    messageThreadEnvelope.observeValues { [weak self] in
      self?.latestThread = $0.messageThread
      self?.markRead($0.messageThread)
    }

  }

  private func loadThread(_ route: Either<Backing, MessageThread>) {
    self.threadTask?.cancel()
    let version = UUID()
    self.threadVersion = version
    let feature = self.feature
    let session = feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.threadTask = Task { [weak self] in
      defer { if let self, self.threadVersion == version { self.threadTask = nil } }
      do {
        let result: MessageThreadEnvelope?
        switch route {
        case let .left(backing): result = try await feature.thread(backing: backing)
        case let .right(thread): result = try await feature.thread(id: thread.id)
        }
        if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
        else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        guard let self, self.threadVersion == version,
              session.isCurrent(userID: userID, generation: generation) else { return }
        self.threadPipe.input.send(value: result)
      } catch {
        // The existing screen leaves failed reads silent and permits a later reload.
      }
    }
  }
  func waitForThread() async { await self.threadTask?.value }

  private func loadBacking(
    _ existing: Backing?, project: Project, participant: User, currentUser: User,
    envelope: MessageThreadEnvelope
  ) {
    self.backingTask?.cancel()
    let version = UUID()
    self.backingVersion = version
    if let existing {
      self.backingTask = nil
      self.backingPipe.input.send(value: (existing, project, true))
      return
    }
    let feature = self.feature
    let session = feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let user = project.personalization.isBacking == .some(true) ? currentUser : participant
    self.backingTask = Task { [weak self] in
      defer { if let self, self.backingVersion == version { self.backingTask = nil } }
      do {
        let backing = try await feature.backing(id: envelope.messageThread.backing?.id, project: project, user: user)
        try Task.checkCancellation()
        guard let self, self.backingVersion == version,
              session.isCurrent(userID: userID, generation: generation) else { return }
        self.backingPipe.input.send(value: (backing, project, false))
      } catch {
        // Preserve the screen's existing silent backing-lookup failure.
      }
    }
  }
  func waitForBacking() async { await self.backingTask?.value }

  private func markRead(_ thread: MessageThread) {
    self.markReadTask?.cancel()
    let version = UUID()
    self.markReadVersion = version
    let session = self.feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let command = self.feature.requestMarkRead(thread)
    self.markReadTask = Task { [weak self] in
      guard case .success = await command.result, !Task.isCancelled,
            let self, self.markReadVersion == version,
            session.isCurrent(userID: userID, generation: generation) else { return }
      self.onMarkedRead?()
      self.markReadTask = nil
    }
  }
  func waitForMarkRead() async { await self.markReadTask?.value }

  deinit {
    self.blockTask?.cancel()
    self.markReadTask?.cancel()
    self.threadTask?.cancel()
    self.backingTask?.cancel()
  }

  public func backingInfoPressed() {
    self.viewPledgeUseCase.goToPledgeViewTapped()
  }

  public func blockUser(id: String) {
    self.latestBlockedID = id
    if let project = self.latestProject { self.trackBlockedUser(id: id, project: project, confirmed: false) }
    self.blockTask?.cancel()
    let version = UUID()
    self.blockVersion = version
    let session = self.feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let request = self.discussion.requestBlockUser(id: id)
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.blockTask = Task { [weak self] in
      let outcome = await request.result
      do {
        if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
        else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
      } catch { return }
      guard let self, self.blockVersion == version, session.isCurrent(userID: userID, generation: generation) else { return }
      switch outcome {
      case .success:
        NotificationCenter.default.post(.init(name: .ksr_blockedUser))
        self.onBlockSuccess?()
        if let project = self.latestProject, let currentID = self.latestBlockedID {
          self.trackBlockedUser(id: currentID, project: project, confirmed: true)
        }
      case .failure(let error):
        if !(error is CancellationError) { self.onBlockError?() }
      }
      self.blockTask = nil
    }
  }
  private func trackBlockedUser(id: String, project: Project, confirmed: Bool) {
    AppEnvironment.current.ksrAnalytics.trackBlockedUser(
      project, page: .messages, typeContext: confirmed ? .confirm : .initiate, targetUserId: id
    )
  }
  func waitForBlock() async { await self.blockTask?.value }

  private let configData = MutableProperty<Either<MessageThread, (project: Project, backing: Backing)>?>(nil)
  public func configureWith(data: Either<MessageThread, (project: Project, backing: Backing)>) {
    self.configData.value = data
  }

  private let messageSentProperty = MutableProperty<Message?>(nil)
  public func messageSent(_ message: Message) {
    self.messageSentProperty.value = message
  }

  var onProjectNavigation: ((Project, RefTag) -> Void)?
  var onReply: ((MessageThread, KSRAnalytics.MessageDialogContext) -> Void)?
  private var latestProject: Project?
  private var latestThread: MessageThread?
  public func projectBannerTapped() {
    if let project = self.latestProject { self.onProjectNavigation?(project, .messageThread) }
  }
  public func replyButtonPressed() {
    if let thread = self.latestThread { self.onReply?(thread, .messages) }
  }

  private let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  private let viewWillAppearProperty = MutableProperty(())
  public func viewWillAppear() {
    self.viewWillAppearProperty.value = ()
  }

  private let viewPledgeUseCase: ViewPledgeUseCase

  public let backingAndProjectAndIsFromBacking: Signal<(Backing, Project, Bool), Never>
  public let emptyStateIsVisibleAndMessageToUser: Signal<(Bool, String), Never>
  public let messages: Signal<[Message], Never>
  public let participantPreviouslyBlocked: Signal<Bool, Never>
  public let project: Signal<Project, Never>
  public let replyButtonIsEnabled: Signal<Bool, Never>

  public var goToBacking: Signal<ManagePledgeViewParamConfigData, Never> {
    self.viewPledgeUseCase.goToNativePledgeView
  }

  public var goToPledgeManagementViewPledge: Signal<String, Never> {
    self.viewPledgeUseCase.goToPledgeManagementPledgeView
  }

  public var inputs: MessagesViewModelInputs { return self }
  public var outputs: MessagesViewModelOutputs { return self }
}
