import Foundation
import KsApi

@MainActor
public protocol SessionProvider {
  func user() async throws -> User
  func graphUser() async throws -> User
  func clearActivityIndicator() async throws -> Int
}

@MainActor
public struct AsyncSessionProvider: SessionProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }
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
  private var revision = 0
  private var readRevision = 0
  private var requests: [Identity: Task<User, Error>] = [:]
  public var currentUser: User? { self.readUser() }
  public var generation: Int { self.revision }
  public var readGeneration: Int { self.readRevision }

  public init(
    makeProvider: @escaping () -> any SessionProvider,
    currentUser: @escaping () -> User? = { AppEnvironment.current.currentUser },
    updateUser: @escaping (User) -> Void = { AppEnvironment.updateCurrentUser($0) }
  ) {
    self.makeProvider = makeProvider
    self.readUser = currentUser
    self.writeUser = updateUser
  }

  /// Login/logout is an explicit boundary, including returning to the same ID.
  /// Admitted badge writes continue but cannot publish into a newer session.
  public func sessionChanged() {
    self.revision += 1
    for (identity, task) in self.requests where identity.operation != .clearActivity { task.cancel() }
  }

  /// A completed account-affecting command requires fresh reads, without
  /// pretending that the user logged out or interrupting admitted badge writes.
  public func invalidateReads() {
    self.readRevision += 1
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

  public func refresh(_ operation: Operation = .user) async throws -> User {
    try Task.checkCancellation()
    let user = try await self.request(operation).value
    try Task.checkCancellation()
    return user
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
      guard self.isCurrent(userID: identity.userID, generation: identity.revision)
      else { throw CancellationError() }
      return user
    }
    self.requests[identity] = task
    return task
  }
}
