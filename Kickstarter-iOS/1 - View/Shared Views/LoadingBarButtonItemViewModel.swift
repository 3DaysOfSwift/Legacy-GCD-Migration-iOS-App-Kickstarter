@MainActor
public final class LoadingBarButtonItemViewModel {
  public var onEnabledChanged: ((Bool) -> Void)?
  public var onTitleChanged: ((String) -> Void)?
  public var onAnimatingChanged: ((Bool) -> Void)?
  public init() {}
  public func setIsEnabled(isEnabled: Bool) { self.onEnabledChanged?(isEnabled) }
  public func setTitle(title: String) { self.onTitleChanged?(title) }
  public func setAnimating(isAnimating: Bool) { self.onAnimatingChanged?(isAnimating) }
}
