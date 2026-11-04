import KsApi
import Observation

@MainActor
@Observable
public final class SettingsFollowCellViewModel {
  public init() {}

  public private(set) var followingPrivacyOn: Bool?
  private var user: User?

  public func configureWith(user: User) {
    self.user = user
    if let social = user.social { self.followingPrivacyOn = social }
  }

  public func followTapped(on: Bool) -> User? {
    guard on, var user = self.user else { return nil }
    user[keyPath: UserAttribute.privacy(.following).keyPath] = true
    self.user = user
    return user
  }
}
