import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol MessagingProvider {
  func page(mailbox: Mailbox, project: Project?, cursor: String?) async throws -> MessageThreadsEnvelope
  func search(query: String, project: Project?) async throws -> MessageThreadsEnvelope
  func thread(id: Int) async throws -> MessageThreadEnvelope
  func thread(backing: Backing) async throws -> MessageThreadEnvelope?
  func backing(id: Int) async throws -> Backing
  func backing(project: Project, user: User) async throws -> Backing
  func markRead(_ thread: MessageThread) async throws -> MessageThread
  func send(body: String, subject: MessageSubject) async throws -> Message
}

@MainActor
public struct AsyncMessagingProvider: MessagingProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func page(mailbox: Mailbox, project: Project?, cursor: String?) async throws -> MessageThreadsEnvelope {
    try await self.service.messageThreadsPage(mailbox: mailbox, project: project, cursor: cursor)
  }
  public func search(query: String, project: Project?) async throws -> MessageThreadsEnvelope {
    try await self.service.messageSearch(query: query, project: project)
  }
  public func thread(id: Int) async throws -> MessageThreadEnvelope {
    try await self.service.messageThread(id: id)
  }
  public func thread(backing: Backing) async throws -> MessageThreadEnvelope? {
    try await self.service.messageThread(backing: backing)
  }
  public func backing(id: Int) async throws -> Backing {
    try await self.service.projectDetailsBacking(id: id).backing
  }
  public func backing(project: Project, user: User) async throws -> Backing {
    try await self.service.messageBacking(project: project, user: user)
  }
  public func markRead(_ thread: MessageThread) async throws -> MessageThread {
    try await self.service.readMessageThread(thread)
  }
  public func send(body: String, subject: MessageSubject) async throws -> Message {
    try await self.service.submitMessage(body: body, subject: subject)
  }
}

/// Owns mailbox history, screen reads, and admitted message mutations.
/// Reactive outputs only adapt these commands to the existing UIKit screens.
@MainActor
public final class MessagingFeature {
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any MessagingProvider
  private let sleep: (TimeInterval) async throws -> Void
  private struct Session: Hashable {
    let userID: Int?
    let generation: Int
  }
  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private func requireCurrent(_ session: Session) throws {
    try Task.checkCancellation()
    guard self.session == session else { throw CancellationError() }
  }

