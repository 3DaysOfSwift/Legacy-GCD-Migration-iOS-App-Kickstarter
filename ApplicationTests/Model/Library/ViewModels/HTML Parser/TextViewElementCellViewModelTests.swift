@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import XCTest

@MainActor
internal final class TextElementCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = TextViewElementCellViewModel()


  private let expectedSampleString = "sample attributed string"
  private let expectedBaseFontSize: CGFloat = 16.0
  private let expectedHeader1FontSize: CGFloat = 28.0
  private let expectedHeader2FontSize: CGFloat = 26.0
  private let expectedHeader3FontSize: CGFloat = 24.0
  private let expectedHeader4FontSize: CGFloat = 22.0
  private let expectedHeader5FontSize: CGFloat = 20.0
  private let expectedHeader6FontSize: CGFloat = 18.0
  private var expectedBaseFont = UIFont.ksr_body()
  private var expectedParagraphStyle = NSMutableParagraphStyle()
  private var expectedHeaderFont = UIFont.ksr_body()
  private var expectedFontAttributes = [NSAttributedString.Key: Any]()

  override func setUp() async throws {
    try await super.setUp()

    self.expectedBaseFont = UIFont.ksr_body(size: self.expectedBaseFontSize)
    self.expectedParagraphStyle.minimumLineHeight = 22
    self.expectedFontAttributes = [
      NSAttributedString.Key.font: self.expectedBaseFont,
      NSAttributedString.Key.foregroundColor: LegacyColors.ksr_support_700.uiColor(),
      NSAttributedString.Key.paragraphStyle: self.expectedParagraphStyle
    ]

  }

  func testPlainTextElement() {
    let plainTextComponent = TextComponent(
      text: expectedSampleString,
      link: nil,
      styles: []
    )
    let plainTextElement = TextViewElement(components: [plainTextComponent])
    let expectedPlainAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: plainTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedPlainAttributedText)
  }

  func testBoldTextElement() {
    let boldTextComponent = TextComponent(
      text: expectedSampleString,
      link: nil,
      styles: [.bold]
    )
    let boldTextElement = TextViewElement(components: [boldTextComponent])

    self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedBaseFont.bolded

    let expectedBoldAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: boldTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedBoldAttributedText)
  }

  func testItalicTextElement() {
    let italicTextComponent = TextComponent(
      text: expectedSampleString,
      link: nil,
      styles: [.emphasis]
    )
    let italicTextElement = TextViewElement(components: [italicTextComponent])

    self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedBaseFont.italicized

    let expectedItalicAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: italicTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedItalicAttributedText)
  }

  func testBoldItalicTextElement() {
    let italicTextComponent = TextComponent(
      text: expectedSampleString,
      link: nil,
      styles: [.bold, .emphasis]
    )
    let italicTextElement = TextViewElement(components: [italicTextComponent])

    self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedBaseFont.boldItalic

    let expectedItalicAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: italicTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedItalicAttributedText)
  }

  func testLinkWithStylesTextElement() {
    let linkWithStylesTextComponent = TextComponent(
      text: expectedSampleString,
      link: "https://ksr.com",
      styles: [.bold, .emphasis, .link]
    )
    let linkWithStylesTextElement = TextViewElement(components: [linkWithStylesTextComponent])

    self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedBaseFont.boldItalic
    self.expectedFontAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_create_700
      .uiColor()
    self.expectedFontAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
    self.expectedFontAttributes[NSAttributedString.Key.link] = NSURL(string: "https://ksr.com")!

    let expectedLinkWithStylesAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: linkWithStylesTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedLinkWithStylesAttributedText)
  }

  func testLinkWithNoStylesTextElement() {
    let linkWithNoStylesTextComponent = TextComponent(
      text: expectedSampleString,
      link: "https://ksr.com",
      styles: [.link]
    )
    let linkWithNoStylesTextElement = TextViewElement(components: [linkWithNoStylesTextComponent])

    self.expectedFontAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_create_700
      .uiColor()
    self.expectedFontAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
    self.expectedFontAttributes[NSAttributedString.Key.link] = NSURL(string: "https://ksr.com")!

    let expectedLinkWithNoStylesAttributedText = NSAttributedString(
      string: expectedSampleString,
      attributes: expectedFontAttributes
    )

    self.vm.configureWith(textElement: linkWithNoStylesTextElement)
    XCTAssertEqual(self.vm.attributedText, expectedLinkWithNoStylesAttributedText)
  }

  func testHeaderElements() {
    let headerTypesToFontSizes = [
      TextComponent.TextStyleType.header1: self.expectedHeader1FontSize,
      TextComponent.TextStyleType.header2: self.expectedHeader2FontSize,
      TextComponent.TextStyleType.header3: self.expectedHeader3FontSize,
      TextComponent.TextStyleType.header4: self.expectedHeader4FontSize,
      TextComponent.TextStyleType.header5: self.expectedHeader5FontSize,
      TextComponent.TextStyleType.header6: self.expectedHeader6FontSize
    ]
    _ = headerTypesToFontSizes.map { headerType, fontSize in
      let headerTextComponent = TextComponent(
        text: expectedSampleString,
        link: nil,
        styles: [headerType]
      )
      let headerTextElement = TextViewElement(components: [headerTextComponent])

      self.expectedHeaderFont = UIFont.ksr_body(size: fontSize).bolded
      self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedHeaderFont
      self.expectedFontAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_support_700
        .uiColor()
      self.expectedParagraphStyle.minimumLineHeight = 25
      self.expectedFontAttributes[NSAttributedString.Key.paragraphStyle] = self.expectedParagraphStyle

      let expectedHeaderAttributedText = NSAttributedString(
        string: expectedSampleString,
        attributes: expectedFontAttributes
      )

      self.vm.configureWith(textElement: headerTextElement)
      XCTAssertEqual(self.vm.attributedText, expectedHeaderAttributedText)
    }
  }

  func testListElement() {
    let expectedBulletStartTextValue = ""
    let expectedFirstListValue = "•  sample attributed string\n"
    let expectedSecondListValue = "•  sample attributed string"

    let listTextComponents = [
      TextComponent(
        text: "",
        link: nil,
        styles: [.bulletStart]
      ),
      TextComponent(
        text: expectedFirstListValue,
        link: "https://ksr.com",
        styles: [.link]
      ),
      TextComponent(
        text: expectedSecondListValue,
        link: nil,
        styles: [.bold]
      ),
      TextComponent(
        text: "",
        link: nil,
        styles: [.bulletEnd]
      )
    ]

    let listTextElement = TextViewElement(components: listTextComponents)

    let baseParagraphStyle = self.expectedParagraphStyle
    let baseFontAttributes = self.expectedFontAttributes

    self.expectedParagraphStyle.headIndent = ("" as NSString)
      .size(withAttributes: self.expectedFontAttributes).width
    self.expectedFontAttributes[NSAttributedString.Key.paragraphStyle] = self.expectedParagraphStyle

    let expectedBulletStartAttributedText = NSAttributedString(
      string: expectedBulletStartTextValue,
      attributes: expectedFontAttributes
    )

    self.expectedParagraphStyle = baseParagraphStyle
    self.expectedFontAttributes[NSAttributedString.Key.foregroundColor] = LegacyColors.ksr_create_700
      .uiColor()
    self.expectedFontAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
    self.expectedFontAttributes[NSAttributedString.Key.paragraphStyle] = self.expectedParagraphStyle
    self.expectedFontAttributes[NSAttributedString.Key.link] = NSURL(string: "https://ksr.com")!

    let expectedFirstListAttributedText = NSAttributedString(
      string: expectedFirstListValue,
      attributes: expectedFontAttributes
    )

    self.expectedParagraphStyle = baseParagraphStyle
    self.expectedFontAttributes = baseFontAttributes
    self.expectedFontAttributes[NSAttributedString.Key.paragraphStyle] = self.expectedParagraphStyle
    self.expectedFontAttributes[NSAttributedString.Key.font] = self.expectedBaseFont.bolded

    let expectedSecondListAttributedText = NSAttributedString(
      string: expectedSecondListValue,
      attributes: expectedFontAttributes
    )

    let combinedListAttributedString =
      NSMutableAttributedString(attributedString: expectedBulletStartAttributedText)
    combinedListAttributedString.append(expectedFirstListAttributedText)
    combinedListAttributedString.append(expectedSecondListAttributedText)

    self.vm.configureWith(textElement: listTextElement)
    XCTAssertEqual(self.vm.attributedText, combinedListAttributedString)
  }
}
