@testable import Kickstarter_iOS
@testable import KsApi
import Experimentation
import XCTest

@MainActor
final class RemoteConfigFlagToolsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = RemoteConfigFeatureFlagToolsViewModel(sleep: {})

  func testLoadsRemoteValuesAndPersistsOverride() async {
    let feature = RemoteConfigFeature.floatingTabBar
    let remote = MockRemoteConfigClient()
    remote.features[feature.rawValue] = false
    await withEnvironment(remoteConfigClient: remote, userDefaults: self.userDefaults) {
      self.vm.viewDidLoad()
      guard let index = self.vm.remoteConfigFeatures.firstIndex(where: { $0.0 == feature }) else {
        return XCTFail("Feature missing")
      }
      XCTAssertFalse(self.vm.remoteConfigFeatures[index].1)
      self.vm.setFeatureAtIndexEnabled(index: index, isEnabled: true)
      await self.vm.waitForReload()
      let stored = self.userDefaults.dictionary(
        forKey: "com.kickstarter.KeyValueStoreType.remoteConfigFeatureFlags"
      ) as? [String: Bool]
      XCTAssertEqual(stored?[feature.rawValue], true)
      XCTAssertEqual(remote.features[feature.rawValue], false)
    }
  }

  func testStatsigToggleWritesOverride() async {
    await withEnvironment(userDefaults: self.userDefaults) {
      self.vm.viewDidLoad()
      guard let feature = self.vm.statsigFeatures.first?.0 else { return XCTFail("No Statsig features") }
      self.vm.setStatsigFeatureAtIndexEnabled(index: 0, isEnabled: true)
      await self.vm.waitForReload()
      XCTAssertEqual(AppEnvironment.current.userDefaults.statsigFeatureFlags[feature.rawValue], true)
    }
  }

  func testOutOfRangeIndicesDoNotCrash() {
    self.vm.viewDidLoad()
    self.vm.setFeatureAtIndexEnabled(index: -1, isEnabled: true)
    self.vm.setStatsigFeatureAtIndexEnabled(index: -1, isEnabled: true)
  }
}
