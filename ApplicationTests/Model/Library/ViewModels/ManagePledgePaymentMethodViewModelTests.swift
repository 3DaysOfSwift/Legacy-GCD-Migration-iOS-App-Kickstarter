@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class ManagePledgePaymentMethodViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  internal let vm = ManagePledgePaymentMethodViewModel()

  func testPaymentSourceInfo() {
    XCTAssertNil(self.vm.cardImageName)
    XCTAssertNil(self.vm.cardNumberAccessibilityLabel)
    XCTAssertNil(self.vm.cardNumberTextShortStyle)
    XCTAssertNil(self.vm.expirationDateText)
    XCTAssertNil(self.vm.fixButtonHidden)


    let data = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: false,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    self.vm.configureWith(data: data)

    XCTAssertEqual(self.vm.cardImageName, "icon--visa")
    XCTAssertEqual(self.vm.cardNumberAccessibilityLabel, "Visa, Card ending in 1111")
    XCTAssertEqual(self.vm.cardNumberTextShortStyle, "Ending in 1111")
    XCTAssertEqual(self.vm.expirationDateText, "Expires 09/2019")
    XCTAssertEqual(self.vm.fixButtonHidden, true)

  }

  func testApplePay() {
    XCTAssertNil(self.vm.cardImageName)
    XCTAssertNil(self.vm.cardNumberAccessibilityLabel)
    XCTAssertNil(self.vm.cardNumberTextShortStyle)
    XCTAssertNil(self.vm.expirationDateText)
    XCTAssertNil(self.vm.fixButtonHidden)


    let data = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: false,
      expirationDate: "2019-10-19",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .applePay
    )

    self.vm.configureWith(data: data)

    XCTAssertEqual(self.vm.cardImageName, "icon--apple-pay")
    XCTAssertEqual(self.vm.cardNumberAccessibilityLabel, "Apple Pay, Visa, Card ending in 1111")
    XCTAssertEqual(self.vm.cardNumberTextShortStyle, "Ending in 1111")
    XCTAssertEqual(self.vm.expirationDateText, "Expires 10/2019")
    XCTAssertEqual(self.vm.fixButtonHidden, true)

  }

  func testGooglePay() {
    XCTAssertNil(self.vm.cardImageName)
    XCTAssertNil(self.vm.cardNumberAccessibilityLabel)
    XCTAssertNil(self.vm.cardNumberTextShortStyle)
    XCTAssertNil(self.vm.expirationDateText)
    XCTAssertNil(self.vm.fixButtonHidden)


    let data = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: false,
      expirationDate: "2019-10-19",
      lastFour: "4111",
      creditCardType: .visa,
      paymentType: .googlePay
    )

    self.vm.configureWith(data: data)

    XCTAssertEqual(self.vm.cardImageName, "icon--google-pay")
    XCTAssertEqual(self.vm.cardNumberAccessibilityLabel, "Google Pay, Visa, Card ending in 4111")
    XCTAssertEqual(self.vm.cardNumberTextShortStyle, "Ending in 4111")
    XCTAssertEqual(self.vm.expirationDateText, "Expires 10/2019")
    XCTAssertEqual(self.vm.fixButtonHidden, true)

  }

  func testFixButton_IsNotHidden() {
    XCTAssertNil(self.vm.cardImageName)
    XCTAssertNil(self.vm.cardNumberAccessibilityLabel)
    XCTAssertNil(self.vm.cardNumberTextShortStyle)
    XCTAssertNil(self.vm.expirationDateText)
    XCTAssertNil(self.vm.fixButtonHidden)


    let data = ManagePledgePaymentMethodViewData(
      showFixPaymentButton: true,
      expirationDate: "2019-09-30",
      lastFour: "1111",
      creditCardType: .visa,
      paymentType: .creditCard
    )

    self.vm.configureWith(data: data)

    XCTAssertEqual(self.vm.cardImageName, "icon--visa")
    XCTAssertEqual(self.vm.cardNumberAccessibilityLabel, "Visa, Card ending in 1111")
    XCTAssertEqual(self.vm.cardNumberTextShortStyle, "Ending in 1111")
    XCTAssertEqual(self.vm.expirationDateText, "Expires 09/2019")
    XCTAssertEqual(self.vm.fixButtonHidden, false)


    XCTAssertEqual(self.vm.cardImageName, "icon--visa")
    XCTAssertEqual(self.vm.cardNumberAccessibilityLabel, "Visa, Card ending in 1111")
    XCTAssertEqual(self.vm.cardNumberTextShortStyle, "Ending in 1111")
    XCTAssertEqual(self.vm.expirationDateText, "Expires 09/2019")
    XCTAssertEqual(self.vm.fixButtonHidden, false)

  }
}

@MainActor
private final class PaymentMethodDelegateProbe: ManagePledgePaymentMethodViewDelegate {
  var calls = 0
  func managePledgePaymentMethodViewDidTapFixButton(_ view: ManagePledgePaymentMethodView) {
    self.calls += 1
  }
}

@MainActor
final class ManagePledgePaymentMethodActionTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testFixActionNotifiesDelegateForEachTap() {
    let view = ManagePledgePaymentMethodView(frame: .zero)
    let delegate = PaymentMethodDelegateProbe()
    view.delegate = delegate
    view.perform(NSSelectorFromString("fixButtonTapped"))
    view.perform(NSSelectorFromString("fixButtonTapped"))
    XCTAssertEqual(delegate.calls, 2)
  }
}
