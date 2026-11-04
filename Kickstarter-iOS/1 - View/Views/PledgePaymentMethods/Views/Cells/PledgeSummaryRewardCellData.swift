import Foundation

public enum PledgeSummaryRewardCellDataType {
  case header
  case reward
  case shipping
  case bonusSupport
}

public struct PledgeSummaryRewardCellData: Hashable {
  public let id = UUID()
  public let type: PledgeSummaryRewardCellDataType?
  public let headerText: NSAttributedString?
  public let showHeader: Bool
  public let text: String
  public let amount: NSAttributedString
}

