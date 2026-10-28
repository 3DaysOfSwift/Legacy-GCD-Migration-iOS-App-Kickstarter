import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

@MainActor
public protocol AccountPreferencesProvider {
  func save(_ user: User) async throws -> User
  func projectNotifications() async throws -> [ProjectNotification]
  func saveProjectNotification(_ notification: ProjectNotification) async throws -> ProjectNotification
  func update(_ change: SettingsFeature.AccountChange) async throws -> User?
  func emailUser() async throws -> GraphUser
  func verifyEmail(token: String) async throws -> EmailVerificationResponseEnvelope
}

@MainActor
public struct AsyncAccountPreferencesProvider: AccountPreferencesProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func save(_ user: User) async throws -> User {
    try await self.service.saveAccountPreferences(user)
  }

  public func verifyEmail(token: String) async throws -> EmailVerificationResponseEnvelope {
    try await self.service.confirmEmail(token: token)
  }

  public func projectNotifications() async throws -> [ProjectNotification] {
    try await self.service.projectNotificationSettings()
  }

  public func saveProjectNotification(_ notification: ProjectNotification) async throws
    -> ProjectNotification {
    try await self.service.saveProjectNotification(notification)
  }

  public func emailUser() async throws -> GraphUser { try await self.service.accountEmailUser() }

  public func update(_ change: SettingsFeature.AccountChange) async throws -> User? {
    switch change {
    case let .email(input): try await self.service.saveEmail(input)
    case let .password(input): try await self.service.savePassword(input)
    case let .initialPassword(input): try await self.service.setInitialPassword(input)
    case let .currency(currency): try await self.service.saveCurrency(.init(chosenCurrency: currency))
    case .sendVerification: try await self.service.requestEmailVerification()
    case let .facebook(token): return try await self.service.connectFacebook(token: token)
    }
    return nil
  }
}

/// Owns ordered preference edits, not credentials or a second current-user store.
/// The legacy endpoint takes a whole User. Edits are applied to the authoritative
/// session user at dispatch, so stale cells cannot undo another screen's edits.
@MainActor
public final class SettingsFeature {
  /// Commands contain credentials only for their admitted lifetime, never in evidence or persistent state.
  public enum AccountChange: Equatable {
    case email(ChangeEmailInput)
    case password(ChangePasswordInput)
    case initialPassword(CreatePasswordInput)
    case currency(String)
    case sendVerification
    case facebook(String)
  }

  private enum Edit: Equatable {
    case preferences([Change])
    case account(AccountChange)
  }

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
    let edit: Edit
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

  private struct NotificationWrite {
    let id: UUID
    let userID: Int
    let generation: Int
    let email: Bool
    let mobile: Bool
    let task: Task<ProjectNotification, Error>
  }

  private var notificationTails: [Int: NotificationWrite] = [:]
  private var notificationWrites: [UUID: Task<ProjectNotification, Error>] = [:]
  private var notificationRevision = 0
  private let notificationResults = Signal<(UUID, Result<ProjectNotification, Error>), Never>.pipe()

  private let session: SessionFeature
  private let makeProvider: () -> any AccountPreferencesProvider
  private var account: Account?
  private var tail: Pending?
  private var writes: [UUID: Task<User, Error>] = [:]
  private var reads: [UUID: Task<Void, Never>] = [:]
  private var emailRead: (
    id: UUID,
    userID: Int?,
    generation: Int,
    revision: Int,
    task: Task<GraphUser, Error>
  )?
  private struct Verification {
    let id: UUID
    let token: String
    let userID: Int?
    let generation: Int
    let task: Task<EmailVerificationResponseEnvelope, Error>
  }

  private var verificationTail: Verification?
  private var verificationWrites: [UUID: Task<EmailVerificationResponseEnvelope, Error>] = [:]
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