  public init(
    sessionFeature: SessionFeature, makeProvider: @escaping () -> any MessagingProvider,
    sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
      if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }
  ) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
    self.sleep = sleep
  }

  public struct MailboxSnapshot {
    public fileprivate(set) var threads: [MessageThread] = []
    public fileprivate(set) var isLoading = false
    public fileprivate(set) var error: ErrorEnvelope?
  }
  private final class MailboxRoute {
    let mailbox: Mailbox
    let project: Project?
    let session: Session
    var snapshot = MailboxSnapshot()
    var cursor: String?
    var request: (id: UUID, task: Task<Void, Never>)?
    init(mailbox: Mailbox, project: Project?, session: Session) {
      self.mailbox = mailbox; self.project = project; self.session = session
    }
  }
  private var mailboxes: [UUID: MailboxRoute] = [:]
  private let pagePipe = Signal<(UUID, [MessageThread]), Never>.pipe()
  private let loadingPipe = Signal<(UUID, Bool), Never>.pipe()
  public var pages: Signal<(UUID, [MessageThread]), Never> { self.pagePipe.output }
  public var loading: Signal<(UUID, Bool), Never> { self.loadingPipe.output }
  public func snapshot(route: UUID) -> MailboxSnapshot { self.mailboxes[route]?.snapshot ?? MailboxSnapshot() }

  @discardableResult
  public func requestMailbox(
    route: UUID, mailbox: Mailbox, project: Project?, refresh: Bool = false
  ) -> Task<Void, Never> {
    if !refresh, let existing = self.mailboxes[route], existing.mailbox == mailbox,
       existing.project?.id == project?.id, existing.session == self.session,
       let request = existing.request { return request.task }
    let previous = self.mailboxes[route]
    previous?.request?.task.cancel()
    let state = MailboxRoute(mailbox: mailbox, project: project, session: self.session)
    self.mailboxes[route] = state
    if previous != nil { self.pagePipe.input.send(value: (route, [])) }
    return self.startPage(route: route, state: state, cursor: nil)
  }

  @discardableResult
  public func requestNextPage(route: UUID) -> Task<Void, Never>? {
    guard let state = self.mailboxes[route], state.session == self.session else { return nil }
    if let request = state.request { return request.task }
    guard let cursor = state.cursor else { return nil }
    return self.startPage(route: route, state: state, cursor: cursor)
  }

  private func startPage(route: UUID, state: MailboxRoute, cursor: String?) -> Task<Void, Never> {
    let id = UUID()
    let provider = self.makeProvider()
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    state.snapshot.isLoading = true
    state.snapshot.error = nil
    let task = Task { [weak self, sleep] in
      guard let self else { return }
      defer {
        if self.mailboxes[route]?.request?.id == id {
          state.request = nil
          state.snapshot.isLoading = false
          self.loadingPipe.input.send(value: (route, false))
        }
      }
      do {
        try self.requireCurrent(state.session)
        let envelope = try await provider.page(mailbox: state.mailbox, project: state.project, cursor: cursor)
        try await sleep(delay)
        try self.requireCurrent(state.session)
        guard self.mailboxes[route]?.request?.id == id else { return }
        // Preserve the original concatenation and empty-page sentinel.
        state.cursor = envelope.messageThreads.isEmpty ? nil : envelope.urls.api.moreMessageThreads
        state.snapshot.threads += envelope.messageThreads
        self.pagePipe.input.send(value: (route, state.snapshot.threads))
      } catch {
        guard !Task.isCancelled, self.session == state.session,
              self.mailboxes[route]?.request?.id == id else { return }
        state.snapshot.error = (error as? ErrorEnvelope) ?? .couldNotParseJSON
      }
    }
    state.request = (id, task)
    self.loadingPipe.input.send(value: (route, true))
    return task
  }

  private var readTasks: [UUID: Task<Void, Never>] = [:]
  private var reads: [UUID: (id: UUID, task: Task<Void, Never>)] = [:]

  /// Each screen supplies an independent route. Replacing or clearing a query
  /// cancels that route before the next debounced request is admitted.
  public func cancelRead(route: UUID) {
    self.reads.removeValue(forKey: route)?.task.cancel()
  }

  public func release(route: UUID) {
    self.cancelRead(route: route)
    self.mailboxes.removeValue(forKey: route)?.request?.task.cancel()
  }

  public func reset() {
    for task in self.readTasks.values { task.cancel() }
    for route in self.mailboxes.values { route.request?.task.cancel() }
    self.reads = [:]
    self.mailboxes = [:]
  }

  public func search(query: String, project: Project?) async throws -> [MessageThread] {
    guard !query.isEmpty else { return [] }
    let session = self.session
    try self.requireCurrent(session)
    let value = try await self.makeProvider().search(query: query, project: project)
    try self.requireCurrent(session)
    return value.messageThreads
  }

  public func thread(id: Int) async throws -> MessageThreadEnvelope? {
    let session = self.session
    try self.requireCurrent(session)
    let value = try await self.makeProvider().thread(id: id)
    try self.requireCurrent(session)
    return value
  }

  public func thread(backing: Backing) async throws -> MessageThreadEnvelope? {
    let session = self.session
    try self.requireCurrent(session)
    let value = try await self.makeProvider().thread(backing: backing)
    try self.requireCurrent(session)
    return value
  }

  public func backing(id: Int?, project: Project, user: User) async throws -> Backing {
    let session = self.session
    try self.requireCurrent(session)
    let provider = self.makeProvider()
    let value: Backing
    if let id { value = try await provider.backing(id: id) }
    else { value = try await provider.backing(project: project, user: user) }
    try self.requireCurrent(session)
    return value
  }

  // Typed, route-owned read execution. Disposing presentation cancels the read;
  // providers that ignore cancellation still cannot deliver obsolete results.
  public func readResult<Value>(
    route: UUID, operation: @escaping @MainActor () async throws -> Value
  ) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        self.cancelRead(route: route)
        let id = UUID()
        let task = Task { [weak self] in
          guard let self else { return }
          defer {
            self.readTasks[id] = nil
            if self.reads[route]?.id == id { self.reads[route] = nil }
          }
          do {
            try self.requireCurrent(session)
            let value = try await operation()
            try self.requireCurrent(session)
            guard self.reads[route]?.id == id else { return }
            observer.send(value: value)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session,
                  self.reads[route]?.id == id else { observer.sendInterrupted(); return }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.readTasks[id] = task
        self.reads[route] = (id, task)
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  private struct Destination: Hashable { let id: Int; let isThread: Bool; let session: Session }
  private struct Send {
    let id: UUID
    let body: String
    let task: Task<Message, Error>
  }
  private var sends: [Destination: Send] = [:]
  private var sendTasks: [UUID: Task<Message, Error>] = [:]
  private struct ReadIdentity: Hashable { let threadID: Int; let session: Session }
  private var readWrites: [ReadIdentity: Task<MessageThread, Error>] = [:]

  /// Equivalent pending submissions share the tail command. Distinct bodies
  /// queue in order per destination; failure never retries or blocks the next.
  @discardableResult
  public func requestSend(body: String, subject: MessageSubject) -> Task<Message, Error> {
    let destination: Destination
    switch subject {
    case let .messageThread(thread):
      destination = Destination(id: thread.id, isThread: true, session: self.session)
    case let .project(id, _):
      destination = Destination(id: id, isThread: false, session: self.session)
    }
    let previous = self.sends[destination]
    if let previous, previous.body == body { return previous.task }
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.sendTasks[id] = nil
        if self.sends[destination]?.id == id { self.sends[destination] = nil }
      }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(destination.session)
      do {
        let message = try await provider.send(body: body, subject: subject)
        try self.requireCurrent(destination.session)
        return message
      } catch {
        try self.requireCurrent(destination.session)
        throw error
      }
    }
    self.sends[destination] = Send(id: id, body: body, task: task)
    self.sendTasks[id] = task
    return task
  }

  public func send(body: String, subject: MessageSubject) async throws -> Message {
    try Task.checkCancellation()
    let value = try await self.requestSend(body: body, subject: subject).value
    try Task.checkCancellation()
    return value
  }

  @discardableResult
  public func requestMarkRead(_ thread: MessageThread) -> Task<MessageThread, Error> {
    let key = ReadIdentity(threadID: thread.id, session: self.session)
    if let task = self.readWrites[key] { return task }
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer { self.readWrites[key] = nil }
      try self.requireCurrent(key.session)
      do {
        let value = try await provider.markRead(thread)
        try self.requireCurrent(key.session)
        return value
      } catch {
        try self.requireCurrent(key.session)
        throw error
      }
    }
    self.readWrites[key] = task
    return task
  }

  // Admission is synchronous, so rapid inputs keep their order. Only the
  // observation task is canceled on screen release, never the admitted write.
  /// Guard both values and errors after the existing presentation delay.
  func delayedResult<Value>(_ producer: SignalProducer<Value, ErrorEnvelope>) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return producer.ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .materialize()
      .filter { _ in MainActor.assumeIsolated { self.session == session } }
      .dematerialize()
  }

  func sendResult(body: String, subject: MessageSubject) -> SignalProducer<Message, ErrorEnvelope> {
    self.mutationResult { self.requestSend(body: body, subject: subject) }
  }
  func markReadResult(_ thread: MessageThread) -> SignalProducer<MessageThread, ErrorEnvelope> {
    self.mutationResult { self.requestMarkRead(thread) }
  }
  private func mutationResult<Value>(
    admit: @escaping @MainActor () -> Task<Value, Error>
  ) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else { observer.sendInterrupted(); return }
        let command = admit()
        let observerTask = Task {
          do {
            let value = try await command.value
            try self.requireCurrent(session)
            observer.send(value: value)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session
            else { observer.sendInterrupted(); return }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        lifetime.observeEnded { observerTask.cancel() }
        // Include delivery in deterministic adapter tests.
        let id = UUID()
        self.deliveries[id] = observerTask
        Task { [weak self] in
          await observerTask.value
          self?.deliveries[id] = nil
        }
      }
    }
  }
  private var deliveries: [UUID: Task<Void, Never>] = [:]

  public func waitForOperations() async {
    while !self.readTasks.isEmpty || !self.sendTasks.isEmpty || !self.readWrites.isEmpty || !self.deliveries.isEmpty
      || self.mailboxes.values.contains(where: { $0.request != nil }) {
      for task in Array(self.readTasks.values) { await task.value }
      for route in Array(self.mailboxes.values) { await route.request?.task.value }
      for task in Array(self.sendTasks.values) { _ = await task.result }
      for task in Array(self.readWrites.values) { _ = await task.result }
      for task in Array(self.deliveries.values) { await task.value }
      await Task.yield()
    }
  }
}
