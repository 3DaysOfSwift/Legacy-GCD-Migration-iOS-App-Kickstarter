@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class DeletePaymentSourceEnvelope_PaymentSourceDeleteMutationTests: XCTestCase {
  func testPaymentSource_WithValidData_Success() {
    let env = DeletePaymentMethodEnvelope.from(DeletePaymentSourceMutationTemplate.valid.data)

    XCTAssertEqual(env?.storedCards.count, 2)

    guard let firstCard = env?.storedCards.first,
          let secondCard = env?.storedCards.last else {
      XCTFail()

      return
    }

    XCTAssertEqual(firstCard.id, "69021326")
    XCTAssertEqual(firstCard.expirationDate, "2023-02-01")
    XCTAssertEqual(firstCard.lastFour, "4242")
    XCTAssertEqual(firstCard.type, .visa)
    XCTAssertEqual(secondCard.id, "69021329")
    XCTAssertEqual(secondCard.expirationDate, "2024-01-01")
    XCTAssertEqual(secondCard.lastFour, "4243")
    XCTAssertEqual(secondCard.type, .discover)
  }

  func testPaymentSource_WithInvalidData_Error() {
    XCTAssertNil(DeletePaymentMethodEnvelope.from(DeletePaymentSourceMutationTemplate.errored.data))
  }
}
