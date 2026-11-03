@testable import Kickstarter_iOS


import Stripe
import XCTest

final class STPPaymentHandler_StripePaymentHandlerActionStatusTests: TestCase {
  func testTypeMapping() {
    XCTAssertEqual(
      STPPaymentHandlerActionStatus.succeeded.status,
      StripePaymentHandlerActionStatus.succeeded
    )

    XCTAssertEqual(
      STPPaymentHandlerActionStatus.canceled.status,
      StripePaymentHandlerActionStatus.canceled
    )

    XCTAssertEqual(
      STPPaymentHandlerActionStatus.failed.status,
      StripePaymentHandlerActionStatus.failed
    )
  }
}
