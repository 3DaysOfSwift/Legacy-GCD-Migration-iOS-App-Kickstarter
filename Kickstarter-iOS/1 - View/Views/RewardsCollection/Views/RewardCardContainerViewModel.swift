import KsApi
import Prelude

@MainActor
public final class RewardCardContainerViewModel {
  public struct Display {
    let style: ButtonStyleType
    let enabled: Bool
    let hidden: Bool
    let title: String?
  }
  public var onDisplay: ((Display) -> Void)?
  public var onRewardSelected: ((Int) -> Void)?
  private var currentReward: Reward?
  public init() {}

  public func configureWith(data: RewardCardViewData) {
    self.currentReward = data.reward
    let title = pledgeButtonTitle(data: data)
    self.onDisplay?(Display(
      style: buttonStyleType(data: data),
      enabled: rewardsCarouselCanNavigateToReward(data.reward, in: data.project, selectedShippingLocation: data.currentShippingLocation),
      hidden: title == nil,
      title: title
    ))
  }

  public func pledgeButtonTapped() {
    guard let reward = self.currentReward else { return }
    self.onRewardSelected?(reward.id)
  }

  public func currentReward(is reward: Reward) -> Bool { self.currentReward == reward }
}

// MARK: - Functions

@MainActor
private func pledgeButtonTitle(data: RewardCardViewData) -> String? {
  if currentUserIsCreator(of: data.project) { return nil }

  let projectBackingState = RewardCellProjectBackingStateType.state(with: data.project)
  let isBackingThisReward = userIsBacking(reward: data.reward, inProject: data.project)
  let isRewardAvailable = rewardIsAvailable(data.reward)
  let rewardShipsToLocation = rewardCanShip(data.reward, toLocation: data.currentShippingLocation)

  // If the reward can't ship to your selected location, show the 'not available' string.
  // If you're already backing this reward, fall back to the default behavior (which will show a 'Continue' string).
  if !rewardShipsToLocation, !isBackingThisReward {
    return Strings.Not_available_in_selected_country()
  }

  switch (projectBackingState, isBackingThisReward, isRewardAvailable) {
  case (.backed(.live), false, true):
    return Strings.Select()
  case (.backed(.live), true, _):
    return Strings.Continue()
  case (.backed(.nonLive), true, _):
    return Strings.Selected()
  case (.nonBacked(.live), _, true):
    return Strings.Select()
  case (.backed(.nonLive), false, _),
       (.backed(.inPostCampaignPledgingPhase), _, _),
       (.nonBacked(.nonLive), _, _):
    return nil
  case (_, _, false):
    return Strings.No_longer_available()
  case (.nonBacked(.inPostCampaignPledgingPhase), _, true):
    return Strings.Select()
  }
}

@MainActor
private func buttonStyleType(data: RewardCardViewData) -> ButtonStyleType {
  if currentUserIsCreator(of: data.project) { return .none }

  let projectBackingState = RewardCellProjectBackingStateType.state(with: data.project)
  let isBackingThisReward = userIsBacking(reward: data.reward, inProject: data.project)

  switch projectBackingState {
  case .backed(.live):
    if isBackingThisReward {
      return .green
    }
  case .nonBacked(.live):
    return .green
  case .backed(.nonLive):
    if isBackingThisReward {
      return .black
    }
    return .none
  case .nonBacked(.nonLive),
       .backed(.inPostCampaignPledgingPhase):
    return .none
  case .nonBacked(.inPostCampaignPledgingPhase):
    return .green
  }

  return .green
}
