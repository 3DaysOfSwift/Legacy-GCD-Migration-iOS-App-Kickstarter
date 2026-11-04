import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class SettingsPrivacyViewModel {
  public var onReload: ((User) -> Void)?
  public var onUserUpdated: ((User) -> Void)?
  public var onError: ((String) -> Void)?
  public var onResetFollowing: (() -> Void)?
  public var onFocusFollowing: (() -> Void)?
  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var initialUser: User?
  private var currentUser: User?
  private var rollbackUser: User?
  private var loadTask: Task<Void, Never>?
  private var saves: [UUID: Task<Void, Never>] = [:]
  private var revision = 0

  public init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }

  public func viewDidLoad() {
    if let user = self.feature.sessionFeature.currentUser { self.display(user) }
    self.loadTask?.cancel()
    self.loadTask = Task { [weak self, feature] in
      guard let user = try? await feature.refresh(), !Task.isCancelled else { return }
      self?.display(user)
    }
  }

  private func display(_ user: User) {
    self.initialUser = user
    self.currentUser = user
    self.rollbackUser = nil
    self.onReload?(user)
  }

  public func didCancelSocialOptOut() {
    self.onResetFollowing?()
    self.focusFollowingIfNeeded()
  }

  public func didConfirmSocialOptOut() {
    self.edit(.privacy(.following), value: false)
    self.focusFollowingIfNeeded()
  }

  public func privateProfileToggled(on: Bool) {
    self.edit(.privacy(.showPublicProfile), value: !on)
  }

  public func didUpdate(user: User) {
    self.save([.init(.privacy(.following), user.social)], source: user, previous: self.rollbackUser)
  }

  private func focusFollowingIfNeeded() {
    if AppEnvironment.current.isVoiceOverRunning() { self.onFocusFollowing?() }
  }

  private func edit(_ attribute: UserAttribute, value: Bool) {
    guard let source = self.initialUser, var current = self.currentUser else { return }
    let previous = current
    self.rollbackUser = previous
    current[keyPath: attribute.keyPath] = value
    self.currentUser = current
    self.save([.init(attribute, value)], source: source, previous: previous)
  }

  private func save(_ changes: [SettingsFeature.Change], source: User, previous: User?) {
    self.revision += 1
    let revision = self.revision
    let id = UUID()
    let feature = self.feature
    let sleep = self.sleep
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    self.saves[id] = Task { [weak self] in
      defer { self?.saves[id] = nil }
      let result: Result<User, Error>
      do { result = .success(try await feature.save(changes, from: source)) }
      catch { result = .failure(error) }
      do { try await sleep(delay) } catch { return }
      guard let self, self.revision == revision else { return }
      switch result {
      case let .success(user): self.onUserUpdated?(user)
      case let .failure(error):
        guard !(error is CancellationError) else { return }
        self.onError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.profile_settings_error())
        if let previous { self.onUserUpdated?(previous) }
      }
    }
  }

  internal func waitForLoad() async { await self.loadTask?.value }
  internal func waitForSaves() async {
    for task in Array(self.saves.values) { await task.value }
  }
}
