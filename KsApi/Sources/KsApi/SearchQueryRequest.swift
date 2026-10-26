import Apollo
import Foundation
import GraphAPI

/// Search-only callback bridge. Other legacy GraphQL operations retain their
/// existing contracts while Search's cancellation/error semantics are verified.
internal enum SearchQueryRequest {
  @MainActor static func fetch(
    start: (@escaping GraphQLResultHandler<GraphAPI.SearchQuery.Data>) -> Cancellable
  ) async throws -> GraphAPI.SearchQuery.Data {
    let pending = PendingSearchQuery()
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
              pending.complete(.success(data))
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
internal final class PendingSearchQuery: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<GraphAPI.SearchQuery.Data, Error>?
  private var request: Cancellable?
  private var finished = false
  private var cancelled = false

  func install(_ continuation: CheckedContinuation<GraphAPI.SearchQuery.Data, Error>) -> Bool {
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

  func complete(_ result: Result<GraphAPI.SearchQuery.Data, Error>) {
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
