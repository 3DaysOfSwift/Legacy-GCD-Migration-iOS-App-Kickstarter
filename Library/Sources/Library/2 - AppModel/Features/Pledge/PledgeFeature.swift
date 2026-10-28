import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol PledgeProvider {
  func create(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope
  func update(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope
  func cancel(_ input: CancelBackingInput) async throws
  func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing
}

@MainActor
public struct AsyncPledgeProvider: PledgeProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func create(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope {
    try await self.service.submitPledge(input)
  }
  public func update(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    try await self.service.revisePledge(input)
  }
  public func cancel(_ input: CancelBackingInput) async throws { try await self.service.cancelPledge(input) }
  public func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    try await self.service.markPledgeReceived(projectID: projectID, userID: userID, received: received)
  }
}

/// Owns admitted pledge mutations independently of screen observation.
/// One account's distinct commands execute in admission order, including across
/// create/update/cancel screens. There is no automatic retry of a financial write.
@MainActor
public final class PledgeFeature {
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any PledgeProvider

  public init(sessionFeature: SessionFeature, makeProvider: @escaping () -> any PledgeProvider) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
  }

  private struct Session: Hashable { let userID: Int?; let generation: Int }
  private var session: Session {
    Session(userID: self.sessionFeature.currentUser?.id, generation: self.sessionFeature.generation)
  }
  private func requireCurrent(_ session: Session) throws {
    try Task.checkCancellation()
    guard self.session == session else { throw CancellationError() }
  }

  private enum Command: Equatable {
    case create(CreateBackingInput)
    case update(UpdateBackingInput)
    case cancel(CancelBackingInput)
    case received(projectID: Int, userID: Int, received: Bool)
  }
  private enum Value {
    case created(CreateBackingEnvelope)
    case updated(UpdateBackingEnvelope)
    case canceled
    case received(Backing)
  }
  private struct Pending {
    let id: UUID
    let command: Command
    let task: Task<Value, Error>
  }
  private var tails: [Session: Pending] = [:]
  private var commands: [UUID: Task<Value, Error>] = [:]
  private var observations: [UUID: Task<Void, Never>] = [:]

  private func request(_ command: Command) -> Task<Value, Error> {
    let session = self.session
    let previous = self.tails[session]
    if let previous, previous.command == command { return previous.task }
    let id = UUID()
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer {
        self.commands[id] = nil
        if self.tails[session]?.id == id { self.tails[session] = nil }
      }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(session)
      do {
        let value: Value
        switch command {
        case let .create(input): value = .created(try await provider.create(input))
        case let .update(input): value = .updated(try await provider.update(input))
        case let .cancel(input):
          try await provider.cancel(input)
          value = .canceled
        case let .received(projectID, userID, received):
          value = .received(try await provider.received(projectID: projectID, userID: userID, received: received))
        }
        try self.requireCurrent(session)
        return value
      } catch {
        try self.requireCurrent(session)
        throw error
      }
    }
    self.tails[session] = Pending(id: id, command: command, task: task)
    self.commands[id] = task
    return task
  }

  private func execute(_ command: Command) async throws -> Value {
    try Task.checkCancellation()
    let session = self.session
    do {
      let value = try await self.request(command).value
      try self.requireCurrent(session)
      return value
    } catch {
      try self.requireCurrent(session)
      throw error
    }
  }

  public func create(_ input: CreateBackingInput) async throws -> CreateBackingEnvelope {
    try Self.created(await self.execute(.create(input)))
  }
  public func update(_ input: UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    try Self.updated(await self.execute(.update(input)))
  }
  public func cancel(_ input: CancelBackingInput) async throws {
    _ = try await self.execute(.cancel(input))
  }
  public func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    try Self.received(await self.execute(.received(projectID: projectID, userID: userID, received: received)))
  }

  private static func created(_ value: Value) throws -> CreateBackingEnvelope {
    guard case let .created(envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func updated(_ value: Value) throws -> UpdateBackingEnvelope {
    guard case let .updated(envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func received(_ value: Value) throws -> Backing {
    guard case let .received(backing) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return backing
  }

  // These output adapters admit synchronously, preserving rapid input order.
  // Disposing an observer never cancels an already-admitted mutation.
  public func createResult(_ input: CreateBackingInput) -> SignalProducer<CreateBackingEnvelope, ErrorEnvelope> {
    self.result(.create(input), transform: Self.created)
  }
  public func updateResult(_ input: UpdateBackingInput) -> SignalProducer<UpdateBackingEnvelope, ErrorEnvelope> {
    self.result(.update(input), transform: Self.updated)
  }
  public func cancelResult(_ input: CancelBackingInput) -> SignalProducer<Void, ErrorEnvelope> {
    self.result(.cancel(input), transform: { _ in () })
  }
  public func receivedResult(projectID: Int, userID: Int, received: Bool) -> SignalProducer<Backing, ErrorEnvelope> {
    self.result(.received(projectID: projectID, userID: userID, received: received), transform: Self.received)
  }

  private func result<Output>(
    _ command: Command, transform: @escaping @MainActor (Value) throws -> Output
  ) -> SignalProducer<Output, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else { observer.sendInterrupted(); return }
        let commandTask = self.request(command)
        let id = UUID()
        let task = Task { [self] in
          defer { self.observations[id] = nil }
          do {
            let value = try await commandTask.value
            try self.requireCurrent(session)
            observer.send(value: try transform(value))
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session
            else { observer.sendInterrupted(); return }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  public func delayedResult<Value>(
    _ producer: SignalProducer<Value, ErrorEnvelope>
  ) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return producer.ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .materialize()
      .filter { _ in MainActor.assumeIsolated { self.session == session } }
      .dematerialize()
  }

  public func reset() {
    for task in self.observations.values { task.cancel() }
    // In-flight writes settle. Old queued writes fail their generation check
    // before provider admission; a new account has its own queue.
  }
  public func waitForOperations() async {
    while !self.commands.isEmpty || !self.observations.isEmpty {
      for task in Array(self.commands.values) { _ = await task.result }
      for task in Array(self.observations.values) { await task.value }
    }
  }
}
