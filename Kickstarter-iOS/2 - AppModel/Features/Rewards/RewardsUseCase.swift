import Foundation

@MainActor
public final class RewardsUseCase {
  private var hasTokenValue = false
  private var secretRewardToken: String?
  var onLogin: ((LoginIntent) -> Void)?
  var onRewards: (() -> Void)?

  public init() {}

  func configure(secretRewardToken: String?) {
    self.hasTokenValue = true
    self.secretRewardToken = secretRewardToken
  }

  func goToRewardsTapped() {
    guard self.hasTokenValue else { return }
    if let token = self.secretRewardToken, !token.isEmpty, AppEnvironment.current.currentUser == nil {
      self.onLogin?(.backProject)
    } else {
      self.onRewards?()
    }
  }
}
