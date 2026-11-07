import UIKit

public extension UIPageViewController {
  /// UIKit lifecycle and controller-action subscribers call this on MainActor.
  /// Preserve synchronous installation/completion; no blocking queue hop is needed.
  @MainActor
  func ksr_setViewControllers(
    _ viewControllers: [UIViewController]?,
    direction: UIPageViewController.NavigationDirection,
    animated: Bool,
    completion: ((Bool) -> Void)? = nil
  ) {
    self.setViewControllers(
      viewControllers,
      direction: direction,
      animated: animated,
      completion: completion
    )
  }
}
