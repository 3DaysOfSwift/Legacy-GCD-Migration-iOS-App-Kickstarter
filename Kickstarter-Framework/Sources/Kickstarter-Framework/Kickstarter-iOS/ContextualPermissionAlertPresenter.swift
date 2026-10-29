import Library
import UIKit

/// UI-owned settling delay after web login dismissal. Equivalent pending prompts
/// share one timer; a different request replaces it. Backgrounding cancels it.
@MainActor
public final class ContextualPermissionAlertPresenter {
  private let sleep: @MainActor (Duration) async throws -> Void
  private var generation = UUID()
  private weak var pendingPresenter: UIViewController?
  private var pendingContext: PushNotificationDialog.Context?
  private(set) var task: Task<Void, Never>?

  public init(sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
    self.sleep = sleep
  }

  public func schedule(
    context: PushNotificationDialog.Context, presenter: UIViewController,
    accepted: @escaping @MainActor () -> Void
  ) {
    if self.task != nil, self.pendingPresenter === presenter, self.pendingContext == context { return }
    self.cancel()
    self.pendingPresenter = presenter
    self.pendingContext = context
    let generation = self.generation
    let sleep = self.sleep
    self.task = Task { [weak self, weak presenter] in
      do { try await sleep(.milliseconds(500)) } catch { return }
      guard !Task.isCancelled, let self, self.generation == generation else { return }
      self.task = nil
      self.pendingPresenter = nil
      self.pendingContext = nil
      guard let presenter, presenter.viewIfLoaded?.window != nil,
        !presenter.isBeingDismissed, presenter.presentedViewController == nil else { return }
      let alert = UIAlertController(title: context.title, message: context.message, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: Strings.project_star_ok(), style: .default) { _ in accepted() })
      alert.addAction(UIAlertAction(title: PushNotificationDialog.titleForDismissal, style: .cancel) { _ in
        PushNotificationDialog.didDenyAccess(for: context)
      })
      presenter.present(alert, animated: true)
    }
  }

  public func cancel() {
    self.generation = UUID()
    self.task?.cancel()
    self.task = nil
    self.pendingPresenter = nil
    self.pendingContext = nil
  }

  deinit { self.task?.cancel() }
}
