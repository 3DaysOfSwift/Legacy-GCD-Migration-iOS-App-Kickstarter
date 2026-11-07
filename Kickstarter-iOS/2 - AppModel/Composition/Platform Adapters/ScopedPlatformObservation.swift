import AVFoundation
import Foundation

/// Owns a platform observer until explicitly disposed or released.
final class PlatformObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var cleanup: (() -> Void)?

  init(_ cleanup: @escaping () -> Void) { self.cleanup = cleanup }

  func dispose() {
    self.lock.lock()
    let cleanup = self.cleanup
    self.cleanup = nil
    self.lock.unlock()
    cleanup?()
  }

  deinit { self.dispose() }
}

extension NotificationCenter {
  func scopedObserver(
    forName name: Notification.Name?, object: Any?, queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> PlatformObservation {
    let token = self.addObserver(forName: name, object: object, queue: queue, using: block)
    return PlatformObservation { self.removeObserver(token) }
  }
}

extension AVPlayer {
  func scopedPeriodicTimeObserver(
    forInterval interval: CMTime, queue: DispatchQueue?, using block: @escaping @Sendable (CMTime) -> Void
  ) -> PlatformObservation {
    let token = self.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: block)
    return PlatformObservation { self.removeTimeObserver(token) }
  }
}
