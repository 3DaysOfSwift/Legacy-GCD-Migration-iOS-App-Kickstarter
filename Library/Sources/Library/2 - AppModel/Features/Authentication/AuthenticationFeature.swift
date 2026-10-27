import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol AuthenticationProvider {
  func login(_ credentials: AuthenticationFeature.Credentials, code: String?) async throws
    -> AccessTokenEnvelope
}

@MainActor
public struct AsyncAuthenticationProvider: AuthenticationProvider {
  private let service: any ServiceType
  public init(service: any ServiceType) { self.service = service }

  public func login(
    _ credentials: AuthenticationFeature.Credentials, code: String?
  ) async throws -> AccessTokenEnvelope {
    switch credentials {
    case let .email(email, password):
      return try await self.service.authenticate(email: email, password: password, code: code)
    case let .facebook(token):
      return try await self.service.authenticate(facebookAccessToken: token, code: code)
    }
  }
}

/// Owns login/verification attempts. Equivalent pending attempts share transport;
/// changed credentials/code replace the older attempt, matching the legacy
/// switch-to-latest interaction. Credentials exist only for the attempt lifetime.
@MainActor
public final class AuthenticationFeature {
  private enum Operation { case login, resend }

  public enum Credentials: Equatable {
    case email(String, password: String)
    case facebook(String)
  }

  private final class Attempt {
    let id = UUID()
    let credentials: Credentials
    let code: String?
    let operation: Operation
    let userID: Int?
    let generation: Int
    let task: Task<AccessTokenEnvelope, Error>
    var waiters = 0
    var committedGeneration: Int?

    init(
      credentials: Credentials, code: String?, operation: Operation, userID: Int?, generation: Int,
      task: Task<AccessTokenEnvelope, Error>
    ) {
      self.credentials = credentials
      self.code = code
      self.operation = operation
      self.userID = userID
      self.generation = generation
      self.task = task
    }
  }

  private let session: SessionFeature
  private let makeProvider: () -> any AuthenticationProvider
  // The legacy screen allows resend and verification concurrently. A resend
  // must not supersede a submitted code; replacements are scoped per operation.
  private var current: [Operation: Attempt] = [:]
  private var attempts: [UUID: Attempt] = [:]
  private var presentations: [UUID: Task<Void, Never>] = [:]
  public private(set) var lastError: Error?

  public init(sessionFeature: SessionFeature, makeProvider: @escaping () -> any AuthenticationProvider) {
    self.session = sessionFeature
    self.makeProvider = makeProvider
  }

  public func authenticate(
    _ credentials: Credentials,
    code: String? = nil
  ) async throws -> AccessTokenEnvelope {
    try Task.checkCancellation()
    return try await self.finish(self.admit(credentials, code: code, resend: false))
  }

  public func resendCode(_ credentials: Credentials) async throws {
    try Task.checkCancellation()
    _ = try await self.finish(self.admit(credentials, code: nil, resend: true))
  }

  private func admit(_ credentials: Credentials, code: String?, resend: Bool) -> Attempt {
    let operation: Operation = resend ? .resend : .login
    if let current = self.current[operation],
       current.credentials == credentials, current.code == code,
       self.session.isCurrent(userID: current.userID, generation: current.generation) {
      current.waiters += 1
      return current
    }
    self.current[operation]?.task.cancel()
    let provider = self.makeProvider()
    let task = Task {
      try Task.checkCancellation()
      return try await provider.login(credentials, code: code)
    }
    let attempt = Attempt(
      credentials: credentials, code: code, operation: operation,
      userID: self.session.currentUser?.id, generation: self.session.generation, task: task
    )
    attempt.waiters = 1
    self.current[operation] = attempt
    self.attempts[attempt.id] = attempt
    self.lastError = nil
    return attempt
  }

  private func finish(_ attempt: Attempt) async throws -> AccessTokenEnvelope {
    defer {
      attempt.waiters -= 1
      if attempt.waiters == 0 {
        self.attempts[attempt.id] = nil
        if self.current[attempt.operation]?.id == attempt.id { self.current[attempt.operation] = nil }
      }
    }
    do {
      let envelope = try await attempt.task.value
      try Task.checkCancellation()
      guard self.current[attempt.operation]?.id == attempt.id else { throw CancellationError() }
      if let committed = attempt.committedGeneration {
        guard self.session.isCurrent(userID: envelope.user.id, generation: committed)
        else { throw CancellationError() }
      } else {
        guard self.session.isCurrent(userID: attempt.userID, generation: attempt.generation)
        else { throw CancellationError() }
        if attempt.operation == .login {
          try self.session.establishSession(
            envelope, userID: attempt.userID, generation: attempt.generation
          )
          attempt.committedGeneration = self.session.generation
        }
      }
      self.lastError = nil
      return envelope
    } catch {
      try Task.checkCancellation()
      guard self.current[attempt.operation]?.id == attempt.id,
            self.session.isCurrent(userID: attempt.userID, generation: attempt.generation)
      else { throw CancellationError() }
      if !(error is CancellationError) { self.lastError = error }
      throw error
    }
  }

  /// UIKit output adapter. Disposal cancels that caller, not another observer's
  /// shared request. A transport response alone never commits a cancelled login.
  /// Resending a code never establishes a session, even if the endpoint returns a token.
  public func result(_ credentials: Credentials, code: String? = nil, resend: Bool = false)
    -> SignalProducer<AccessTokenEnvelope, ErrorEnvelope> {
    SignalProducer { observer, lifetime in
      MainActor.assumeIsolated {
        let attempt = self.admit(credentials, code: code, resend: resend)
        let id = UUID()
        let task = Task { [self] in
          defer { self.presentations[id] = nil }
          do {
            let envelope = try await self.finish(attempt)
            observer.send(value: envelope)
            observer.sendCompleted()
          } catch is CancellationError { observer.sendInterrupted() }
          catch { observer.send(error: error as? ErrorEnvelope ?? .couldNotParseJSON) }
        }
        self.presentations[id] = task
        lifetime.observeEnded { task.cancel() }
      }
    }
  }

  func waitForOperations() async {
    while !self.presentations.isEmpty {
      for task in Array(self.presentations.values) { await task.value }
    }
  }
}
