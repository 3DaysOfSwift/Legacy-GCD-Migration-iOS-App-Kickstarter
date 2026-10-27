import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol AccountPreferencesProvider {
  func save(_ user: User) async throws -> User
}

@MainActor
public struct AsyncAccountPreferencesProvider: AccountPreferencesProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func save(_ user: User) async throws -> User {
    try await self.service.saveAccountPreferences(user)
  }
}

/// Owns ordered preference edits, not credentials or a second current-user store.
/// The legacy endpoint takes a whole User. Edits are applied to the authoritative
/// session user at dispatch, so stale cells cannot undo another screen's edits.
@MainActor
public final class SettingsFeature {
  public struct Change: Hashable {
    let path: WritableKeyPath<User, Bool?>
    let value: Bool?

    public init(_ attribute: UserAttribute, _ value: Bool?) {
      self.path = attribute.keyPath
      self.value = value
    }

    @MainActor public static func allNewsletters(_ on: Bool) -> [Change] {
      SettingsFeature.newsletters.map { Change(.newsletter($0), on) }
    }
  }

  private struct Account: Equatable {
    let id: Int?
    let generation: Int
    let sourceID: Int
  }

  private struct Pending {
    let id: UUID
    let account: Account
    let changes: [Change]
    let task: Task<User, Error>
  }

  private static let newsletters: [Newsletter] = [
    .arts, .games, .happening, .invent, .promo, .weekly, .films, .publishing, .alumni, .music
  ]
  private static var attributes: [UserAttribute] {
    let notifications: [UserAttribute.Notification] = [
      .commentReplies, .comments, .creatorDigest, .creatorTips, .follower, .friendActivity, .messages,
      .mobileComments, .mobileFollower, .mobileFriendActivity, .mobileMarketingUpdate, .mobileMessages,
      .mobilePledgeActivity, .mobilePostLikes, .mobileUpdates, .pledgeActivity, .postLikes, .updates
    ]
    return self.newsletters.map(UserAttribute.newsletter)
      + notifications.map(UserAttribute.notification)
      + [.privacy(.following), .privacy(.recommendations), .privacy(.showPublicProfile)]
  }

  private let session: SessionFeature
  private let makeProvider: () -> any AccountPreferencesProvider
  private var account: Account?
  private var tail: Pending?
  private var writes: [UUID: Task<User, Error>] = [:]
  private var reads: [UUID: Task<Void, Never>] = [:]
  private var editRevision = 0
  private let results = Signal<(UUID, Result<User, Error>), Never>.pipe()
  public private(set) var lastError: Error?

  public init(sessionFeature: SessionFeature, makeProvider: @escaping () -> any AccountPreferencesProvider) {
    self.session = sessionFeature
    self.makeProvider = makeProvider
  }

  public func save(_ changes: [Change], from user: User) async throws -> User {
    try Task.checkCancellation()
    // Once admitted, a preference write outlives its initiating screen/waiter.
    let value = try await self.request(changes, from: user).task.value
    try Task.checkCancellation()
    return value
  }

  private func identity(for user: User) -> Account {
    Account(id: self.session.currentUser?.id, generation: self.session.generation, sourceID: user.id)
  }

  private func isCurrent(_ account: Account) -> Bool {
    self.session.isCurrent(userID: account.id, generation: account.generation)
      && account.id == account.sourceID
  }

  private func preferences(of user: User) -> [Change] {
    Self.attributes.map { Change($0, user[keyPath: $0.keyPath]) }
  }

  private func applying(_ changes: [Change], to user: User) -> User {
    var user = user
    for change in changes { user[keyPath: change.path] = change.value }
    return user
  }

