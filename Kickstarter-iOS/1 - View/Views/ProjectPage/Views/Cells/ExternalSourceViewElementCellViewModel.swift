import KsApi
import Observation

@MainActor
@Observable
public final class ExternalSourceViewElementCellViewModel {
  public init() {}
  public private(set) var htmlText: String?
  public private(set) var contentHeight: Int?

  public func configureWith(element: ExternalSourceViewElement) {
    guard !element.embeddedURLString.isEmpty else {
      self.htmlText = nil
      self.contentHeight = nil
      return
    }
    self.htmlText = element.embeddedURLString
    self.contentHeight = element.embeddedURLContentHeight
  }
}
