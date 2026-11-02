import KsApi
import Library
import Prelude
import XCTest

@MainActor
final class CreditCard_UtilsTests: XCTestCase {
  func testExpirationDate() {
    let card = UserCreditCards.masterCard
      |> \.expirationDate .~ "2019-09-20"

    XCTAssertEqual(card.expirationDate(), "09/2019")
  }
}
