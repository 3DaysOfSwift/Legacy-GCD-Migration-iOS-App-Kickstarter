import Foundation
import KsApi
import Prelude

@MainActor
public final class MessagesViewModel {
  var onBacking: ((Backing, Project, Bool) -> Void)?
  var onEmptyState: ((Bool, String) -> Void)?
  var onMessages: (([Message]) -> Void)?
  var onParticipantBlocked: ((Bool) -> Void)?
  var onProject: ((Project) -> Void)?
  var onReplyEnabled: ((Bool) -> Void)?
  private var configuredData: Either<MessageThread, (project: Project, backing: Backing)>?
  private var activeRoute: Either<Backing, MessageThread>?
  private var activeBacking: Backing?
  private var activeUser: User?
  private var latestMessagesExist: Bool?
  private var latestBlocked: Bool?
  private let feature: MessagingFeature
  private let discussion: DiscussionFeature
  private var blockTask: Task<Void, Never>?
  private var threadTask: Task<Void, Never>?
  private var threadVersion = UUID()
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
  }

  private func receivedThread(_ envelope: MessageThreadEnvelope?) {
    guard let envelope else {
      if let backing = self.activeBacking, let project = self.latestProject {
        let creator = !project.memberData.permissions.isEmpty && backing.backer?.id != AppEnvironment.current.currentUser?.id
        self.onEmptyState?(true, creator ? Strings.messages_empty_state_message_creator() : Strings.messages_empty_state_message_backer())
      }
      return
    }
    let messages = envelope.messages.sorted { $0.id > $1.id }
    self.latestMessagesExist = !messages.isEmpty
    self.onMessages?(messages)
    self.publishReplyEnabled()
    self.latestThread = envelope.messageThread
    self.markRead(envelope.messageThread)
    if let project = self.latestProject, let currentUser = self.activeUser {
      self.loadBacking(self.activeBacking, project: project, participant: envelope.messageThread.participant,
                       currentUser: currentUser, envelope: envelope)
    }
  }
  private func publishReplyEnabled() {
    if let messages = self.latestMessagesExist, let blocked = self.latestBlocked { self.onReplyEnabled?(messages && !blocked) }
  }
  private func receivedBacking(_ backing: Backing, project: Project, isFromBacking: Bool) {
    self.latestProjectBacking = (project, backing)
    self.onBacking?(backing, project, isFromBacking)
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
        self.receivedThread(result)
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
      self.receivedBacking(existing, project: project, isFromBacking: true)
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
        self.receivedBacking(backing, project: project, isFromBacking: false)
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

  var onBackingNavigation: ((ManagePledgeViewParamConfigData) -> Void)?
  var onPledgeManagement: ((String) -> Void)?
  private var latestProjectBacking: (Project, Backing)?
  public func backingInfoPressed() {
    guard let (project, backing) = self.latestProjectBacking else { return }
    switch pledgeDestination(project: project, backing: backing) {
    case let .native(params): self.onBackingNavigation?(params)
    case let .web(url): self.onPledgeManagement?(url)
    }
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

  public func configureWith(data: Either<MessageThread, (project: Project, backing: Backing)>) {
    self.configuredData = data
  }
  public func messageSent(_ message: Message) {
    if let route = self.activeRoute { self.loadThread(route) }
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

  public func viewDidLoad() {
    self.onEmptyState?(false, "")
    guard let data = self.configuredData else { return }
    let project: Project
    switch data {
    case let .left(thread): project = thread.project; self.activeBacking = nil; self.activeRoute = .right(thread)
    case let .right(value): project = value.project; self.activeBacking = value.backing; self.activeRoute = .left(value.backing)
    }
    self.activeUser = AppEnvironment.current.currentUser
    self.latestProject = project
    self.onProject?(project)
    if let id = self.latestBlockedID { self.trackBlockedUser(id: id, project: project, confirmed: false) }
    if let route = self.activeRoute { self.loadThread(route) }
  }
  public func viewWillAppear() {
    guard let project = self.latestProject else { return }
    self.latestBlocked = project.creator.isBlocked
    self.onParticipantBlocked?(project.creator.isBlocked)
    self.publishReplyEnabled()
  }
}
