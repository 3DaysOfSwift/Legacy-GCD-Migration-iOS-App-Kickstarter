import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class SettingsRecommendationsCellViewModel {
  public private(set) var recommendationsOn: Bool?
  public var onSaved: (() -> Void)?
  public var onError: ((String) -> Void)?
  private let feature: SettingsFeature
  private let sleep: (TimeInterval) async throws -> Void
  private var initialUser: User?
  private var currentUser: User?
  private var revision = 0
  private var tasks: [UUID: Task<Void, Never>] = [:]

  public init(feature: SettingsFeature? = nil, sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
    if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
  }) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.sleep = sleep
  }

  public func configureWith(user: User) {
    self.initialUser = user
    self.currentUser = user
    if let optedOut = user.optedOutOfRecommendations { self.recommendationsOn = !optedOut }
  }

  public func recommendationsTapped(on: Bool) {
    guard let source = self.initialUser, var current = self.currentUser else { return }
    let previous = current
    current[keyPath: UserAttribute.privacy(.recommendations).keyPath] = !on
    self.currentUser = current
    if let optedOut = current.optedOutOfRecommendations { self.recommendationsOn = !optedOut }
    self.revision += 1
    let revision = self.revision
    let feature = self.feature
    let sleep = self.sleep
    let delay = AppEnvironment.current.apiDelayInterval.searchDelaySeconds
    let id = UUID()
    let task = Task { [weak self] in
      defer { self?.tasks[id] = nil }
      let result: Result<User, Error>
      do {
        result = .success(try await feature.save([.init(.privacy(.recommendations), !on)], from: source))
      } catch {
        result = .failure(error)
      }
      do { try await sleep(delay) } catch { return }
      guard let self, self.revision == revision else { return }
      switch result {
      case .success:
        self.onSaved?()
      case let .failure(error):
        guard !(error is CancellationError) else { return }
        self.currentUser = previous
        if let optedOut = previous.optedOutOfRecommendations { self.recommendationsOn = !optedOut }
        self.onError?((error as? ErrorEnvelope)?.errorMessages.first ?? Strings.profile_settings_error())
      }
    }
    self.tasks[id] = task
  }

  internal func waitForSaves() async {
    let tasks = Array(self.tasks.values)
    for task in tasks { await task.value }
  }
}
