import Foundation
import UIKit

/// Owns the legacy 10ms refresh-layout delay. Ending a load or removing the
/// control cancels its pending start, so a fast response cannot restart it later.
@MainActor
public final class DeferredRefreshControl: UIRefreshControl {
  private var pendingStart: Task<Void, Never>?
  private var requestID = UUID()
  private let delay: @MainActor () async throws -> Void

  public override init(frame: CGRect) {
    self.delay = { try await Task.sleep(for: .milliseconds(10)) }
    super.init(frame: frame)
  }

  public required init?(coder: NSCoder) {
    self.delay = { try await Task.sleep(for: .milliseconds(10)) }
    super.init(coder: coder)
  }

  internal init(delay: @escaping @MainActor () async throws -> Void) {
    self.delay = delay
    super.init(frame: .zero)
  }

  @discardableResult
  public func beginRefreshingAfterLayout() -> Task<Void, Never> {
    if let pendingStart { return pendingStart }
    let id = UUID()
    self.requestID = id
    let delay = self.delay
    let task = Task { [weak self] in
      defer { if self?.requestID == id { self?.pendingStart = nil } }
      do { try await delay() } catch { return }
      guard !Task.isCancelled, let self, self.requestID == id else { return }
      if let scrollView = self.superview as? UIScrollView {
        scrollView.layoutIfNeeded()
        if scrollView.contentOffset.y == 0 {
          scrollView.setContentOffset(
            .init(x: scrollView.contentOffset.x, y: -self.frame.height), animated: true
          )
        }
      }
      self.beginRefreshing()
    }
    self.pendingStart = task
    return task
  }

  public override func endRefreshing() {
    self.cancelPendingStart()
    super.endRefreshing()
  }

  public override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if self.superview == nil { self.cancelPendingStart() }
  }

  private func cancelPendingStart() {
    self.requestID = UUID()
    self.pendingStart?.cancel()
    self.pendingStart = nil
  }

  deinit { self.pendingStart?.cancel() }
}
