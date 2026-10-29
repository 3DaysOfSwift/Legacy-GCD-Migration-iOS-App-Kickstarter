import Foundation
import Library
import Stripe

/// Only checked status/error values leave the SDK callback. PaymentIntent and
/// SetupIntent SDK objects never cross into the observing task.
struct StripeConfirmationOutcome: Sendable, StripePaymentHandlerActionStatusType {
  let status: StripePaymentHandlerActionStatus
  let error: Error?

  init(status: STPPaymentHandlerActionStatus, error: Error?) {
    switch status {
    case .succeeded: self.status = .succeeded
    case .canceled: self.status = .canceled
    case .failed: self.status = .failed
    @unknown default: self.status = .failed
    }
    self.error = error
  }
}

/// Owns observation of one native confirmation. Stripe exposes no cancellation
/// token: cancelling observation suppresses UI delivery, not a server-side payment.
@MainActor
final class StripeConfirmationOperation {
  struct Identity: Equatable {
    enum Kind { case setup, payment }
    let kind: Kind
    let clientSecret: String
    var paymentMethodID: String? = nil
  }

  private var identity: Identity?
  private var generation: UUID?
  private var continuation: AsyncStream<StripeConfirmationOutcome>.Continuation?
  private(set) var task: Task<Void, Never>?

  func start(
    identity: Identity,
    isCurrent: @escaping @MainActor () -> Bool = { true },
    begin: (@escaping @Sendable (StripeConfirmationOutcome) -> Void) -> Void,
    completed: @escaping @MainActor (StripeConfirmationOutcome) -> Void
  ) {
    if self.identity == identity { return }
    guard self.identity == nil else {
      completed(.init(status: .failed, error: ConfirmationError.alreadyInProgress))
      return
    }

    let id = UUID()
    let (stream, continuation) = AsyncStream<StripeConfirmationOutcome>.makeStream(bufferingPolicy: .bufferingOldest(1))
    self.identity = identity
    self.generation = id
    self.continuation = continuation
    self.task = Task { [weak self] in
      for await outcome in stream {
        guard !Task.isCancelled, let self, self.generation == id else { return }
        self.identity = nil
        self.generation = nil
        self.continuation = nil
        self.task = nil
        guard isCurrent() else { return }
        completed(outcome)
        return
      }
    }
    begin { outcome in
      continuation.yield(outcome)
      continuation.finish()
    }
  }

  func cancelObservation() {
    self.generation = nil
    self.identity = nil
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

private enum ConfirmationError: LocalizedError {
  case alreadyInProgress
  var errorDescription: String? { "Another payment confirmation is already in progress." }
}
