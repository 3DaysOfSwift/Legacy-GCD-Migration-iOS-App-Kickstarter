import Foundation
import GraphAPI
import KsApi

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
    let task = self.requestIntent(projectID: projectID, backingID: backingID, checkoutID: checkoutID, total: total)
    let value = try await task.value
    try Task.checkCancellation()
    return value
  }

  /// Admit the intent immediately; cancellation of a screen's waiter does not cancel the write.
  public func requestIntent(projectID: String, backingID: String, checkoutID: String, total: Double) -> Task<PaymentIntentEnvelope, Error> {
    let session = self.session
    let amount = String(format: "%.2f", total)
    let request = self.request(.intent(projectID, backingID, checkoutID, amount)) {
      .intent(try await $0.intent(input: KsApi.CreatePaymentIntentInput(
        projectId: projectID, backingId: backingID, amountDollars: amount,
        checkoutId: encodeToBase64("Checkout-\(checkoutID)"), digitalMarketingAttributed: nil
      )))
    }
    return Task { [self] in
      let value = try await request.value
      try self.requireCurrent(session)
      guard case let .intent(envelope) = value else { preconditionFailure("Payment command type mismatch") }
      return envelope
    }
  }

  public func waitForOperations() async {
    while !self.commands.isEmpty {
      for task in Array(self.commands.values) { _ = await task.result }
    }
  }
}
