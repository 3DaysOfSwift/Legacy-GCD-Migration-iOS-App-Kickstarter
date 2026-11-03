import Foundation
import PassKit

struct ApplePayTokenOutcome: Sendable {
  let tokenID: String?
  let error: Error?
}

/// Owns token observation and guarantees one PassKit reply, including cancellation
/// and owner release. Tokenization itself exposes no cancellation handle.
@MainActor
final class ApplePayTokenOperation {
  private var generation: UUID?
  private var continuation: AsyncStream<ApplePayTokenOutcome>.Continuation?
  private(set) var task: Task<Void, Never>?

  func start(
    isCurrent: @escaping @MainActor () -> Bool,
    begin: (@escaping @Sendable (ApplePayTokenOutcome) -> Void) -> Void,
    apply: @escaping @MainActor (ApplePayTokenOutcome) -> PKPaymentAuthorizationStatus,
    reply: @escaping @MainActor (PKPaymentAuthorizationResult) -> Void
  ) {
    guard self.generation == nil else {
      reply(PKPaymentAuthorizationResult(status: .failure, errors: []))
      return
    }
    let id = UUID()
    let (stream, continuation) = AsyncStream<ApplePayTokenOutcome>.makeStream(bufferingPolicy: .bufferingOldest(1))
    self.generation = id
    self.continuation = continuation
    self.task = Task { [weak self] in
      var status = PKPaymentAuthorizationStatus.failure
      for await outcome in stream {
        if !Task.isCancelled, let self, self.generation == id, isCurrent() {
          status = apply(outcome)
        }
        break
      }
      if let self, self.generation == id {
        self.generation = nil
        self.continuation = nil
        self.task = nil
      }
      reply(PKPaymentAuthorizationResult(status: status, errors: []))
    }
    begin { outcome in continuation.yield(outcome); continuation.finish() }
  }

  func cancelObservation() {
    self.generation = nil
    self.continuation?.finish()
    self.continuation = nil
    self.task?.cancel()
    self.task = nil
  }

  deinit {
    self.continuation?.finish()
    self.task?.cancel()
  }
}
