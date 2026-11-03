@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

final class CreatePaymentSourceInput_ConstructorTests: TestCase {
  func testCreatePaymentSourceInput_Reusable() {
    let input = CreatePaymentSourceInput.input(
      fromToken: "token",
      stripeCardId: "cardId",
      reusable: true
    )

    XCTAssertEqual(input.paymentType, PaymentType.creditCard)
    XCTAssertEqual(input.stripeToken, "token")
    XCTAssertEqual(input.stripeCardId, "cardId")
    XCTAssertEqual(input.reusable, true)
  }

  func testCreatePaymentSourceInput_SingleUse() {
    let input = CreatePaymentSourceInput.input(
      fromToken: "token",
      stripeCardId: "cardId",
      reusable: false
    )

    XCTAssertEqual(input.paymentType, PaymentType.creditCard)
    XCTAssertEqual(input.stripeToken, "token")
    XCTAssertEqual(input.stripeCardId, "cardId")
    XCTAssertEqual(input.reusable, false)
  }
}
