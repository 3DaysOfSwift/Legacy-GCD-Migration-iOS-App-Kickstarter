@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class FeatureFlagToolsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let vm = FeatureFlagToolsViewModel(sleep: {})

  func testSortedRecognizedFeaturesAndUpdates() async {
    let keys = Feature.allCases.map(\.rawValue).sorted()
    let original = keys.reduce(into: [String: Bool]()) { $0[$1] = true }
    let config = Config.template |> \.features .~ original.merging(["unknown_feature": false]) { old, _ in old }
    await withEnvironment(config: config) {
      var updated: Features?
      var notifications = 0
      self.vm.onUpdateConfig = { updated = $0 }
      self.vm.onConfigUpdated = { notifications += 1 }
      self.vm.viewDidLoad()
      XCTAssertEqual(self.vm.reloadWithData, keys.map { [$0: true] })
      self.vm.setFeatureAtIndexEnabled(index: 0, isEnabled: true)
      XCTAssertNil(updated)
      self.vm.setFeatureAtIndexEnabled(index: -1, isEnabled: false)
      XCTAssertNil(updated)
      self.vm.setFeatureAtIndexEnabled(index: 0, isEnabled: false)
      XCTAssertEqual(updated?[keys[0]], false)
      XCTAssertEqual(updated?["unknown_feature"], false)
      self.vm.didUpdateConfig()
      XCTAssertEqual(notifications, 1)
      await self.vm.waitForReload()
    }
  }

  func testUnknownFeaturesAreIgnored() {
    XCTAssertTrue(featureEnabledFromDictionaries([["some_unknown_feature": false]]).isEmpty)
    let known = Feature.allCases[0].rawValue
    XCTAssertFalse(featureEnabledFromDictionaries([[known: false]]).isEmpty)
  }
}
