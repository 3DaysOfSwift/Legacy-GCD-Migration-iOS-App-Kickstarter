@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class ImageViewElementCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = ImageViewElementCellViewModel()


  private let expectedImage = UIImage(systemName: "camera")!
  private let expectedSampleString = "sample attributed string"
  private let expectedBaseFontSize: CGFloat = 12.0
  private var expectedBaseFont = UIFont.ksr_body()
  private var expectedParagraphStyle = NSMutableParagraphStyle()
  private var expectedFontAttributes = [NSAttributedString.Key: Any]()

  override func setUp() async throws {
    try await super.setUp()

    self.expectedBaseFont = UIFont.ksr_body(size: self.expectedBaseFontSize).italicized
    self.expectedParagraphStyle.minimumLineHeight = 22
    self.expectedFontAttributes = [
      NSAttributedString.Key.font: self.expectedBaseFont,
      NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_400.uiColor(),
      NSAttributedString.Key.paragraphStyle: self.expectedParagraphStyle
    ]

  }

  func testPlainAttributedTextElement_Success() {
    let nonLinkCaptionImageViewElement = ImageViewElement(
      src: "https://image.com",
      href: nil,
      caption: expectedSampleString
    )
    let expectedNonLinkAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(imageElement: nonLinkCaptionImageViewElement, image: nil)
    XCTAssertEqual(self.vm.attributedText, expectedNonLinkAttributedText)
  }

  func testLinkTextElement_Success() {
    let linkCaptionImageViewElement = ImageViewElement(
      src: "https://image.com",
      href: "https://link.com",
      caption: expectedSampleString
    )

    self.expectedFontAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
    self.expectedFontAttributes[NSAttributedString.Key.link] = URL(string: "https://link.com")!
    self.expectedFontAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_create_700
      .uiColor()

    let expectedLinkAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(imageElement: linkCaptionImageViewElement, image: nil)
    XCTAssertEqual(self.vm.attributedText, expectedLinkAttributedText)
  }

  func testImageViewElementData_Success() {
    let dataImageViewElement = ImageViewElement(
      src: "https://image.com",
      href: "https://link.com",
      caption: expectedSampleString
    )

    self.vm.configureWith(imageElement: dataImageViewElement, image: nil)

    XCTAssertNil(self.vm.image)

    self.vm.configureWith(imageElement: dataImageViewElement, image: self.expectedImage)

    XCTAssertEqual(self.vm.image, self.expectedImage)
  }
}
