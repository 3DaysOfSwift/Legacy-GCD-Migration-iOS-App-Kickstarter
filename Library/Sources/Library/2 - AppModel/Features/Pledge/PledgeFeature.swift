import Foundation
import GraphAPI
import KsApi
import ReactiveSwift

@MainActor
public protocol PledgeProvider {
  func confirmAddress(backingID: String, addressID: String) async throws -> Bool
  func receipt(backingID: String, received: Bool) async throws -> Bool
  func paymentPlan(slug: String, amount: String) async throws -> GraphAPI.BuildPaymentPlanQuery.Data
  func openCheckout(_ input: KsApi.CreateCheckoutInput) async throws -> CreateCheckoutEnvelope
  func validateCheckout(checkoutID: String, sourceID: String, secret: String) async throws
    -> ValidateCheckoutEnvelope
  func completeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws
    -> GraphAPI.CompleteOnSessionCheckoutMutation.Data
  func project(_ param: Param) async throws -> Project
  func backing(_ id: Int) async throws -> Backing

  func create(_ input: KsApi.CreateBackingInput) async throws -> CreateBackingEnvelope
  func update(_ input: KsApi.UpdateBackingInput) async throws -> UpdateBackingEnvelope
  func cancel(_ input: KsApi.CancelBackingInput) async throws
  func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing
}

