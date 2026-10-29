import Apollo
import ApolloAPI
import Foundation
import GraphAPI

/// Shared bridge for migrated Search and Project-detail Apollo operations.
/// The pinned Apollo callback APIs have no native cancellation-aware async form.
internal enum CancellableGraphQLRequest {
  @MainActor static func fetch<Data: RootSelectionSet>(
    start: (@escaping GraphQLResultHandler<Data>) -> Cancellable
  ) async throws -> Data {
    try await self.perform(start: start, map: { $0 })
  }

  /// Decode a checked value snapshot on the callback executor. Generated Apollo
  /// selection sets stay there instead of crossing into the awaiting Feature.
  @MainActor static func fetch<Data: RootSelectionSet, Value: Sendable>(
    start: (@escaping GraphQLResultHandler<Data>) -> Cancellable,
    map: @escaping @Sendable (Data) throws -> Value
  ) async throws -> Value {
    try await self.perform(start: start, map: map)
  }

  @MainActor private static func perform<Data: RootSelectionSet, Value>(
    start: (@escaping GraphQLResultHandler<Data>) -> Cancellable,
    map: @escaping @Sendable (Data) throws -> Value
  ) async throws -> Value {
    let pending = PendingGraphQLRequest<Value>()
    let data = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard pending.install(continuation) else { return }
        let request = start { response in
          switch response {
          case let .success(result):
            if let message = result.errors?.first?.errorDescription {
              pending.complete(.failure(ErrorEnvelope.graphError(message)))
            } else if let data = result.data {
              do { pending.complete(.success(try map(data))) }
              catch { pending.complete(.failure(error)) }
            } else {
              pending.complete(.failure(ErrorEnvelope.couldNotParseJSON))
            }
          case .failure:
            // Preserve Search's existing reactive transport-error mapping.
            pending.complete(.failure(ErrorEnvelope.couldNotParseJSON))
          }
        }
        pending.install(request)
      }
    } onCancel: {
      pending.cancel()
    }
    try Task.checkCancellation()
    return data
  }
}

/// The lock protects all lifetime state. Exactly one terminal path takes the
/// continuation and request. Neither client cancellation nor continuation
/// resumption runs under the lock (both can re-enter through callbacks).
/// This narrowly scoped unchecked conformance protects a callback/cancellation
/// race; it does not declare Apollo payloads or the client globally Sendable.
internal final class PendingGraphQLRequest<Data>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?
  private var request: Cancellable?
  private var finished = false
  private var cancelled = false

  func install(_ continuation: CheckedContinuation<Data, Error>) -> Bool {
    self.lock.lock()
    let accepts = !self.finished
    if accepts { self.continuation = continuation }
    self.lock.unlock()
    if !accepts { continuation.resume(throwing: CancellationError()) }
    return accepts
  }

  func install(_ request: Cancellable) {
    self.lock.lock()
    let cancelImmediately = self.cancelled
    if !self.finished { self.request = request }
    self.lock.unlock()
    // Cancellation may win before Apollo returns its token.
    if cancelImmediately { request.cancel() }
  }

  func complete(_ result: Result<Data, Error>) {
    self.lock.lock()
    guard !self.finished else {
      self.lock.unlock()
      return
    }
    self.finished = true
    let continuation = self.continuation
    let request = self.request
    self.continuation = nil
    self.request = nil
    self.lock.unlock()
    // Releasing a client token can run its deinitializer; do that outside lock too.
    withExtendedLifetime(request) { continuation?.resume(with: result) }
  }

  func cancel() {
    self.lock.lock()
    guard !self.finished else {
      self.lock.unlock()
      return
    }
    self.finished = true
    self.cancelled = true
    let continuation = self.continuation
    let request = self.request
    self.continuation = nil
    self.request = nil
    self.lock.unlock()
    request?.cancel()
    continuation?.resume(throwing: CancellationError())
  }
}
