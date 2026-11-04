import KDS
import KsApi
import Observation
import UIKit

@MainActor
@Observable
public final class ImageViewElementCellViewModel {
  public init() {}
  public private(set) var attributedText: NSAttributedString?
  public private(set) var image: UIImage?
  public func configureWith(imageElement: ImageViewElement, image: UIImage?) {
    self.attributedText = attributedTextFrom(imageElement)
    self.image = image
  }
}

@MainActor
private func attributedTextFrom(_ imageElement: ImageViewElement) -> NSAttributedString? {
  guard let captionText = imageElement.caption, !captionText.isEmpty else {
    return nil
  }

  let completedAttributedText = NSMutableAttributedString()
  let paragraphStyle = NSMutableParagraphStyle()
  let currentAttributedText = NSMutableAttributedString(string: captionText)
  let fullRange = (captionText as NSString).localizedStandardRange(of: captionText)
  let baseFontSize: CGFloat = 12.0
  let baseFont = UIFont.ksr_body(size: baseFontSize).italicized
  paragraphStyle.minimumLineHeight = 22
  let baseFontAttributes = [
    NSAttributedString.Key.font: baseFont,
    NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_400.uiColor(),
    NSAttributedString.Key.paragraphStyle: paragraphStyle
  ]

  var combinedAttributes: [NSAttributedString.Key: Any] = baseFontAttributes

  if let validURLString = imageElement.href,
     let validURL = URL(string: validURLString) {
    combinedAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_create_700.uiColor()
    combinedAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
    combinedAttributes[NSAttributedString.Key.link] = validURL
  }

  currentAttributedText.addAttributes(combinedAttributes, range: fullRange)
  completedAttributedText.append(currentAttributedText)

  return completedAttributedText
}
