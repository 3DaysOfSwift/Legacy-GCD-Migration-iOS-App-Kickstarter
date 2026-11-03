import Foundation
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
final class PledgePaymentIncrementFormattedTest: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testIncrementFormat() {
    let amount = PledgePaymentIncrementAmount(
      currency: "USD",
      amountFormattedInProjectNativeCurrency: "$20.00"
    )

    let increment = PledgePaymentIncrement(
      amount: amount,
      badge: PledgePaymentIncrement.Badge(
        copy: "Collected",
        variant: .green
      ),
      refundStatus: .unknown, scheduledCollection: TimeInterval(1_240_902_000)
    )

    let incrementFormatted = PledgePaymentIncrementFormatted(from: increment, index: 0)
    XCTAssertEqual(incrementFormatted.incrementChargeNumber, "Charge 1")
    XCTAssertEqual(incrementFormatted.scheduledCollection, "Apr 28, 2009")
    XCTAssertEqual(incrementFormatted.amount, "$20.00")
  }
}
