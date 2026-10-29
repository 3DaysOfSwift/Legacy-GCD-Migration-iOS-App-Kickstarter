import Foundation
import Library
import StripePaymentSheet
import UIKit

/// SDK resources stay on the UI actor. Only checked events enter the task.
@MainActor
protocol PaymentSheetClient: AnyObject {
  var hasPaymentOption: Bool { get }
  func load(completion: @escaping @MainActor (Error?) -> Void)
  func present(from presenter: UIViewController, completion: @escaping @MainActor () -> Void)
  func confirm(from presenter: UIViewController, completion: @escaping @Sendable (PaymentSheetOutcome) -> Void)
  func paymentMethod(completion: @escaping @Sendable (String?) -> Void)
}

enum PaymentSheetOutcome: Sendable {
  case completed(paymentMethodID: String?)
  case canceled
  case noSelection
  case failed(Error)
  case loadFailed(Error)
}

/// Owns one sheet from creation through optional payment-method lookup.
/// Cancellation ends observation; it cannot undo a Stripe-accepted setup intent.
@MainActor
final class PaymentSheetOperation {
  private enum Event: Sendable { case loaded(Error?), selected, confirmed(PaymentSheetOutcome), method(String?) }
  private enum Phase { case loading, selecting, confirming, retrieving }
  private var hasPresented = false
  private var identity: String?
  private var generation: UUID?
  private var continuation: AsyncStream<Event>.Continuation?
  private(set) var task: Task<Void, Never>?

  func start(
    clientSecret: String,
    client: PaymentSheetClient,
    presenter: UIViewController,
    retrievePaymentMethod: Bool,
    isCurrent: @escaping @MainActor () -> Bool,
    didPresent: @escaping @MainActor () -> Void = {},
    completed: @escaping @MainActor (PaymentSheetOutcome) -> Void
  ) {
    if self.identity == clientSecret { return }
    guard self.identity == nil else {
      completed(.failed(PaymentSheetOperationError.alreadyInProgress))
      return
    }
    let id = UUID()
    let (stream, continuation) = AsyncStream<Event>.makeStream()
    self.identity = clientSecret
    self.generation = id
    self.continuation = continuation
    self.task = Task { [weak self, weak presenter] in
      var phase = Phase.loading
      for await event in stream {
        guard !Task.isCancelled, let self, self.generation == id else { return }
        guard isCurrent(), let presenter else {
          self.cancelObservation()
          return
        }
        var outcome: PaymentSheetOutcome?
        switch (phase, event) {
        case let (.loading, .loaded(error)):
          if let error { outcome = .loadFailed(error) } else {
            phase = .selecting
            self.hasPresented = true
            client.present(from: presenter) { continuation.yield(.selected) }
            didPresent()
          }
        case (.selecting, .selected):
          if client.hasPaymentOption {
            phase = .confirming
            client.confirm(from: presenter) { continuation.yield(.confirmed($0)) }
          } else { outcome = .noSelection }
        case let (.confirming, .confirmed(result)):
          if case .completed = result, retrievePaymentMethod {
            phase = .retrieving
            client.paymentMethod { continuation.yield(.method($0)) }
          } else { outcome = result }
        case let (.retrieving, .method(method)):
          outcome = .completed(paymentMethodID: method)
        default: break // A duplicate callback cannot advance another phase.
        }
        if let outcome {
          self.finish()
          completed(outcome)
          return
        }
      }
    }
    client.load { continuation.yield(.loaded($0)) }
  }

  func cancelBeforePresentation() {
    guard !self.hasPresented else { return }
    self.cancelObservation()
  }

  func cancelObservation() {
    self.task?.cancel()
    self.finish()
  }

  private func finish() {
    self.hasPresented = false
    self.identity = nil
    self.generation = nil
    self.continuation?.finish()
    self.continuation = nil
    self.task = nil
  }

  deinit {
    self.continuation?.finish()
    self.task?.cancel()
  }
}

private enum PaymentSheetOperationError: LocalizedError {
  case alreadyInProgress
  var errorDescription: String? { "Another payment setup is already in progress." }
}

/// The pinned PaymentSheetLoader completes in Task { @MainActor in }; selection
/// dismissal is UIKit-owned. Keep the SDK controller on that actor, not in a stream.
@MainActor
final class StripePaymentSheetClient: PaymentSheetClient {
  private let data: PaymentSheetSetupData
  private var flow: PaymentSheet.FlowController?
  private var didLoad = false

  init(data: PaymentSheetSetupData) { self.data = data }
  var hasPaymentOption: Bool { self.flow?.paymentOption != nil }

  func load(completion: @escaping @MainActor (Error?) -> Void) {
    PaymentSheet.FlowController.create(
      setupIntentClientSecret: self.data.clientSecret, configuration: self.data.configuration
    ) { [weak self] result in
      guard let self, !self.didLoad else { return }
      self.didLoad = true
      switch result {
      case let .success(flow): self.flow = flow; completion(nil)
      case let .failure(error): completion(error)
      }
    }
  }

  func present(from presenter: UIViewController, completion: @escaping @MainActor () -> Void) {
    self.flow?.presentPaymentOptions(from: presenter, completion: completion)
  }

  func confirm(from presenter: UIViewController, completion: @escaping @Sendable (PaymentSheetOutcome) -> Void) {
    self.flow?.confirm(from: presenter) { result in
      switch result {
      case .completed: completion(.completed(paymentMethodID: nil))
      case .canceled: completion(.canceled)
      case let .failed(error): completion(.failed(error))
      }
    }
  }

  func paymentMethod(completion: @escaping @Sendable (String?) -> Void) {
    STPAPIClient.shared.retrieveSetupIntent(withClientSecret: self.data.clientSecret) { intent, _ in
      // Existing behavior adds the card even when this optional enrichment fails.
      completion(intent?.paymentMethodID)
    }
  }
}
