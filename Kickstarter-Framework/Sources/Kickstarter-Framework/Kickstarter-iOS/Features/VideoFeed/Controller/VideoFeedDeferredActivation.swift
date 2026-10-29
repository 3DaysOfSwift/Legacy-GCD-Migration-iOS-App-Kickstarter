import Foundation

/// One pending UI activation. New layout/appearance requests replace old ones;
/// disappearance/backgrounding cancels them. The caller rechecks visible UI state.
@MainActor
final class VideoFeedDeferredActivation {
  private let nextTurn: @MainActor () async -> Void
  private var generation = UUID()
  private(set) var task: Task<Void, Never>?

  init(nextTurn: @escaping @MainActor () async -> Void = { await Task.yield() }) {
    self.nextTurn = nextTurn
  }

  func schedule(_ activate: @escaping @MainActor () -> Void) {
    self.cancel()
    let generation = self.generation
    let nextTurn = self.nextTurn
    self.task = Task { [weak self] in
      await nextTurn()
      guard !Task.isCancelled, let self, self.generation == generation else { return }
      self.task = nil
      activate()
    }
  }

  func cancel() {
    self.generation = UUID()
    self.task?.cancel()
    self.task = nil
  }

  deinit { self.task?.cancel() }
}
