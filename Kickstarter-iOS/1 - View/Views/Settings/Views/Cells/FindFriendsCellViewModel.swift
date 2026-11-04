import KsApi
import Observation

@MainActor
@Observable
public final class FindFriendsCellViewModel {
  public init() {}

  public private(set) var isDisabled: Bool?

  public func configure(with user: User?) {
    guard let followingEnabled = user?.social else { return }
    self.isDisabled = !followingEnabled
  }
}
