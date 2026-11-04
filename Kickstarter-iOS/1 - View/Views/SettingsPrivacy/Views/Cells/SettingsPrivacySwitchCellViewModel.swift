import KsApi
import Observation

@MainActor
@Observable
public final class SettingsPrivacySwitchCellViewModel {
  public init() {}

  public private(set) var privacySwitchIsOn = false

  public func configure(with user: User) {
    self.privacySwitchIsOn = !(user.showPublicProfile ?? false)
  }
}