@MainActor
public struct AsyncPledgeProvider: PledgeProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func confirmAddress(backingID: String, addressID: String) async throws -> Bool {
    try await self.service.confirmPledgeAddress(backingID: backingID, addressID: addressID)
  }
  public func receipt(backingID: String, received: Bool) async throws -> Bool {
    try await self.service.setPledgeReceipt(backingID: backingID, received: received)
  }
  public func paymentPlan(slug: String, amount: String) async throws
    -> GraphAPI.BuildPaymentPlanQuery.Data
  {
    try await self.service.pledgePaymentPlan(slug: slug, amount: amount)
  }
  public func openCheckout(_ input: KsApi.CreateCheckoutInput) async throws
    -> CreateCheckoutEnvelope
  {
    try await self.service.openPledgeCheckout(input)
  }
  public func validateCheckout(checkoutID: String, sourceID: String, secret: String) async throws
    -> ValidateCheckoutEnvelope
  {
    try await self.service.checkPledgeCheckout(
      checkoutID: checkoutID, sourceID: sourceID, secret: secret)
  }
  public func completeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws
    -> GraphAPI.CompleteOnSessionCheckoutMutation.Data
  {
    try await self.service.finishPledgeCheckout(input)
  }
  public func backing(_ id: Int) async throws -> Backing {
    try await self.service.managedPledgeBacking(id: id)
  }
  public func project(_ param: Param) async throws -> Project {
    var project = try await self.service.discussionProject(param: param)
    try Task.checkCancellation()
    let extras = try await self.service.managedPledgeRewards(projectID: project.id)
    // Retain the existing first reward (the no-reward choice), then the GraphQL rewards.
    project.rewardData.rewards = Array(project.rewardData.rewards.prefix(1)) + extras.rewards
    project.isPledgeOverTimeAllowed = extras.isPledgeOverTimeAllowed
    project.pledgeOverTimeCollectionPlanChargeExplanation =
      extras.pledgeOverTimeCollectionPlanChargeExplanation
    project.pledgeOverTimeCollectionPlanChargedAsNPayments =
      extras.pledgeOverTimeCollectionPlanChargedAsNPayments
    project.pledgeOverTimeCollectionPlanShortPitch = extras.pledgeOverTimeCollectionPlanShortPitch
    project.pledgeOverTimeMinimumExplanation = extras.pledgeOverTimeMinimumExplanation
    return project
  }
  public func create(_ input: KsApi.CreateBackingInput) async throws -> CreateBackingEnvelope {
    try await self.service.submitPledge(input)
  }
  public func update(_ input: KsApi.UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    try await self.service.revisePledge(input)
  }
  public func cancel(_ input: KsApi.CancelBackingInput) async throws {
    try await self.service.cancelPledge(input)
  }
  public func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    try await self.service.markPledgeReceived(
      projectID: projectID, userID: userID, received: received)
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

  private enum Command: Equatable {
    case confirmAddress(String, String)
    case receipt(String, Bool)
    case openCheckout(KsApi.CreateCheckoutInput)
    case validateCheckout(checkoutID: String, sourceID: String, secret: String)
    case completeCheckout(GraphAPI.CompleteOnSessionCheckoutInput)
    case create(KsApi.CreateBackingInput)
    case update(KsApi.UpdateBackingInput)
    case cancel(KsApi.CancelBackingInput)
    case received(projectID: Int, userID: Int, received: Bool)
  }
  private enum Value {
    case acknowledged(Bool)
    case checkout(CreateCheckoutEnvelope)
    case validated(ValidateCheckoutEnvelope)
    case completed(GraphAPI.CompleteOnSessionCheckoutMutation.Data)
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
  private var writeVersion: [Session: Int] = [:]
  private var tails: [Session: Pending] = [:]
  private var commands: [UUID: Task<Value, Error>] = [:]
  private var observations: [UUID: Task<Void, Never>] = [:]

  private func request(_ command: Command) -> Task<Value, Error> {
    let session = self.session
    let previous = self.tails[session]
    if let previous, previous.command == command { return previous.task }
    self.writeVersion[session, default: 0] += 1
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
        case .confirmAddress(let backingID, let addressID):
          value = .acknowledged(
            try await provider.confirmAddress(backingID: backingID, addressID: addressID))
        case .receipt(let backingID, let received):
          value = .acknowledged(
            try await provider.receipt(backingID: backingID, received: received))
        case .openCheckout(let input): value = .checkout(try await provider.openCheckout(input))
        case .validateCheckout(let checkoutID, let sourceID, let secret):
          value = .validated(
            try await provider.validateCheckout(
              checkoutID: checkoutID, sourceID: sourceID, secret: secret))
        case .completeCheckout(let input):
          value = .completed(try await provider.completeCheckout(input))
        case .create(let input): value = .created(try await provider.create(input))
        case .update(let input): value = .updated(try await provider.update(input))
        case .cancel(let input):
          try await provider.cancel(input)
          value = .canceled
        case .received(let projectID, let userID, let received):
          value = .received(
            try await provider.received(projectID: projectID, userID: userID, received: received))
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

  public func confirmAddress(backingID: String, addressID: String) async throws -> Bool {
    try Self.acknowledged(await self.execute(.confirmAddress(backingID, addressID)))
  }
  public func receipt(backingID: String, received: Bool) async throws -> Bool {
    try Self.acknowledged(await self.execute(.receipt(backingID, received)))
  }
  public func confirmAddressResult(backingID: String, addressID: String) -> SignalProducer<
    Bool, ErrorEnvelope
  > {
    self.result(.confirmAddress(backingID, addressID), transform: Self.acknowledged)
  }
  public func receiptResult(backingID: String, received: Bool) -> SignalProducer<
    Bool, ErrorEnvelope
  > {
    self.result(.receipt(backingID, received), transform: Self.acknowledged)
  }
  private static func acknowledged(_ value: Value) throws -> Bool {
    guard case .acknowledged(let success) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return success
  }

  public func create(_ input: KsApi.CreateBackingInput) async throws -> CreateBackingEnvelope {
    try Self.created(await self.execute(.create(input)))
  }
  public func update(_ input: KsApi.UpdateBackingInput) async throws -> UpdateBackingEnvelope {
    try Self.updated(await self.execute(.update(input)))
  }
  public func cancel(_ input: KsApi.CancelBackingInput) async throws {
    _ = try await self.execute(.cancel(input))
  }
  public func received(projectID: Int, userID: Int, received: Bool) async throws -> Backing {
    try Self.received(
      await self.execute(.received(projectID: projectID, userID: userID, received: received)))
  }

  public func openCheckout(_ input: KsApi.CreateCheckoutInput) async throws
    -> CreateCheckoutEnvelope
  {
    try Self.checkout(await self.execute(.openCheckout(input)))
  }
  public func validateCheckout(checkoutID: String, sourceID: String, secret: String) async throws
    -> ValidateCheckoutEnvelope
  {
    try Self.validated(
      await self.execute(
        .validateCheckout(checkoutID: checkoutID, sourceID: sourceID, secret: secret)))
  }
  public func completeCheckout(_ input: GraphAPI.CompleteOnSessionCheckoutInput) async throws
    -> GraphAPI.CompleteOnSessionCheckoutMutation.Data
  {
    try Self.completed(await self.execute(.completeCheckout(input)))
  }
  public func openCheckoutResult(_ input: KsApi.CreateCheckoutInput) -> SignalProducer<
    CreateCheckoutEnvelope, ErrorEnvelope
  > {
    self.result(.openCheckout(input), transform: Self.checkout)
  }
  public func validateCheckoutResult(checkoutID: String, sourceID: String, secret: String)
    -> SignalProducer<ValidateCheckoutEnvelope, ErrorEnvelope>
  {
    self.result(
      .validateCheckout(checkoutID: checkoutID, sourceID: sourceID, secret: secret),
      transform: Self.validated)
  }
  public func completeCheckoutResult(_ input: GraphAPI.CompleteOnSessionCheckoutInput)
    -> SignalProducer<GraphAPI.CompleteOnSessionCheckoutMutation.Data, ErrorEnvelope>
  {
    self.result(.completeCheckout(input), transform: Self.completed)
  }
  private static func checkout(_ value: Value) throws -> CreateCheckoutEnvelope {
    guard case .checkout(let envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func validated(_ value: Value) throws -> ValidateCheckoutEnvelope {
    guard case .validated(let envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func completed(_ value: Value) throws
    -> GraphAPI.CompleteOnSessionCheckoutMutation.Data
  {
    guard case .completed(let data) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return data
  }

  private static func created(_ value: Value) throws -> CreateBackingEnvelope {
    guard case .created(let envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func updated(_ value: Value) throws -> UpdateBackingEnvelope {
    guard case .updated(let envelope) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return envelope
  }
  private static func received(_ value: Value) throws -> Backing {
    guard case .received(let backing) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return backing
  }

  // These output adapters admit synchronously, preserving rapid input order.
  // Disposing an observer never cancels an already-admitted mutation.
  public func createResult(_ input: KsApi.CreateBackingInput) -> SignalProducer<
    CreateBackingEnvelope, ErrorEnvelope
  > {
    self.result(.create(input), transform: Self.created)
  }
  public func updateResult(_ input: KsApi.UpdateBackingInput) -> SignalProducer<
    UpdateBackingEnvelope, ErrorEnvelope
  > {
    self.result(.update(input), transform: Self.updated)
  }
  public func cancelResult(_ input: KsApi.CancelBackingInput) -> SignalProducer<Void, ErrorEnvelope>
  {
    self.result(.cancel(input), transform: { _ in () })
  }
  public func receivedResult(projectID: Int, userID: Int, received: Bool) -> SignalProducer<
    Backing, ErrorEnvelope
  > {
    self.result(
      .received(projectID: projectID, userID: userID, received: received), transform: Self.received)
  }

  private func result<Output>(
    _ command: Command, transform: @escaping @MainActor (Value) throws -> Output
  ) -> SignalProducer<Output, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else {
          observer.sendInterrupted()
          return
        }
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
            else {
              observer.sendInterrupted()
              return
            }
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
    return producer.ksr_delay(
      AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler
    )
    .materialize()
    .filter { _ in MainActor.assumeIsolated { self.session == session } }
    .dematerialize()
  }

  private enum Read: Equatable {
    case plan(String, String)
    case project(Param)
    case backing(Int)
  }
  private enum ReadValue {
    case plan(GraphAPI.BuildPaymentPlanQuery.Data)
    case project(Project)
    case backing(Backing)
  }
  private struct PendingRead {
    let id: UUID
    let input: Read
    let version: Int
    let session: Session
    let task: Task<ReadValue, Error>
  }
  private var reads: [UUID: PendingRead] = [:]
  private var readTasks: [UUID: Task<ReadValue, Error>] = [:]

  private func requestRead(route: UUID, input: Read) -> Task<ReadValue, Error> {
    let session = self.session
    let version = self.writeVersion[session, default: 0]
    if let pending = self.reads[route], pending.input == input, pending.session == session,
      pending.version == version
    {
      return pending.task
    }
    self.reads[route]?.task.cancel()
    let id = UUID()
    let provider = self.makeProvider()
    let precedingWrite = self.tails[session]?.task
    let task = Task { [self] in
      defer {
        self.readTasks[id] = nil
        if self.reads[route]?.id == id { self.reads[route] = nil }
      }
      // A refresh must not overtake a write that the screen has already admitted.
      if let precedingWrite { _ = await precedingWrite.result }
      try self.requireCurrent(session)
      do {
        let value: ReadValue
        switch input {
        case .plan(let slug, let amount):
          value = .plan(try await provider.paymentPlan(slug: slug, amount: amount))
        case .project(let param): value = .project(try await provider.project(param))
        case .backing(let id): value = .backing(try await provider.backing(id))
        }
        try self.requireCurrent(session)
        return value
      } catch {
        try self.requireCurrent(session)
        throw error
      }
    }
    self.reads[route] = PendingRead(
      id: id, input: input, version: version, session: session, task: task)
    self.readTasks[id] = task
    return task
  }

  public func paymentPlan(route: UUID, slug: String, amount: String) async throws
    -> GraphAPI.BuildPaymentPlanQuery.Data
  {
    try Task.checkCancellation()
    let session = self.session
    do {
      let value = try await self.requestRead(route: route, input: .plan(slug, amount)).value
      try self.requireCurrent(session)
      return try Self.plan(value)
    } catch {
      try self.requireCurrent(session)
      throw error
    }
  }
  public func paymentPlanResult(route: UUID, slug: String, amount: String) -> SignalProducer<
    GraphAPI.BuildPaymentPlanQuery.Data, ErrorEnvelope
  > {
    self.readResult(route: route, input: .plan(slug, amount), transform: Self.plan)
  }
  private static func plan(_ value: ReadValue) throws -> GraphAPI.BuildPaymentPlanQuery.Data {
    guard case .plan(let data) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return data
  }
  public func project(route: UUID, param: Param) async throws -> Project {
    try Task.checkCancellation()
    let session = self.session
    do {
      let value = try await self.requestRead(route: route, input: .project(param)).value
      try self.requireCurrent(session)
      return try Self.project(value)
    } catch {
      try self.requireCurrent(session)
      throw error
    }
  }
  public func backing(route: UUID, id: Int) async throws -> Backing {
    try Task.checkCancellation()
    let session = self.session
    do {
      let value = try await self.requestRead(route: route, input: .backing(id)).value
      try self.requireCurrent(session)
      return try Self.backing(value)
    } catch {
      try self.requireCurrent(session)
      throw error
    }
  }
  private static func project(_ value: ReadValue) throws -> Project {
    guard case .project(let project) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return project
  }
  private static func backing(_ value: ReadValue) throws -> Backing {
    guard case .backing(let backing) = value else { throw ErrorEnvelope.couldNotParseJSON }
    return backing
  }
  public func projectResult(route: UUID, param: Param) -> SignalProducer<Project, ErrorEnvelope> {
    self.readResult(route: route, input: .project(param), transform: Self.project)
  }
  public func backingResult(route: UUID, id: Int) -> SignalProducer<Backing, ErrorEnvelope> {
    self.readResult(route: route, input: .backing(id), transform: Self.backing)
  }
  private func readResult<Output>(
    route: UUID, input: Read,
    transform: @escaping @MainActor (ReadValue) throws -> Output
  ) -> SignalProducer<Output, ErrorEnvelope> {
    let session = self.session
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session == session else {
          observer.sendInterrupted()
          return
        }
        let request = self.requestRead(route: route, input: input)
        let id = UUID()
        let task = Task { [self] in
          defer { self.observations[id] = nil }
          do {
            let value = try await request.value
            try self.requireCurrent(session)
            observer.send(value: try transform(value))
            observer.sendCompleted()
          } catch {
            guard !Task.isCancelled, !(error is CancellationError), self.session == session
            else {
              observer.sendInterrupted()
              return
            }
            observer.send(error: (error as? ErrorEnvelope) ?? .couldNotParseJSON)
          }
        }
        self.observations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }
  public func releaseRead(route: UUID) {
    self.reads.removeValue(forKey: route)?.task.cancel()
  }

  public func reset() {
    for pending in self.reads.values { pending.task.cancel() }
    self.reads.removeAll()
    self.writeVersion.removeAll()
    for task in self.observations.values { task.cancel() }
    // In-flight writes settle. Old queued writes fail their generation check
    // before provider admission; a new account has its own queue.
  }
  public func waitForOperations() async {
    while !self.commands.isEmpty || !self.observations.isEmpty || !self.readTasks.isEmpty {
      for task in Array(self.readTasks.values) { _ = await task.result }
      for task in Array(self.commands.values) { _ = await task.result }
      for task in Array(self.observations.values) { await task.value }
    }
  }
}
