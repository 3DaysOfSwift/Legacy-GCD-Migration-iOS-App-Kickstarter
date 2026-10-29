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