  /// Notification URLs carry wire names. Convert only the requested field into
  /// an edit; never enqueue the whole user snapshot supplied by a deep link.
  public func notificationResult(named parameter: String, enabled: Bool)
    -> SignalProducer<User, ErrorEnvelope> {
    guard let user = self.session.currentUser else { return .empty }
    let names: [String: UserAttribute.Notification] = [
      "notify_of_backings": .pledgeActivity,
      "notify_of_comment_replies": .commentReplies,
      "notify_of_comments": .comments,
      "notify_of_creator_digest": .creatorDigest,
      "notify_of_creator_edu": .creatorTips,
      "notify_of_follower": .follower,
      "notify_of_friend_activity": .friendActivity,
      "notify_of_messages": .messages,
      "notify_mobile_of_backings": .mobilePledgeActivity,
      "notify_mobile_of_comments": .mobileComments,
      "notify_mobile_of_follower": .mobileFollower,
      "notify_mobile_of_friend_activity": .mobileFriendActivity,
      "notify_mobile_of_marketing_update": .mobileMarketingUpdate,
      "notify_mobile_of_messages": .mobileMessages,
      "notify_mobile_of_post_likes": .mobilePostLikes,
      "notify_mobile_of_updates": .mobileUpdates,
      "notify_of_post_likes": .postLikes,
      "notify_of_updates": .updates
    ]
    // Legacy decoding ignored unknown keys but still saved the unchanged user.
    let changes = names[parameter].map { [Change(.notification($0), enabled)] } ?? []
    return self.saveResult(changes, from: user)
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
    self.request(.preferences(changes), from: source)
  }

