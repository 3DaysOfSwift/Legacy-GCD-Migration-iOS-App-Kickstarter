@testable import Kickstarter_iOS
import UIKit
import XCTest

@MainActor
final class PledgeExpandableHeaderRewardCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testRewardSummaryCellsDisplayAndUpdateValues() {
    let amount = NSAttributedString(string: "$20")
    let data = PledgeSummaryRewardCellData(type: .reward, headerText: nil, showHeader: false, text: "Reward", amount: amount)
    let cells: [UITableViewCell] = [
      PledgeExpandableHeaderRewardCell(style: .default, reuseIdentifier: nil),
      PostCampaignPledgeRewardsSummaryCell(style: .default, reuseIdentifier: nil),
      PledgeExpandableHeaderRewardHeaderCell(style: .default, reuseIdentifier: nil)
    ]
    for cell in cells {
      switch cell {
      case let cell as PledgeExpandableHeaderRewardCell: cell.configureWith(value: data)
      case let cell as PostCampaignPledgeRewardsSummaryCell: cell.configureWith(value: data)
      case let cell as PledgeExpandableHeaderRewardHeaderCell: cell.configureWith(value: data)
      default: XCTFail("Unexpected cell")
      }
      let labels = self.labels(in: cell)
      XCTAssertTrue(labels.contains { $0.text == "Reward" })
      XCTAssertTrue(labels.contains { $0.attributedText?.string == "$20" })
    }
  }

  func testPostCampaignHeaderHidesEmptySubtitle() throws {
    let cell = PostCampaignPledgeRewardsSummaryHeaderCell(style: .default, reuseIdentifier: nil)
    let data = PledgeSummaryRewardCellData(type: .header, headerText: nil, showHeader: false, text: "Details", amount: NSAttributedString(string: ""))
    cell.configureWith(value: data)
    let subtitle = try XCTUnwrap(self.labels(in: cell).first { $0.text == "Details" })
    XCTAssertFalse(subtitle.isHidden)
    cell.configureWith(value: .init(type: .header, headerText: nil, showHeader: false, text: "", amount: NSAttributedString(string: "")))
    XCTAssertTrue(subtitle.isHidden)
  }

  private func labels(in view: UIView) -> [UILabel] {
    let own = (view as? UILabel).map { [$0] } ?? []
    return own + view.subviews.flatMap { self.labels(in: $0) }
  }
}
