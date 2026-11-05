@MainActor
public final class LoadingButtonViewModel {
  public var onLoadingChanged: ((Bool) -> Void)?
  public init() {}
  public func isLoading(_ isLoading: Bool) { self.onLoadingChanged?(isLoading) }
}
