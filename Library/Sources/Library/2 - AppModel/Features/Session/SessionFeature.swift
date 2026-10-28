import Foundation
import KsApi

@MainActor
public protocol SessionProvider {
  func setup() async throws -> GraphUserSetup
  func user() async throws -> User
  func graphUser() async throws -> User
  func clearActivityIndicator() async throws -> Int
}

@MainActor
public struct AsyncSessionProvider: SessionProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
  public func setup() async throws -> GraphUserSetup { try await self.service.sessionSetup() }
  public func user() async throws -> User { try await self.service.sessionUser() }
  public func graphUser() async throws -> User { try await self.service.sessionGraphUser() }
  public func clearActivityIndicator() async throws -> Int { try await self.service.clearActivityIndicator() }
}

/// Owns shared account-read execution and account-bound badge mutations.
/// AppEnvironment remains the single credential/current-user store during staged
/// adoption; this Feature deliberately does not introduce a competing user cache.
@MainActor
public final class SessionFeature {
  public enum Operation: Hashable { case user, graphUser, clearActivity }
  private struct Identity: Hashable {
    let operation: Operation
    let userID: Int?
    let revision: Int
    let readRevision: Int
  }

  private let makeProvider: () -> any SessionProvider
  private let readUser: () -> User?
  private let writeUser: (User) -> Void
  private let login: (AccessTokenEnvelope) -> Void
  private let writeSetup: (GraphUserSetup) -> Void
  private var setupRequests: [Identity: Task<GraphUserSetup, Error>] = [:]
  private var revision = 0
  private var readRevision = 0
  private var requests: [Identity: Task<User, Error>] = [:]
  public var currentUser: User? { self.readUser() }
  public var generation: Int { self.revision }
  public var readGeneration: Int { self.readRevision }

  public init(
    makeProvider: @escaping () -> any SessionProvider,
    currentUser: @escaping () -> User? = { AppEnvironment.current.currentUser },
    updateUser: @escaping (User) -> Void = { AppEnvironment.updateCurrentUser($0) },
    login: @escaping (AccessTokenEnvelope) -> Void = { AppEnvironment.login($0) },
    updateSetup: @escaping (GraphUserSetup) -> Void = { setup in
      guard let email = setup.email else { return }
      AppEnvironment.replaceCurrentEnvironment(
        currentUserEmail: email,
        currentUserPPOSettings: PPOUserSettings(
          hasAction: setup.ppoHasAction ?? false, backingActionCount: setup.backingActionCount ?? 0
        ),
        currentUserServerFeatures: setup.enabledFeatures
      )
    }
  ) {
    self.makeProvider = makeProvider
    self.readUser = currentUser
    self.writeUser = updateUser
    self.login = login
    self.writeSetup = updateSetup
  }

  /// Login/logout is an explicit boundary, including returning to the same ID.
  /// Admitted badge writes continue but cannot publish into a newer session.
  public func sessionChanged() {
    self.revision += 1
    for task in self.setupRequests.values { task.cancel() }
    for (identity, task) in self.requests where identity.operation != .clearActivity { task.cancel() }
  }

  /// A completed account-affecting command requires fresh reads, without
  /// pretending that the user logged out or interrupting admitted badge writes.
  public func invalidateReads() {
    self.readRevision += 1
    for task in self.setupRequests.values { task.cancel() }
    for (identity, task) in self.requests where identity.operation != .clearActivity { task.cancel() }
  }

  public func isCurrent(userID: Int?, generation: Int) -> Bool {
    self.currentUser?.id == userID && self.revision == generation
  }

  /// Persistence stays behind the existing current-user store. A stale response
  /// must never recreate a logged-out account or update a replacement account.
  public func commitUser(_ user: User, userID: Int?, generation: Int) {
    guard userID == user.id, self.isCurrent(userID: userID, generation: generation) else { return }
    self.writeUser(user)
  }

  /// A stored OAuth token can restore a user absent from legacy defaults. Only
  /// the authenticated lifecycle path opts in; ordinary reads cannot sign in.
  public func commitRefreshedUser(
    _ user: User, userID: Int?, generation: Int, allowSessionRestore: Bool
  ) {
    guard self.isCurrent(userID: userID, generation: generation),
          userID == user.id || (userID == nil && allowSessionRestore) else { return }
    self.writeUser(user)
  }

