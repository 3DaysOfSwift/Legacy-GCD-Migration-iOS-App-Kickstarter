import KsApi
import Observation
import Prelude
import UIKit

@MainActor
@Observable
public final class SettingsViewModel {
  public private(set) var findFriendsDisabled = false
  public var onReload: ((User) -> Void)?
  public var onRate: ((String) -> Void)?
  public var onLogout: ((DiscoveryParams) -> Void)?
  public var onLogoutPrompt: ((String, String, String) -> Void)?
  public var onNavigate: ((UIViewController) -> Void)?
  private let settings: SettingsFeature
  private let viewControllerFactory: @MainActor (SettingsCellType) -> UIViewController?
  private var reads: [UUID: Task<Void, Never>] = [:]

  public init(_ viewControllerFactory: @escaping @MainActor (SettingsCellType) -> UIViewController?,
              settingsFeature: SettingsFeature? = nil) {
    self.viewControllerFactory = viewControllerFactory
    self.settings = settingsFeature ?? AppModel.shared.settingsFeature
  }

  public func viewDidLoad() { self.loadUser() }
  public func currentUserUpdated() { self.loadUser() }
  public func viewWillAppear() {}

  private func loadUser() {
    if let user = self.settings.sessionFeature.currentUser { self.display(user) }
    let id = UUID()
    self.reads[id] = Task { [weak self, settings] in
      defer { self?.reads[id] = nil }
      guard let user = try? await settings.refresh(), !Task.isCancelled else { return }
      self?.display(user)
    }
  }

  private func display(_ user: User) {
    self.findFriendsDisabled = !(user.social ?? true)
    self.onReload?(user)
  }

  public func settingsCellTapped(cellType: SettingsCellType) {
    if cellType == .logout {
      self.onLogoutPrompt?(Strings.profile_settings_logout_alert_message(),
                           Strings.profile_settings_logout_alert_cancel_button(), Strings.Yes())
    }
    if cellType == .rateInAppStore { self.onRate?(AppEnvironment.current.config?.iTunesLink ?? "") }
    if let controller = self.viewControllerFactory(cellType) { self.onNavigate?(controller) }
  }

  public func logoutConfirmed() {
    self.onLogout?(.defaults |> DiscoveryParams.lens.includePOTD .~ true |> DiscoveryParams.lens.sort .~ .magic)
  }

  public func shouldSelectRow(for cellType: SettingsCellType) -> Bool {
    guard cellType == .findFriends else { return true }
    return AppEnvironment.current.currentUser?.social ?? true
  }

  internal func waitForLoads() async {
    for task in Array(self.reads.values) { await task.value }
  }
}
