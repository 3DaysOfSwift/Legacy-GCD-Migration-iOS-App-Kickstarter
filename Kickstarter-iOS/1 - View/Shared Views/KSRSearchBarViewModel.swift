@MainActor
public final class KSRSearchBarViewModel {
  public var onFocusChanged: ((Bool) -> Void)?
  public var onResign: (() -> Void)?
  public var onTextChanged: ((String) -> Void)?
  public init() {}
  public func cancelButtonPressed() {
    self.onTextChanged?("")
    self.onResign?()
  }
  public func clearSearchText() { self.onTextChanged?("") }
  public func searchFieldDidBeginEditing() { self.onFocusChanged?(true) }
  public func searchTextEditingDidEnd() {
    self.onFocusChanged?(false)
    self.onResign?()
  }
  public func searchTextChanged(_ searchText: String) { self.onTextChanged?(searchText) }
}