  /// Commit credentials and user together through the existing store, only if
  /// the session that initiated authentication still owns this completion.
  public func establishSession(
    _ envelope: AccessTokenEnvelope, userID: Int?, generation: Int
  ) throws {
    guard self.isCurrent(userID: userID, generation: generation) else { throw CancellationError() }
    self.sessionChanged()
    self.login(envelope)
  }

  /// Email, feature flags and backing-action metadata belong to the same session
  /// as the user. Only the shared execution commits; observers never replay it.
  public func refreshSetup() async throws -> GraphUserSetup {
    try Task.checkCancellation()
    let identity = Identity(
      operation: .user,
      userID: self.currentUser?.id,
      revision: self.revision,
      readRevision: self.readRevision
    )
    let task: Task<GraphUserSetup, Error>
    if let existing = self.setupRequests[identity] {
      task = existing
    } else {
      let provider = self.makeProvider()
      task = Task { [self] in
        defer { self.setupRequests[identity] = nil }
        do {
          try Task.checkCancellation()
          let setup = try await provider.setup()
          try Task.checkCancellation()
          guard self.isCurrent(userID: identity.userID, generation: identity.revision),
                self.readRevision == identity.readRevision else { throw CancellationError() }
          self.writeSetup(setup)
          return setup
        } catch {
          guard !Task.isCancelled,
                self.isCurrent(userID: identity.userID, generation: identity.revision),
                self.readRevision == identity.readRevision else { throw CancellationError() }
          throw error
        }
      }
      self.setupRequests[identity] = task
    }
    do {
      let setup = try await task.value
      try Task.checkCancellation()
      guard self.isCurrent(userID: identity.userID, generation: identity.revision),
            self.readRevision == identity.readRevision else { throw CancellationError() }
      return setup
    } catch {
      guard !Task.isCancelled,
            self.isCurrent(userID: identity.userID, generation: identity.revision),
            self.readRevision == identity.readRevision else { throw CancellationError() }
      throw error
    }
  }

  public func refresh(_ operation: Operation = .user) async throws -> User {
    try Task.checkCancellation()
    let userID = self.currentUser?.id
    let generation = self.revision
    let readGeneration = self.readRevision
    do {
      let user = try await self.request(operation).value
      try Task.checkCancellation()
      guard self.isCurrent(userID: userID, generation: generation),
            operation == .clearActivity || self.readRevision == readGeneration
      else { throw CancellationError() }
      return user
    } catch {
      guard !Task.isCancelled, self.isCurrent(userID: userID, generation: generation),
            operation == .clearActivity || self.readRevision == readGeneration
      else { throw CancellationError() }
      throw error
    }
  }

  @discardableResult
  public func request(_ operation: Operation = .user) -> Task<User, Error> {
    let identity = Identity(
      operation: operation, userID: self.currentUser?.id, revision: self.revision,
      readRevision: operation == .clearActivity ? 0 : self.readRevision
    )
    if let task = self.requests[identity] { return task }
    let provider = self.makeProvider()
    let task = Task { [self] in
      defer { self.requests[identity] = nil }
      try Task.checkCancellation()
      guard self.isCurrent(userID: identity.userID, generation: identity.revision)
      else { throw CancellationError() }
      do {
        let user: User
        switch operation {
        case .user: user = try await provider.user()
        case .graphUser: user = try await provider.graphUser()
        case .clearActivity:
          guard identity.userID != nil else { throw CancellationError() }
          let count = try await provider.clearActivityIndicator()
          guard var current = self.currentUser else { throw CancellationError() }
          current.unseenActivityCount = count
          user = current
        }
        try Task.checkCancellation()
        guard self.isCurrent(userID: identity.userID, generation: identity.revision),
              operation == .clearActivity || self.readRevision == identity.readRevision
        else { throw CancellationError() }
        return user
      } catch {
        // An old unauthorized response must not log out a replacement session.
        guard !Task.isCancelled, self.isCurrent(userID: identity.userID, generation: identity.revision),
              operation == .clearActivity || self.readRevision == identity.readRevision
        else { throw CancellationError() }
        throw error
      }
    }
    self.requests[identity] = task
    return task
  }
}
