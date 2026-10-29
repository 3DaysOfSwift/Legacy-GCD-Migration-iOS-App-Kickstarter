import Foundation
import GraphAPI
import KsApi
import ReactiveSwift

@MainActor
public protocol PaymentsProvider {
  func cards() async throws -> UserEnvelope<GraphUser>
  func remove(id: String) async throws -> DeletePaymentMethodEnvelope
  func store(secret: String) async throws -> CreatePaymentSourceEnvelope
  func setup(input: KsApi.CreateSetupIntentInput) async throws -> ClientSecretEnvelope
  func intent(input: KsApi.CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope
}

@MainActor
public struct AsyncPaymentsProvider: PaymentsProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func cards() async throws -> UserEnvelope<GraphUser> { try await self.service.paymentCards() }
  public func remove(id: String) async throws -> DeletePaymentMethodEnvelope {
    try await self.service.removePaymentMethod(id: id)
  }
  public func store(secret: String) async throws -> CreatePaymentSourceEnvelope {
    try await self.service.storePaymentMethod(secret: secret)
  }
  public func setup(input: KsApi.CreateSetupIntentInput) async throws -> ClientSecretEnvelope {
    try await self.service.paymentSetupIntent(input: input)
  }
  public func intent(input: KsApi.CreatePaymentIntentInput) async throws -> PaymentIntentEnvelope {
    try await self.service.paymentIntent(input: input)
  }
}

/// Owns stored-card operations and intent creation. An admitted mutation outlives
/// its screen observer; cancellation cannot undo a server-accepted write.
/// There is no automatic retry or claim of server-side idempotency.
@MainActor
public final class PaymentsFeature {
  public let sessionFeature: SessionFeature
  private let makeProvider: () -> any PaymentsProvider
  public init(sessionFeature: SessionFeature, makeProvider: @escaping () -> any PaymentsProvider) {
    self.sessionFeature = sessionFeature
    self.makeProvider = makeProvider
  }

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

  private enum Command: Hashable {
    case remove(String)
    case store(String)
    case setup(String?, String)
    case intent(String, String, String, String)
    var changesCards: Bool {
      switch self { case .remove, .store: return true; default: return false }
    }
  }
  private enum Value: Sendable {
    case removed(DeletePaymentMethodEnvelope)
    case stored(CreatePaymentSourceEnvelope)
    case setup(ClientSecretEnvelope)
    case intent(PaymentIntentEnvelope)
  }
  private struct Identity: Hashable { let session: Session; let command: Command }
  private struct Pending { let id: UUID; let task: Task<Value, Error> }
  private var pending: [Identity: Pending] = [:]
  private var commands: [UUID: Task<Value, Error>] = [:]
  private var cardTail: [Session: Pending] = [:]
  private var cardRevision = 0
  private var observers: [UUID: Task<Void, Never>] = [:]

  private func request(_ command: Command, operation: @escaping @MainActor (any PaymentsProvider) async throws -> Value)
    -> Task<Value, Error> {
    let identity = Identity(session: self.session, command: command)
    let previous = command.changesCards ? self.cardTail[identity.session] : nil
    if let existing = self.pending[identity],
       !command.changesCards || previous?.id == existing.id { return existing.task }
    let id = UUID()
    let provider = self.makeProvider()
    if command.changesCards { self.cardRevision += 1 }
    let task = Task { [self] in
      defer {
        self.commands[id] = nil
        if self.pending[identity]?.id == id { self.pending[identity] = nil }
        if self.cardTail[identity.session]?.id == id { self.cardTail[identity.session] = nil }
      }
      if let previous { _ = await previous.task.result }
      try self.requireCurrent(identity.session)
      do {
        let value = try await operation(provider)
        try self.requireCurrent(identity.session)
        return value
      } catch {
        try self.requireCurrent(identity.session)
        throw error
      }
    }
    let entry = Pending(id: id, task: task)
    self.pending[identity] = entry
    self.commands[id] = task
    if command.changesCards { self.cardTail[identity.session] = entry }
    return task
  }

  public func cards() async throws -> UserEnvelope<GraphUser> {
    let session = self.session
    // A reload waits for admitted card writes. If another write overtakes a
    // read, fetch again after that write rather than publishing an old list.
    while true {
      while let previous = self.cardTail[session] { _ = await previous.task.result }
      try self.requireCurrent(session)
      let revision = self.cardRevision
      do {
        let value = try await self.makeProvider().cards()
        try self.requireCurrent(session)
        if revision == self.cardRevision { return value }
      } catch {
        try self.requireCurrent(session)
        if revision == self.cardRevision { throw error }
      }
    }
  }

