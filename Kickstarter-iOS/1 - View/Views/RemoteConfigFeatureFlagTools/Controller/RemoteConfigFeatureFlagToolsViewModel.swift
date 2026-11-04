import Experimentation
import Foundation
import KsApi
import Observation

public typealias RemoteConfigFeatures = [(RemoteConfigFeature, Bool)]
public typealias StatsigFeatures = [(StatsigFeature, Bool)]

@MainActor
@Observable
public final class RemoteConfigFeatureFlagToolsViewModel {
  public private(set) var remoteConfigFeatures: RemoteConfigFeatures = []
  public private(set) var statsigFeatures: StatsigFeatures = []
  private var reloadTask: Task<Void, Never>?
  private let sleep: () async throws -> Void

  public init(sleep: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) {
    self.sleep = sleep
  }
  public func viewDidLoad() { self.reload() }
  public func didUpdateUserDefaults() {
    self.reloadTask?.cancel()
    self.reloadTask = Task { [weak self, sleep] in
      do {
        try await sleep()
        try Task.checkCancellation()
        self?.reload()
      } catch { }
    }
  }
  public func setFeatureAtIndexEnabled(index: Int, isEnabled: Bool) {
    guard self.remoteConfigFeatures.indices.contains(index) else { return }
    setValueInUserDefaults(for: self.remoteConfigFeatures[index].0, and: isEnabled)
    self.didUpdateUserDefaults()
  }
  public func setStatsigFeatureAtIndexEnabled(index: Int, isEnabled: Bool) {
    guard self.statsigFeatures.indices.contains(index) else { return }
    setStatsigValueInUserDefaults(for: self.statsigFeatures[index].0, and: isEnabled)
    self.didUpdateUserDefaults()
  }
  private func reload() {
    self.remoteConfigFeatures = RemoteConfigFeature.allCases.map { ($0, isFeatureEnabled($0)) }
    self.statsigFeatures = StatsigFeature.allCases.map { ($0, statsigFeatureEnabled(feature: $0)) }
  }
  internal func waitForReload() async { await self.reloadTask?.value }
}

// MARK: - Private Helpers (Remote Config)

@MainActor
private func isFeatureEnabled(_ feature: RemoteConfigFeature) -> Bool {
  return featureEnabled(feature: feature)
}

@MainActor
private func setValueInUserDefaults(for feature: RemoteConfigFeature, and value: Bool) {
  AppEnvironment.current.userDefaults
    .remoteConfigFeatureFlags[feature.rawValue] = value
}

// MARK: - Private Helpers (Statsig)

@MainActor
private func setStatsigValueInUserDefaults(for feature: StatsigFeature, and value: Bool) {
  AppEnvironment.current.userDefaults
    .statsigFeatureFlags[feature.rawValue] = value
}
