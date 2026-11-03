import Foundation
import XCTest
@testable import Library
@testable import Kickstarter_Framework

final class PledgeSummaryIdentifierTests: XCTestCase {
  func testSectionsAndRowIdentityPreserveRewardOrdering() {
    let header = self.model(.header)
    let reward = self.model(.reward)
    let addOn = self.model(.reward)
    let shipping = self.model(.shipping)
    let bonus = self.model(.bonusSupport)
    let snapshot = diffableDataSourceSnapshot(using: header, [reward, addOn, shipping, bonus])
    XCTAssertEqual(snapshot.sectionIdentifiers, [.header, .reward, .addOns, .shipping, .bonusSupport])
    XCTAssertEqual(snapshot.itemIdentifiers, [
      .header(header.id), .reward(reward.id), .addOns(addOn.id), .shipping(shipping.id), .bonusSupport(bonus.id)
    ])
    self.requireSendable(snapshot.itemIdentifiers)
  }

  func testEmptySummaryHasNoSectionsOrItems() {
    let snapshot = diffableDataSourceSnapshot(using: nil, [])
    XCTAssertTrue(snapshot.sectionIdentifiers.isEmpty)
    XCTAssertTrue(snapshot.itemIdentifiers.isEmpty)
  }

  private func requireSendable<T: Sendable>(_: T) {}

  private func model(_ type: PledgeSummaryRewardCellDataType) -> PledgeSummaryRewardCellData {
    PledgeSummaryRewardCellData(
      type: type, headerText: nil, showHeader: false, text: "Reward",
      amount: NSAttributedString(string: "$10"))
  }
}
