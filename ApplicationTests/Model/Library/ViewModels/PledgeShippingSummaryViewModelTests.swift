@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

@MainActor
final class PledgeShippingSummaryViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testShippingAmountAndLocationWithCurrencyCode() {
    let data = PledgeShippingSummaryViewData(
      locationName: "Canada", omitUSCurrencyCode: false,
      currencyCode: Project.Country.us.currencyCode, total: 100
    )
    let presentation = PledgeShippingSummaryPresentation(data: data)
    XCTAssertEqual(presentation.location, "Canada")
    XCTAssertEqual(presentation.amount?.string, "+ US$ 100.00")
  }

  func testShippingAmountWithoutCurrencyCode() {
    let data = PledgeShippingSummaryViewData(
      locationName: "Canada", omitUSCurrencyCode: true,
      currencyCode: Project.Country.us.currencyCode, total: 100
    )
    XCTAssertEqual(PledgeShippingSummaryPresentation(data: data).amount?.string, "+$100.00")
  }
}