  private func request(_ changes: [Change], from source: User) -> Pending {
    let account = self.identity(for: source)
    let valid = self.isCurrent(account)
    if valid, self.account != account {
      self.account = account
      self.tail = nil
      self.lastError = nil
    }
    // Share only the equivalent tail: on/off/on must still execute in order.
    if valid, let tail = self.tail, tail.account == account, tail.changes == changes { return tail }
    let previous = valid ? self.tail?.task : nil
    let provider = self.makeProvider()
    let id = UUID()
    if valid {
      self.editRevision += 1
      self.session.invalidateReads()
    }
    let task = Task { [self] in
      if let previous { _ = await previous.result }
      let result: Result<User, Error>
      do {
        guard self.isCurrent(account) else { throw CancellationError() }
        let base = self.session.currentUser ?? source
        let requested = self.applying(changes, to: base)
        let response = try await provider.save(requested)
        guard self.isCurrent(account), response.id == source.id else { throw CancellationError() }
        let current = self.applying(self.preferences(of: response), to: self.session.currentUser ?? response)
        self.session.commitUser(current, userID: account.id, generation: account.generation)
        self.session.invalidateReads()
        self.lastError = nil
        result = .success(current)
      } catch {
        if self.isCurrent(account), !(error is CancellationError) { self.lastError = error }
        result = .failure(self.isCurrent(account) ? error : CancellationError())
      }
      self.writes[id] = nil
      if self.tail?.id == id { self.tail = nil }
      self.results.input.send(value: (id, result))
      return try result.get()
    }
    let pending = Pending(id: id, account: account, changes: changes, task: task)
    if valid { self.tail = pending }
    self.writes[id] = task
    return pending
  }

  /// Output-only bridge for existing UIKit adapters. Disposing observation does
  /// not abandon a durable command; async callers use save directly.
  public func saveResult(_ changes: [Change], from user: User) -> SignalProducer<User, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let pending = self.request(changes, from: user)
        let subscription = self.results.output.filter { $0.0 == pending.id }.take(first: 1)
          .observeValues { _, result in
            Self.deliver(result, to: observer)
          }
        lifetime.observeEnded { subscription?.dispose() }
      }
    }
  }

  public func userResult() -> SignalProducer<User, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        if let user = self.session.currentUser { observer.send(value: user) }
        let id = UUID()
        let generation = self.session.generation
        let userID = self.session.currentUser?.id
        let task = Task { [self] in
          defer { self.reads[id] = nil }
          do {
            let user = try await self.refresh(userID: userID, generation: generation)
            observer.send(value: user)
            observer.sendCompleted()
          } catch { Self.deliver(.failure(error), to: observer) }
        }
        self.reads[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  public func refresh() async throws -> User {
    try await self.refresh(userID: self.session.currentUser?.id, generation: self.session.generation)
  }

  private func refresh(userID: Int?, generation: Int) async throws -> User {
    if let previous = self.tail?.task { _ = await previous.result }
    let revision = self.editRevision
    try Task.checkCancellation()
    guard self.session.isCurrent(userID: userID, generation: generation)
    else { throw CancellationError() }
    let user = try await self.session.refresh()
    try Task.checkCancellation()
    guard revision == self.editRevision, userID == nil || user.id == userID else { throw CancellationError() }
    self.account = self.identity(for: user)
    self.session.commitUser(user, userID: userID, generation: generation)
    return user
  }

  private static func deliver(
    _ result: Result<User, Error>,
    to observer: Signal<User, ErrorEnvelope>.Observer
  ) {
    switch result {
    case let .success(user): observer.send(value: user); observer.sendCompleted()
    case .failure(is CancellationError): observer.sendInterrupted()
    case let .failure(error): observer.send(error: error as? ErrorEnvelope ?? .couldNotParseJSON)
    }
  }

  /// Waits for owned executions, not presentation scheduler delays.
  func waitForOperations() async {
    while !self.reads.isEmpty || !self.writes.isEmpty {
      let reads = Array(self.reads.values)
      let writes = Array(self.writes.values)
      for read in reads { await read.value }
      for write in writes { _ = await write.result }
    }
  }
}