  public func remove(id: String) async throws -> DeletePaymentMethodEnvelope {
    try Task.checkCancellation()
    let session = self.session
    let value = try await self.request(.remove(id)) { .removed(try await $0.remove(id: id)) }.value
    try self.requireCurrent(session)
    guard case let .removed(envelope) = value else { preconditionFailure("Payment command type mismatch") }
    return envelope
  }
  public func store(secret: String) async throws -> CreatePaymentSourceEnvelope {
    try Task.checkCancellation()
    let session = self.session
    let value = try await self.request(.store(secret)) { .stored(try await $0.store(secret: secret)) }.value
    try self.requireCurrent(session)
    guard case let .stored(envelope) = value else { preconditionFailure("Payment command type mismatch") }
    return envelope
  }
  public func setup(projectID: String?, context: GraphAPI.StripeIntentContextTypes) async throws -> ClientSecretEnvelope {
    try Task.checkCancellation()
    let session = self.session
    let value = try await self.request(.setup(projectID, context.rawValue)) {
      .setup(try await $0.setup(input: KsApi.CreateSetupIntentInput(projectId: projectID, context: context)))
    }.value
    try self.requireCurrent(session)
    guard case let .setup(envelope) = value else { preconditionFailure("Payment command type mismatch") }
    return envelope
  }
  public func intent(projectID: String, backingID: String, checkoutID: String, total: Double) async throws -> PaymentIntentEnvelope {
    try Task.checkCancellation()
    let session = self.session
    let amount = String(format: "%.2f", total)
    let value = try await self.request(.intent(projectID, backingID, checkoutID, amount)) {
      .intent(try await $0.intent(input: KsApi.CreatePaymentIntentInput(
        projectId: projectID, backingId: backingID, amountDollars: amount,
        checkoutId: encodeToBase64("Checkout-\(checkoutID)"), digitalMarketingAttributed: nil
      )))
    }.value
    try self.requireCurrent(session)
    guard case let .intent(envelope) = value else { preconditionFailure("Payment command type mismatch") }
    return envelope
  }

  private func commandResult<Output>(
    _ command: Command, operation: @escaping @MainActor (any PaymentsProvider) async throws -> Value,
    extract: @escaping (Value) -> Output
  ) -> SignalProducer<Output, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else { observer.sendInterrupted(); return }
        let task = self.request(command, operation: operation)
        lifetime += self.result { extract(try await task.value) }.start(observer)
      }
    }
  }
  public func removeResult(id: String) -> SignalProducer<DeletePaymentMethodEnvelope, ErrorEnvelope> {
    self.commandResult(.remove(id), operation: { .removed(try await $0.remove(id: id)) }) {
      guard case let .removed(value) = $0 else { preconditionFailure("Payment command type mismatch") }
      return value
    }
  }
  public func storeResult(secret: String) -> SignalProducer<CreatePaymentSourceEnvelope, ErrorEnvelope> {
    self.commandResult(.store(secret), operation: { .stored(try await $0.store(secret: secret)) }) {
      guard case let .stored(value) = $0 else { preconditionFailure("Payment command type mismatch") }
      return value
    }
  }
  public func setupResult(projectID: String?, context: GraphAPI.StripeIntentContextTypes) -> SignalProducer<ClientSecretEnvelope, ErrorEnvelope> {
    self.commandResult(.setup(projectID, context.rawValue), operation: {
      .setup(try await $0.setup(input: KsApi.CreateSetupIntentInput(projectId: projectID, context: context)))
    }) {
      guard case let .setup(value) = $0 else { preconditionFailure("Payment command type mismatch") }
      return value
    }
  }
  public func intentResult(projectID: String, backingID: String, checkoutID: String, total: Double) -> SignalProducer<PaymentIntentEnvelope, ErrorEnvelope> {
    let amount = String(format: "%.2f", total)
    return self.commandResult(.intent(projectID, backingID, checkoutID, amount), operation: {
      .intent(try await $0.intent(input: KsApi.CreatePaymentIntentInput(
        projectId: projectID, backingId: backingID, amountDollars: amount,
        checkoutId: encodeToBase64("Checkout-\(checkoutID)"), digitalMarketingAttributed: nil
      )))
    }) {
      guard case let .intent(value) = $0 else { preconditionFailure("Payment command type mismatch") }
      return value
    }
  }

  /// UIKit compatibility boundary. Only observation is canceled on disposal.
  /// Awaitable commands above own mutations independently of this adapter.
  public func result<Value>(_ operation: @escaping @MainActor () async throws -> Value) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let id = UUID()
        let task = Task { [self] in
          defer { self.observers[id] = nil }
          do {
            try self.requireCurrent(session)
            let value = try await operation()
            try self.requireCurrent(session)
            observer.send(value: value)
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session
            else { observer.sendInterrupted(); return }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observers[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  /// Recheck session identity after any existing presentation debounce/delay.
  public func currentResult<Value>(_ make: () -> SignalProducer<Value, ErrorEnvelope>) -> SignalProducer<Value, ErrorEnvelope> {
    let session = self.session
    return make().materialize()
      .filter { _ in MainActor.assumeIsolated { self.session == session } }
      .dematerialize()
  }

  public func reset() {
    for task in self.observers.values { task.cancel() }
    // Already-admitted writes settle; queued obsolete writes fail their session
    // check before reaching the provider.
  }

  public func waitForOperations() async {
    while !self.observers.isEmpty || !self.commands.isEmpty {
      for task in Array(self.commands.values) { _ = await task.result }
      for task in Array(self.observers.values) { await task.value }
    }
  }
}
