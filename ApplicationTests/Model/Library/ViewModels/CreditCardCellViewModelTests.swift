@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
internal final class CreditCardCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  internal let vm = CreditCardCellViewModel()

  func testCardInfoForSupportedCards() {
    var display: CreditCardCellViewModel.Display
    display = self.vm.configureWith(creditCard: UserCreditCards.amex)

    XCTAssertEqual(display.image, image(named: "icon--amex"))
    XCTAssertEqual(display.accessibilityLabel, "Amex, Card ending in 8882")
    XCTAssertEqual(display.number, "Card ending in 8882")
    XCTAssertEqual(display.expiration, "Expires 01/2024")

    display = self.vm.configureWith(creditCard: UserCreditCards.discover)

    XCTAssertEqual(display.image, image(named: "icon--discover"))
    XCTAssertEqual(display.accessibilityLabel, "Discover, Card ending in 4242")
    XCTAssertEqual(display.number, "Card ending in 4242")
    XCTAssertEqual(display.expiration, "Expires 03/2022")

    display = self.vm.configureWith(creditCard: UserCreditCards.jcb)

    XCTAssertEqual(display.image, image(named: "icon--jcb"))
    XCTAssertEqual(display.accessibilityLabel, "Jcb, Card ending in 2222")
    XCTAssertEqual(display.number, "Card ending in 2222")
    XCTAssertEqual(display.expiration, "Expires 01/2022")

    display = self.vm.configureWith(creditCard: UserCreditCards.masterCard)

    XCTAssertEqual(display.image, image(named: "icon--mastercard"))
    XCTAssertEqual(display.accessibilityLabel, "Mastercard, Card ending in 0000")
    XCTAssertEqual(display.number, "Card ending in 0000")
    XCTAssertEqual(display.expiration, "Expires 10/2018")

    display = self.vm.configureWith(creditCard: UserCreditCards.visa)

    XCTAssertEqual(display.image, image(named: "icon--visa"))
    XCTAssertEqual(display.accessibilityLabel, "Visa, Card ending in 1111")
    XCTAssertEqual(display.number, "Card ending in 1111")
    XCTAssertEqual(display.expiration, "Expires 09/2019")

    display = self.vm.configureWith(creditCard: UserCreditCards.diners)

    XCTAssertEqual(display.image, image(named: "icon--diners"))
    XCTAssertEqual(display.accessibilityLabel, "Diners, Card ending in 1212")
    XCTAssertEqual(display.number, "Card ending in 1212")
    XCTAssertEqual(display.expiration, "Expires 09/2022")
  }

  func testSelectedCard() {
    let display: CreditCardCellViewModel.Display
    display = self.vm.configureWith(creditCard: UserCreditCards.generic)

    XCTAssertEqual(display.image, image(named: "icon--generic"))
    XCTAssertEqual(display.number, "Card ending in 1882")
    XCTAssertEqual(display.expiration, "Expires 01/2024")
  }

  func testCardInfoForUnsupportedCards() {
    let display: CreditCardCellViewModel.Display
    display = self.vm.configureWith(creditCard: UserCreditCards.generic)

    XCTAssertEqual(display.image, image(named: "icon--generic"))
    XCTAssertEqual(display.number, "Card ending in 1882")
    XCTAssertEqual(display.expiration, "Expires 01/2024")
  }

  func testCardInfoForUnknownCardType() {
    let display: CreditCardCellViewModel.Display
    let unknownCard = UserCreditCards.generic |> \.type .~ nil

    display = self.vm.configureWith(creditCard: unknownCard)

    XCTAssertEqual(display.image, image(named: "icon--generic"))
    XCTAssertEqual(display.accessibilityLabel, "Card ending in 1882")
    XCTAssertEqual(display.number, "Card ending in 1882")
    XCTAssertEqual(display.expiration, "Expires 01/2024")
  }
  func testAddPaymentCellUpdatesLoadingOnReuse() throws {
    let cell = PledgePaymentMethodAddCell(style: .default, reuseIdentifier: nil)
    let indicator = try XCTUnwrap(self.descendants(of: cell).compactMap { $0 as? UIActivityIndicatorView }.first)
    let button = try XCTUnwrap(self.descendants(of: cell).compactMap { $0 as? UIButton }.first)
    cell.configureWith(value: true)
    XCTAssertTrue(indicator.isAnimating)
    XCTAssertTrue(button.isHidden)
    cell.configureWith(value: false)
    XCTAssertFalse(indicator.isAnimating)
    XCTAssertFalse(button.isHidden)
  }

  private func descendants(of view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + self.descendants(of: $0) }
  }

}
