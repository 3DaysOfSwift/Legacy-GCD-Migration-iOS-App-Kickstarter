import AVFoundation
import Foundation

/// Immutable AVFoundation events cross the callback boundary. UI/analytics inputs
/// are delivered by one main-actor consumer, never from a KVO callback.
enum ProjectVideoEvent: Sendable {
  case duration(CMTime)
  case rate(Double, CMTime)
  case completion(UUID)
}

@MainActor
protocol ProjectVideoEventSource: AnyObject {
  var events: AsyncStream<ProjectVideoEvent> { get }
  func setBoundary(_ time: CMTime, id: UUID)
  func stop()
}

@MainActor
final class ProjectVideoObservation {
  private let source: any ProjectVideoEventSource
  private let receive: @MainActor (ProjectVideoEvent) -> Void
  private var boundaryID = UUID()
  private var stopped = false
  private(set) var task: Task<Void, Never>?

  init(source: any ProjectVideoEventSource, receive: @escaping @MainActor (ProjectVideoEvent) -> Void) {
    self.source = source
    self.receive = receive
    let events = source.events
    self.task = Task { [weak self] in
      for await event in events {
        guard !Task.isCancelled, let self, !self.stopped else { return }
        if case let .completion(id) = event, id != self.boundaryID { continue }
        self.receive(event)
      }
    }
  }

  func setCompletionBoundary(_ time: CMTime) {
    guard !self.stopped, time.isNumeric, time.seconds.isFinite, time >= .zero else { return }
    self.boundaryID = UUID()
    self.source.setBoundary(time, id: self.boundaryID)
  }

  func stop() {
    guard !self.stopped else { return }
    self.stopped = true
    self.task?.cancel()
    self.source.stop()
  }

  deinit { self.task?.cancel() }
}

/// AVPlayer KVO and boundary observers have no equivalent native async sequence.
/// Tokens belong to this exact player, and replacement always removes the old token.
@MainActor
final class NativeProjectVideoEvents: ProjectVideoEventSource {
  let events: AsyncStream<ProjectVideoEvent>
  private let continuation: AsyncStream<ProjectVideoEvent>.Continuation
  private let player: AVPlayer
  private var observations: [NSKeyValueObservation] = []
  private var boundaryToken: Any?

  init(player: AVPlayer) {
    self.player = player
    (self.events, self.continuation) = AsyncStream<ProjectVideoEvent>.makeStream()
    let continuation = self.continuation
    self.observations = [
      player.observe(\.currentItem?.duration, options: [.initial, .new]) { player, _ in
        guard let duration = player.currentItem?.duration,
          duration.isNumeric, duration.seconds.isFinite, duration > .zero else { return }
        continuation.yield(.duration(duration))
      },
      player.observe(\.rate, options: [.new]) { player, _ in
        guard let time = player.currentItem?.currentTime(), time.isNumeric else { return }
        continuation.yield(.rate(Double(player.rate), time))
      }
    ]
  }

  func setBoundary(_ time: CMTime, id: UUID) {
    if let token = self.boundaryToken { self.player.removeTimeObserver(token) }
    let continuation = self.continuation
    self.boundaryToken = self.player.addBoundaryTimeObserver(
      forTimes: [NSValue(time: time)], queue: .main
    ) { continuation.yield(.completion(id)) }
  }

  func stop() {
    self.observations.forEach { $0.invalidate() }
    self.observations.removeAll()
    self.continuation.finish()
    if let token = self.boundaryToken { self.player.removeTimeObserver(token) }
    self.boundaryToken = nil
    self.player.pause()
    self.player.currentItem?.cancelPendingSeeks()
  }

  deinit {
    self.observations.forEach { $0.invalidate() }
    self.continuation.finish()
    let player = self.player
    let token = self.boundaryToken
    // Finite platform-resource cleanup by value also supports synchronous UIKit
    // release on the current runtime; never capture the deinitializing owner.
    Task { @MainActor in
      if let token { player.removeTimeObserver(token) }
      player.pause()
      player.currentItem?.cancelPendingSeeks()
      player.replaceCurrentItem(with: nil)
    }
  }
}
