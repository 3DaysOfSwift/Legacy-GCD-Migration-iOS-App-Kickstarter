import AVFoundation
import Foundation
import ReactiveSwift

// Resource handles own their SDK deregistration. ScopedDisposable runs cleanup on
// release without entering an actor-isolated owner's destructor. NotificationCenter
// and AVPlayer perform token removal; no application state is touched by cleanup.
extension NotificationCenter {
  func scopedObserver(
    forName name: Notification.Name?, object: Any?, queue: OperationQueue?,
    using block: @escaping @Sendable (Notification) -> Void
  ) -> ScopedDisposable<AnyDisposable> {
    let token = self.addObserver(forName: name, object: object, queue: queue, using: block)
    return ScopedDisposable(AnyDisposable { self.removeObserver(token) })
  }
}

extension AVPlayer {
  func scopedPeriodicTimeObserver(
    forInterval interval: CMTime, queue: DispatchQueue?, using block: @escaping @Sendable (CMTime) -> Void
  ) -> ScopedDisposable<AnyDisposable> {
    let token = self.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: block)
    return ScopedDisposable(AnyDisposable { self.removeTimeObserver(token) })
  }
}
