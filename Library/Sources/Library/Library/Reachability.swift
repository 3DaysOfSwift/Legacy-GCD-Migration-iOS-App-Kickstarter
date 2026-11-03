import Foundation
import ReactiveSwift
import SystemConfiguration

public enum Reachability: Sendable {
  case wifi
  case wwan
  case none

  @MainActor public static var current: Reachability {
    AppModel.shared.appLifecycleFeature.connectivity
  }

  /// Compatibility at the UI boundary. Main-thread subscribers keep their immediate
  /// initial value; other subscribers enter the actor before accessing feature state.
  public static var signalProducer: SignalProducer<Reachability, Never> {
    makeSignalProducer { AppModel.shared.appLifecycleFeature.connectivityProducer }
  }

  static func makeSignalProducer(
    connectivity: @escaping @MainActor @Sendable () -> SignalProducer<Reachability, Never>
  ) -> SignalProducer<Reachability, Never> {
    SignalProducer { observer, lifetime in
      let subscription = ReachabilitySubscription(observer: observer, lifetime: lifetime)
      if Thread.isMainThread {
        MainActor.assumeIsolated { subscription.start(connectivity) }
      } else {
        let task = Task { @MainActor in
          guard !Task.isCancelled else { return }
          subscription.start(connectivity)
        }
        subscription.cancelOnEnd(task)
      }
    }
  }

  static func from(flags: SCNetworkReachabilityFlags) -> Reachability {
    // Preserve the existing classification, including WWAN precedence.
    if flags.contains(.isWWAN) { return .wwan }
    return flags.contains(.reachable) ? .wifi : .none
  }
}

public protocol ReachabilityMonitoring: AnyObject {
  var initial: Reachability { get }
  var updates: AsyncStream<Reachability> { get }
}

/// SystemConfiguration has no native async sequence. Its required serial callback
/// queue only yields immutable values; the application state belongs to the Feature.
/// The handle and C callback context remain retained until this owner is released.
public final class SystemReachabilityMonitor: ReachabilityMonitoring {
  public let initial: Reachability
  public let updates: AsyncStream<Reachability>
  private let reference: SCNetworkReachability
  private let continuation: AsyncStream<Reachability>.Continuation

  public init?() {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout.size(ofValue: address))
    address.sin_family = sa_family_t(AF_INET)
    guard let reference = withUnsafePointer(to: &address, { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        SCNetworkReachabilityCreateWithAddress(nil, $0)
      }
    }) else { return nil }
    var flags = SCNetworkReachabilityFlags()
    guard SCNetworkReachabilityGetFlags(reference, &flags) else { return nil }
    let (updates, continuation) = AsyncStream<Reachability>.makeStream()
    self.reference = reference
    self.initial = Reachability.from(flags: flags)
    self.updates = updates
    self.continuation = continuation

    let contextOwner = ReachabilityCallback(continuation: continuation)
    var context = SCNetworkReachabilityContext(
      version: 0, info: Unmanaged.passUnretained(contextOwner).toOpaque(),
      retain: { info in
        _ = Unmanaged<ReachabilityCallback>.fromOpaque(info).retain()
        return info
      }, release: { info in
        Unmanaged<ReachabilityCallback>.fromOpaque(info).release()
      }, copyDescription: nil)
    let registered = withExtendedLifetime(contextOwner) {
      SCNetworkReachabilitySetCallback(reference, { _, flags, info in
        guard let info else { return }
        Unmanaged<ReachabilityCallback>.fromOpaque(info).takeUnretainedValue()
          .continuation.yield(Reachability.from(flags: flags))
      }, &context)
    }
    guard registered,
      SCNetworkReachabilitySetDispatchQueue(reference, DispatchQueue(label: "com.kickstarter.reachability"))
    else {
      SCNetworkReachabilitySetCallback(reference, nil, nil)
      continuation.finish()
      return nil
    }
  }

  deinit {
    SCNetworkReachabilitySetDispatchQueue(self.reference, nil)
    SCNetworkReachabilitySetCallback(self.reference, nil, nil)
    self.continuation.finish()
  }
}

private final class ReachabilityCallback: Sendable {
  let continuation: AsyncStream<Reachability>.Continuation
  init(continuation: AsyncStream<Reachability>.Continuation) { self.continuation = continuation }
}

/// Narrow compatibility boundary for the pinned ReactiveSwift version, which has
/// no Sendable annotations. These immutable references come only from the normal
/// SignalProducer initializer: its Signal.pipe serializes event delivery; Lifetime
/// uses CompositeDisposable's atomic state and synchronized disposable collection.
/// Arbitrary standalone observers must not be placed in this wrapper. UI values
/// are emitted on MainActor; disposal can originate on the subscriber's executor.
private final class ReachabilitySubscription: @unchecked Sendable {
  private let observer: Signal<Reachability, Never>.Observer
  private let lifetime: Lifetime

  init(observer: Signal<Reachability, Never>.Observer, lifetime: Lifetime) {
    self.observer = observer
    self.lifetime = lifetime
  }

  @MainActor func start(_ connectivity: () -> SignalProducer<Reachability, Never>) {
    guard !self.lifetime.hasEnded else { return }
    let disposable = connectivity().start(self.observer)
    self.lifetime.observeEnded { disposable.dispose() }
  }

  func cancelOnEnd(_ task: Task<Void, Never>) {
    self.lifetime.observeEnded { task.cancel() }
  }
}
