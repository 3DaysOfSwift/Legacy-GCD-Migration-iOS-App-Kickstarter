import Foundation

public final class RewardCellViewModel {
  public init() {}

  func backerLabelHidden(for data: RewardCardViewData) -> Bool {
    !userIsBacking(reward: data.reward, inProject: data.project)
  }
}
