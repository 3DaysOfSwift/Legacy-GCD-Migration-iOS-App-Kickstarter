import Foundation

public typealias PledgeDisclaimerViewData = (
  iconImageName: String,
  attributedText: NSAttributedString
)

@MainActor
public final class PledgeDisclaimerViewModel {
  public var onLinkTapped: ((URL) -> Void)?
  public init() {}
  public func linkTapped(url: URL) { self.onLinkTapped?(url) }
}