  private func request(_ edit: Edit, from source: User) -> Pending {
    let account = self.identity(for: source)
    let valid = self.isCurrent(account)
    if valid, self.account != account {
      self.account = account
      self.tail = nil
      self.lastError = nil
    }
    // Share only the equivalent tail: on/off/on must still execute in order.
    if valid, let tail = self.tail, tail.account == account, tail.edit == edit { return tail }
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
        let current: User
        switch edit {
        case let .preferences(changes):
          let response = try await provider.save(self.applying(changes, to: base))
          guard self.isCurrent(account), response.id == source.id else { throw CancellationError() }
          current = self.applying(self.preferences(of: response), to: self.session.currentUser ?? response)
        case let .account(change):
          let response = try await provider.update(change)
          guard self.isCurrent(account), response == nil || response?.id == source.id,
                var latest = self.session.currentUser else { throw CancellationError() }
          // Update only confirmed account fields, not a stale server copy of preferences.
          switch change {
          case let .currency(currency): latest.chosenCurrency = currency
          case .initialPassword: latest.needsPassword = false
          case .facebook:
            latest.facebookConnected = response?.facebookConnected
            latest.needsFreshFacebookToken = response?.needsFreshFacebookToken
          case .email, .password, .sendVerification: break
          }
          current = latest
        }
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
    let pending = Pending(id: id, account: account, edit: edit, task: task)
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

  public func updateAccount(_ change: AccountChange) async throws -> User {
    try Task.checkCancellation()
    guard let user = self.session.currentUser else { throw CancellationError() }
    let result = try await self.request(.account(change), from: user).task.value
    try Task.checkCancellation()
    return result
  }

  public func accountResult(_ change: AccountChange) -> SignalProducer<User, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard let user = self.session.currentUser else { observer.sendInterrupted(); return }
        let pending = self.request(.account(change), from: user)
        let subscription = self.results.output.filter { $0.0 == pending.id }.take(first: 1)
          .observeValues { _, result in Self.deliver(result, to: observer) }
        lifetime.observeEnded { subscription?.dispose() }
      }
    }
  }

  /// Verification links carry their own token and may be opened while signed out.
  /// They do not establish a login. Distinct links queue; equivalent tails share.
  public func verifyEmail(token: String) async throws -> EmailVerificationResponseEnvelope {
    try Task.checkCancellation()
    let task = self.verificationRequest(token: token)
    let envelope = try await task.value
    try Task.checkCancellation()
    return envelope
  }

  private func verificationRequest(token: String) -> Task<EmailVerificationResponseEnvelope, Error> {
    let userID = self.session.currentUser?.id
    let generation = self.session.generation
    if let tail = self.verificationTail, tail.token == token,
       tail.userID == userID, tail.generation == generation { return tail.task }
    let previous = self.verificationTail?.task
    let provider = self.makeProvider()
    let id = UUID()
    let task = Task { [self] in
      defer {
        self.verificationWrites[id] = nil
        if self.verificationTail?.id == id { self.verificationTail = nil }
      }
      if let previous { _ = await previous.result }
      do {
        guard self.session.isCurrent(userID: userID, generation: generation)
        else { throw CancellationError() }
        let envelope = try await provider.verifyEmail(token: token)
        guard self.session.isCurrent(userID: userID, generation: generation)
        else { throw CancellationError() }
        self.session.invalidateReads()
        return envelope
      } catch {
        guard self.session.isCurrent(userID: userID, generation: generation)
        else { throw CancellationError() }
        throw error
      }
    }
    self.verificationTail = Verification(
      id: id,
      token: token,
      userID: userID,
      generation: generation,
      task: task
    )
    self.verificationWrites[id] = task
    return task
  }

  public func verificationResult(token: String)
    -> SignalProducer<EmailVerificationResponseEnvelope, ErrorEnvelope> {
    self.readResult { try await self.verifyEmail(token: token) }
  }

  public func setupResult() -> SignalProducer<GraphUserSetup, ErrorEnvelope> {
    let userID = self.session.currentUser?.id
    let generation = self.session.generation
    return self.readResult {
      while let previous = self.tail?.task { _ = await previous.result }
      try Task.checkCancellation()
      guard self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
      return try await self.session.refreshSetup()
    }
  }

  private func readResult<Value>(_ operation: @escaping @MainActor () async throws -> Value)
    -> SignalProducer<Value, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let id = UUID()
        let task = Task { [self] in
          defer { self.reads[id] = nil }
          do {
            let value = try await operation()
            try Task.checkCancellation()
            observer.send(value: value)
            observer.sendCompleted()
          } catch is CancellationError { observer.sendInterrupted() }
          catch { observer.send(error: error as? ErrorEnvelope ?? .couldNotParseJSON) }
        }
        self.reads[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  public func emailUser() async throws -> GraphUser {
    let generation = self.session.generation
    let userID = self.session.currentUser?.id
    while let previous = self.tail?.task { _ = await previous.result }
    let revision = self.session.readGeneration
    try Task.checkCancellation()
    guard self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
    let task: Task<GraphUser, Error>
    if let existing = self.emailRead, existing.userID == userID,
       existing.generation == generation, existing.revision == revision {
      task = existing.task
    } else {
      self.emailRead?.task.cancel()
      let id = UUID()
      let provider = self.makeProvider()
      task = Task { [self] in
        defer { if self.emailRead?.id == id { self.emailRead = nil } }
        return try await provider.emailUser()
      }
      self.emailRead = (id, userID, generation, revision, task)
    }
    do {
      let user = try await task.value
      try Task.checkCancellation()
      guard revision == self.session.readGeneration, self.session.isCurrent(
        userID: userID,
        generation: generation
      )
      else { throw CancellationError() }
      return user
    } catch {
      guard !Task.isCancelled, revision == self.session.readGeneration,
            self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
      throw error
    }
  }

  public func emailUserResult() -> SignalProducer<GraphUser, ErrorEnvelope> {
    let generation = self.session.generation
    let userID = self.session.currentUser?.id
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let id = UUID()
        let task = Task { [self] in
          defer { self.reads[id] = nil }
          do {
            guard self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
            let user = try await self.emailUser()
            observer.send(value: user)
            observer.sendCompleted()
          } catch is CancellationError { observer.sendInterrupted() }
          catch { observer.send(error: error as? ErrorEnvelope ?? .couldNotParseJSON) }
        }
        self.reads[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  /// Preserve presentation delay while rejecting results from an earlier session
  /// or an account read invalidated by a later settings write.
  public func accountFieldsResult() -> SignalProducer<GraphUser, ErrorEnvelope> {
    let generation = self.session.generation
    let userID = self.session.currentUser?.id
    return self.emailUserResult()
      .materialize()
      .map { ($0, self.session.readGeneration) }
      .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
      .filter { _, revision in
        MainActor.assumeIsolated {
          self.session.isCurrent(userID: userID, generation: generation) && self.session.readGeneration == revision
        }
      }
      .map { $0.0 }
      .dematerialize()
  }

  /// App lifecycle receives only a freshly committed user, not the cached initial emission.
  public func refreshResult(allowSessionRestore: Bool = false) -> SignalProducer<User, ErrorEnvelope> {
    self.userResult(includeCurrent: false, allowSessionRestore: allowSessionRestore)
  }

  public func userResult() -> SignalProducer<User, ErrorEnvelope> {
    self.userResult(includeCurrent: true)
  }

  private func userResult(
    includeCurrent: Bool,
    allowSessionRestore: Bool = false
  ) -> SignalProducer<User, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        if includeCurrent, let user = self.session.currentUser { observer.send(value: user) }
        let id = UUID()
        let generation = self.session.generation
        let userID = self.session.currentUser?.id
        let task = Task { [self] in
          defer { self.reads[id] = nil }
          do {
            let user = try await self.refresh(
              userID: userID,
              generation: generation,
              allowSessionRestore: allowSessionRestore
            )
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

  private func refresh(
    userID: Int?,
    generation: Int,
    allowSessionRestore: Bool = false
  ) async throws -> User {
    while let previous = self.tail?.task { _ = await previous.result }
    let revision = self.editRevision
    try Task.checkCancellation()
    guard self.session.isCurrent(userID: userID, generation: generation)
    else { throw CancellationError() }
    let readGeneration = self.session.readGeneration
    do {
      let user = try await self.session.refresh()
      try Task.checkCancellation()
      guard revision == self.editRevision, readGeneration == self.session.readGeneration,
            self.session.isCurrent(userID: userID, generation: generation),
            userID == nil || user.id == userID else { throw CancellationError() }
      self.account = self.identity(for: user)
      self.session.commitRefreshedUser(
        user,
        userID: userID,
        generation: generation,
        allowSessionRestore: allowSessionRestore
      )
      return user
    } catch {
      guard !Task.isCancelled, revision == self.editRevision,
            readGeneration == self.session.readGeneration,
            self.session.isCurrent(userID: userID, generation: generation)
      else { throw CancellationError() }
      throw error
    }
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

  // MARK: Project notification settings

  public func projectNotifications() async throws -> [ProjectNotification] {
    let userID = self.session.currentUser?.id
    let generation = self.session.generation
    guard userID != nil else { throw CancellationError() }
    // A fresh list cannot overtake an admitted setting edit.
    while !self.notificationWrites.isEmpty {
      for task in Array(self.notificationWrites.values) { _ = await task.result }
    }
    let revision = self.notificationRevision
    try Task.checkCancellation()
    guard self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
    let provider = self.makeProvider()
    do {
      let values = try await provider.projectNotifications()
      try Task.checkCancellation()
      guard revision == self.notificationRevision,
            self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
      return values
    } catch {
      guard !Task.isCancelled, revision == self.notificationRevision,
            self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
      throw error
    }
  }

  public func saveProjectNotification(_ notification: ProjectNotification) async throws -> ProjectNotification {
    try Task.checkCancellation()
    let pending = try self.notificationRequest(notification)
    let result = try await pending.task.value
    try Task.checkCancellation()
    guard self.session.isCurrent(userID: pending.userID, generation: pending.generation)
    else { throw CancellationError() }
    return result
  }

  private func notificationRequest(_ notification: ProjectNotification) throws -> NotificationWrite {
    guard let userID = self.session.currentUser?.id else { throw CancellationError() }
    let generation = self.session.generation
    let tail = self.notificationTails[notification.id]
    let sameSession = tail?.userID == userID && tail?.generation == generation
    if sameSession, let tail, tail.email == notification.email, tail.mobile == notification.mobile {
      return tail
    }
    let previous = sameSession ? tail?.task : nil
    let id = UUID()
    let provider = self.makeProvider()
    self.notificationRevision += 1
    let task = Task { [self] in
      if let previous { _ = await previous.result }
      let result: Result<ProjectNotification, Error>
      do {
        guard self.session.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
        let saved = try await provider.saveProjectNotification(notification)
        guard self.session.isCurrent(userID: userID, generation: generation), saved.id == notification.id
        else { throw CancellationError() }
        // Preserve the existing cache/key and store only confirmed state.
        AppEnvironment.current.cache[self.notificationCacheKey(saved)] = saved.email && saved.mobile
        result = .success(saved)
      } catch {
        result = .failure(self.session.isCurrent(userID: userID, generation: generation)
          ? error : CancellationError())
      }
      self.notificationWrites[id] = nil
      if self.notificationTails[notification.id]?.id == id { self.notificationTails[notification.id] = nil }
      self.notificationResults.input.send(value: (id, result))
      return try result.get()
    }
    let pending = NotificationWrite(
      id: id, userID: userID, generation: generation,
      email: notification.email, mobile: notification.mobile, task: task
    )
    self.notificationTails[notification.id] = pending
    self.notificationWrites[id] = task
    return pending
  }

  private func notificationCacheKey(_ notification: ProjectNotification) -> String {
    "project_notification_view_model_notification_\(notification.id)"
  }

  public func cachedProjectNotification(_ notification: ProjectNotification) -> ProjectNotification {
    guard let on = AppEnvironment.current.cache[self.notificationCacheKey(notification)] as? Bool
    else { return notification }
    return notification |> ProjectNotification.lens.email .~ on |> ProjectNotification.lens.mobile .~ on
  }

  /// Compatibility output only. Disposal stops presentation, never an admitted write.
  public func projectNotificationResult(_ notification: ProjectNotification)
    -> SignalProducer<ProjectNotification, ErrorEnvelope> {
    let userID = self.session.currentUser?.id
    let generation = self.session.generation
    return SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        guard self.session.isCurrent(userID: userID, generation: generation) else {
          observer.sendInterrupted()
          return
        }
        do {
          let pending = try self.notificationRequest(notification)
          let subscription = self.notificationResults.output.filter { $0.0 == pending.id }.take(first: 1)
            .observeValues { _, result in
              switch result {
              case let .success(value): observer.send(value: value); observer.sendCompleted()
              case .failure(is CancellationError): observer.sendInterrupted()
              case let .failure(error): observer.send(error: error as? ErrorEnvelope ?? .couldNotParseJSON)
              }
            }
          lifetime.observeEnded { subscription?.dispose() }
        } catch { observer.sendInterrupted() }
      }
    }
    .materialize()
    .ksr_delay(AppEnvironment.current.apiDelayInterval, on: AppEnvironment.current.scheduler)
    .filter { _ in self.session.isCurrent(userID: userID, generation: generation) }
    .dematerialize()
  }

  /// Waits for owned executions, not presentation scheduler delays.
  func waitForOperations() async {
    while !self.reads.isEmpty || !self.writes.isEmpty || !self.verificationWrites.isEmpty || self
      .emailRead != nil || !self.notificationWrites.isEmpty {
      for task in Array(self.notificationWrites.values) { _ = await task.result }
      let reads = Array(self.reads.values)
      let writes = Array(self.writes.values)
      let verifications = Array(self.verificationWrites.values)
      for verification in verifications { _ = await verification.result }
      if let task = self.emailRead?.task { _ = await task.result }
      for read in reads { await read.value }
      for write in writes { _ = await write.result }
    }
  }
}
