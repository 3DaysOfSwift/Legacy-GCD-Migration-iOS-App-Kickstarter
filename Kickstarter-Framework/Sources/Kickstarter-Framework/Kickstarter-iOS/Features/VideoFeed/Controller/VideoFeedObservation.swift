import Foundation
import Observation

/// One UI subscription per output. Re-arm only the output that changed, after
/// its willSet notification has finished. Acknowledgements are observed too.
@MainActor
final class VideoFeedObservation {
  enum Output: CaseIterable, Sendable { case fetchedItems, items, error, login, saveError }
  private let read: @MainActor (Output) -> Void
  private let changed: @MainActor (Output) -> Void
  private var continuation: AsyncStream<Output>.Continuation?
  private(set) var task: Task<Void, Never>?
  private var generation = UUID()

  init(read: @escaping @MainActor (Output) -> Void, changed: @escaping @MainActor (Output) -> Void) {
    self.read = read
    self.changed = changed
  }

  func start() {
    guard self.task == nil else { return }
    let (events, continuation) = AsyncStream<Output>.makeStream()
    self.continuation = continuation
    let generation = self.generation
    for output in Output.allCases { self.arm(output, continuation: continuation) }
    self.task = Task { [weak self] in
      for await output in events {
        guard !Task.isCancelled, let self, self.generation == generation else { return }
        self.arm(output, continuation: continuation)
        self.changed(output)
      }
    }
  }

  func stop() {
    self.generation = UUID()
    self.continuation?.finish()
    self.continuation = nil
    self.task?.cancel()
    self.task = nil
  }

  private func arm(_ output: Output, continuation: AsyncStream<Output>.Continuation) {
    withObservationTracking { self.read(output) } onChange: { continuation.yield(output) }
  }

  deinit {
    self.continuation?.finish()
    self.task?.cancel()
  }
}
