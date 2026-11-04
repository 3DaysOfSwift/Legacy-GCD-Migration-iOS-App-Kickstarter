import Foundation
import KsApi
import Observation

public typealias FeatureEnabled = (feature: Feature, isEnabled: Bool)

@MainActor
@Observable
public final class FeatureFlagToolsViewModel {
  public private(set) var reloadWithData: [Features] = []
  public var onUpdateConfig: ((Features) -> Void)?
  public var onConfigUpdated: (() -> Void)?
  private var sortedFeatures: [(key: String, value: Bool)] = []
  private var reloadTask: Task<Void, Never>?
  private let sleep: () async throws -> Void

  public init(sleep: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) {
    self.sleep = sleep
  }

  public func viewDidLoad() { self.reload() }
  public func didUpdateConfig() {
    self.onConfigUpdated?()
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
    guard self.sortedFeatures.indices.contains(index),
          self.sortedFeatures[index].value != isEnabled,
          var features = AppEnvironment.current.config?.features else { return }
    features[self.sortedFeatures[index].key] = isEnabled
    self.onUpdateConfig?(features)
  }
  private func reload() {
    guard let features = AppEnvironment.current.config?.features else { return }
    self.sortedFeatures = features.filter { Feature(rawValue: $0.key) != nil }
      .sorted { $0.key < $1.key }
    self.reloadWithData = self.sortedFeatures.map { [$0.key: $0.value] }
  }
  internal func waitForReload() async { await self.reloadTask?.value }
}

public func featureEnabledFromDictionaries(_ dictionaryArray: [Features]) -> [FeatureEnabled] {
  return dictionaryArray.compactMap { dictionary -> (Feature, Bool)? in
    dictionary.compactMap { key, value in
      guard let feature = Feature(rawValue: key) else { return nil }
      return (feature, value)
    }
    .first
  }
}
