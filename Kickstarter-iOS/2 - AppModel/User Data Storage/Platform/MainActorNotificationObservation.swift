import Foundation

/// Owns notifications whose publishers are confined to MainActor (for example,
/// application session and saved-project events). Delivery stays synchronous,
/// preserving event order and avoiding transfer of heterogeneous userInfo values.
/// Do not use this adapter for notifications posted by background SDK callbacks.
@MainActor
public final class MainActorNotificationObservation: NSObject {
  private let center: NotificationCenter
  private let handler: @MainActor (Notification) -> Void
  private var active = true

  public init(
    center: NotificationCenter = .default,
    name: Notification.Name,
    handler: @escaping @MainActor (Notification) -> Void
  ) {
    self.center = center
    self.handler = handler
    super.init()
    center.addObserver(self, selector: #selector(self.receive(_:)), name: name, object: nil)
  }

  @objc private func receive(_ notification: Notification) {
    MainActor.assertIsolated()
    guard self.active else { return }
    self.handler(notification)
  }

  public func cancel() {
    self.active = false
    self.center.removeObserver(self)
  }

  deinit { self.center.removeObserver(self) }
}

/// A payload-free notification from an arbitrary publisher, delivered on MainActor.
/// The callback only yields a Sendable signal. The owner cancels queued delivery on
/// release; neither the Notification nor its SDK-owned payload crosses actors.
@MainActor
public final class MainActorNotificationSignalObservation: NSObject {
  private let center: NotificationCenter
  nonisolated private let continuation: AsyncStream<Void>.Continuation
  private var delivery: Task<Void, Never>?

  public init(
    center: NotificationCenter = .default,
    name: Notification.Name,
    handler: @escaping @MainActor () -> Void
  ) {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    self.center = center
    self.continuation = continuation
    super.init()
    center.addObserver(self, selector: #selector(self.receive(_:)), name: name, object: nil)
    self.delivery = Task { @MainActor in
      for await _ in stream {
        guard !Task.isCancelled else { break }
        handler()
      }
    }
  }

  @objc nonisolated private func receive(_: Notification) {
    self.continuation.yield(())
  }

  public func cancel() {
    self.center.removeObserver(self)
    self.delivery?.cancel()
    self.delivery = nil
    self.continuation.finish()
  }

  deinit {
    self.delivery?.cancel()
    self.continuation.finish()
    self.center.removeObserver(self)
  }
}
