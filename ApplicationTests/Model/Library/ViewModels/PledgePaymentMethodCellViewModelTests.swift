@testable import Kickstarter_iOS
import KDS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class PledgePaymentMethodCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = PledgePaymentMethodCellViewModel()

  private let cardImageAlpha = PaymentRecorder<CGFloat>()
  private let cardImageName = PaymentRecorder<String>()
  private let cardNumberAccessibilityLabel = PaymentRecorder<String>()
  private let cardNumberTextShortStyle = PaymentRecorder<String>()
  private let checkmarkImageHidden = PaymentRecorder<Bool>()
  private let checkmarkImageName = PaymentRecorder<String>()
  private let expirationDateText = PaymentRecorder<String>()
  private let lastFourLabelTextColor = PaymentRecorder<UIColor>()
  private let selectionStyle = PaymentRecorder<UITableViewCell.SelectionStyle>()
  private let unavailableCardLabelHidden = PaymentRecorder<Bool>()
  private let unavailableCardText = PaymentRecorder<String>()

  private func configureWith(value: PledgePaymentMethodCellData) {
    let display = self.vm.configureWith(value: value)
    self.cardImageName.record(display.cardImageName)
    self.cardImageAlpha.record(display.cardImageAlpha)
    self.cardNumberAccessibilityLabel.record(display.cardNumberAccessibilityLabel)
    self.cardNumberTextShortStyle.record(display.cardNumberTextShortStyle)
    self.expirationDateText.record(display.expirationDateText)
    self.checkmarkImageName.record(display.checkmarkImageName)
    self.checkmarkImageHidden.record(display.checkmarkImageHidden)
    self.lastFourLabelTextColor.record(display.lastFourLabelTextColor)
    self.selectionStyle.record(display.selectionStyle)
    self.unavailableCardLabelHidden.record(display.unavailableCardLabelHidden)
    if let text = display.unavailableCardText { self.unavailableCardText.record(text) }
  }

  private func setSelectedCardId(_ id: String) {
    if let name = self.vm.setSelectedCardId(id) { self.checkmarkImageName.record(name) }
  }

  func testSelectionSetBeforeConfiguration() {
    XCTAssertNil(self.vm.setSelectedCardId(UserCreditCards.generic.id))
    let display = self.vm.configureWith(value: (UserCreditCards.generic, true, false, "US", false))
    XCTAssertEqual(display.checkmarkImageName, "icon-payment-method-selected")
  }

  func testCardInfoForSupportedCards() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.amex, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--amex")
    self.cardNumberAccessibilityLabel.assertLastValue("Amex, Card ending in 8882")
    self.cardNumberTextShortStyle.assertLastValue("•••• 8882")
    self.expirationDateText.assertLastValue("Expires 01/2024")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.selectionStyle.assertLastValue(.default)
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.discover, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--discover")
    self.cardNumberAccessibilityLabel.assertLastValue("Discover, Card ending in 4242")
    self.cardNumberTextShortStyle.assertLastValue("•••• 4242")
    self.expirationDateText.assertLastValue("Expires 03/2022")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.selectionStyle.assertLastValue(.default)
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.jcb, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--jcb")
    self.cardNumberAccessibilityLabel.assertLastValue("Jcb, Card ending in 2222")
    self.cardNumberTextShortStyle.assertLastValue("•••• 2222")
    self.expirationDateText.assertLastValue("Expires 01/2022")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.selectionStyle.assertLastValue(.default)
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.masterCard, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--mastercard")
    self.cardNumberAccessibilityLabel.assertLastValue("Mastercard, Card ending in 0000")
    self.cardNumberTextShortStyle.assertLastValue("•••• 0000")
    self.expirationDateText.assertLastValue("Expires 10/2018")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.selectionStyle.assertLastValue(.default)
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.visa, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--visa")
    self.cardNumberAccessibilityLabel.assertLastValue("Visa, Card ending in 1111")
    self.cardNumberTextShortStyle.assertLastValue("•••• 1111")
    self.expirationDateText.assertLastValue("Expires 09/2019")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.selectionStyle.assertLastValue(.default)
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.diners, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertLastValue("icon--diners")
    self.cardNumberAccessibilityLabel.assertLastValue("Diners, Card ending in 1212")
    self.cardNumberTextShortStyle.assertLastValue("•••• 1212")
    self.expirationDateText.assertLastValue("Expires 09/2022")
    self.cardImageAlpha.assertLastValue(1.0)
    self.checkmarkImageName.assertLastValue("icon-payment-method-unselected")
    self.selectionStyle.assertLastValue(.default)
    self.checkmarkImageHidden.assertLastValue(false)
    self.lastFourLabelTextColor.assertLastValue(LegacyColors.ksr_support_700.uiColor())
    self.unavailableCardLabelHidden.assertLastValue(true)
    self.unavailableCardText.assertDidNotEmitValue()
  }

  func testUnselectingCard() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.generic, true, true, "Brooklyn, NY", false))
    self.setSelectedCardId(UserCreditCards.diners.id)

    self.cardImageName.assertValues(["icon--generic"])
    self.cardImageAlpha.assertValues([1.0])
    self.cardNumberAccessibilityLabel.assertValues(["Card ending in 1882"])
    self.cardNumberTextShortStyle.assertValues(["•••• 1882"])
    self.checkmarkImageName.assertValues(["icon-payment-method-selected", "icon-payment-method-unselected"])
    self.checkmarkImageHidden.assertValues([false])
    self.expirationDateText.assertValues(["Expires 01/2024"])
    self.lastFourLabelTextColor.assertValues([LegacyColors.ksr_support_700.uiColor()])
    self.selectionStyle.assertValues([.default])
    self.unavailableCardLabelHidden.assertValues([true])
    self.unavailableCardText.assertValues([])
  }

  func testSelectingCard() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.generic, true, false, "Brooklyn, NY", false))
    self.setSelectedCardId(UserCreditCards.generic.id)

    self.cardImageName.assertValues(["icon--generic"])
    self.cardImageAlpha.assertValues([1.0])
    self.cardNumberAccessibilityLabel.assertValues(["Card ending in 1882"])
    self.cardNumberTextShortStyle.assertValues(["•••• 1882"])
    self.checkmarkImageName.assertValues(["icon-payment-method-unselected", "icon-payment-method-selected"])
    self.checkmarkImageHidden.assertValues([false])
    self.expirationDateText.assertValues(["Expires 01/2024"])
    self.lastFourLabelTextColor.assertValues([LegacyColors.ksr_support_700.uiColor()])
    self.selectionStyle.assertValues([.default])
    self.unavailableCardLabelHidden.assertValues([true])
    self.unavailableCardText.assertValues([])
  }

  func testUnavailableCard() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    self.configureWith(value: (UserCreditCards.generic, false, true, "Brooklyn, NY", false))
    self.setSelectedCardId(UserCreditCards.generic.id)

    self.cardImageName.assertValues(["icon--generic"])
    self.cardImageAlpha.assertValues([0.5])
    self.cardNumberAccessibilityLabel.assertValues(["Card ending in 1882"])
    self.cardNumberTextShortStyle.assertValues(["•••• 1882"])
    self.checkmarkImageName.assertValues(["icon-payment-method-selected", "icon-payment-method-selected"])
    self.checkmarkImageHidden.assertValues([true])
    self.expirationDateText.assertValues(["Expires 01/2024"])
    self.lastFourLabelTextColor.assertValues([LegacyColors.ksr_support_400.uiColor()])
    self.selectionStyle.assertValues([.none])
    self.unavailableCardLabelHidden.assertValues([false])
    self.unavailableCardText.assertValues(
      ["You can’t use this credit card to back a project from Brooklyn, NY."]
    )
  }

  func testCardInfoForUnknownCardType() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    let unknownCard = UserCreditCards.generic |> \.type .~ nil

    self.configureWith(value: (unknownCard, true, false, "Brooklyn, NY", false))

    self.cardImageName.assertValues(["icon--generic"])
    self.cardImageAlpha.assertValues([1.0])
    self.cardNumberAccessibilityLabel.assertValues(["Card ending in 1882"])
    self.cardNumberTextShortStyle.assertValues(["•••• 1882"])
    self.checkmarkImageName.assertValues(["icon-payment-method-unselected"])
    self.checkmarkImageHidden.assertValues([false])
    self.expirationDateText.assertValues(["Expires 01/2024"])
    self.lastFourLabelTextColor.assertValues([LegacyColors.ksr_support_700.uiColor()])
    self.selectionStyle.assertValues([.default])
    self.unavailableCardLabelHidden.assertValues([true])
    self.unavailableCardText.assertValues([])
  }

  func testCardInfoForErroredCard() {
    self.cardImageName.assertDidNotEmitValue()
    self.cardImageAlpha.assertDidNotEmitValue()
    self.cardNumberAccessibilityLabel.assertDidNotEmitValue()
    self.cardNumberTextShortStyle.assertDidNotEmitValue()
    self.checkmarkImageName.assertDidNotEmitValue()
    self.checkmarkImageHidden.assertDidNotEmitValue()
    self.expirationDateText.assertDidNotEmitValue()
    self.lastFourLabelTextColor.assertDidNotEmitValue()
    self.selectionStyle.assertDidNotEmitValue()
    self.unavailableCardLabelHidden.assertDidNotEmitValue()
    self.unavailableCardText.assertDidNotEmitValue()

    let data = PledgePaymentMethodCellData(
      card: UserCreditCards.visa,
      isEnabled: true,
      isSelected: false,
      projectCountry: "Brooklyn, NY",
      isErroredPaymentMethod: true
    )

    self.configureWith(value: data)

    self.cardImageName.assertValues(["icon--visa"])
    self.cardImageAlpha.assertValues([1.0])
    self.cardNumberAccessibilityLabel.assertValues(["Visa, Card ending in 1111"])
    self.cardNumberTextShortStyle.assertValues(["•••• 1111"])
    self.checkmarkImageName.assertValues(["icon-payment-method-unselected"])
    self.checkmarkImageHidden.assertValues([false])
    self.expirationDateText.assertValues(["Expires 09/2019"])
    self.lastFourLabelTextColor.assertValues([LegacyColors.ksr_support_700.uiColor()])
    self.selectionStyle.assertValues([.default])
    self.unavailableCardLabelHidden.assertValues([false])
    self.unavailableCardText.assertValues(["Retry or select another method."])
  }
}

private final class PaymentRecorder<Value: Equatable> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertLastValue(_ expected: Value, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.last, expected, file: file, line: line)
  }
  func assertValues(_ expected: [Value], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, file: file, line: line)
  }
}
