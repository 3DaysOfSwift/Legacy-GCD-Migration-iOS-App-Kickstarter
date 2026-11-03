@testable import Kickstarter_iOS


import Prelude
import XCTest

@MainActor
final class RemoteConfigFeatureHelpersTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func assert(
    featureFlagIsFalse checkFeatureFlag: @MainActor () -> Bool,
    whenRemoteConfigFeatureIsFalse feature: RemoteConfigFeature
  ) {
    let mockRemoteConfigClient = MockRemoteConfigClient()
      |> \.features .~ [feature.rawValue: false]

    withEnvironment(remoteConfigClient: mockRemoteConfigClient) {
      XCTAssertFalse(checkFeatureFlag())
    }
  }

  func assert(
    featureFlagIsTrue checkFeatureFlag: @MainActor () -> Bool,
    whenRemoteConfigFeatureIsTrue feature: RemoteConfigFeature
  ) {
    let mockRemoteConfigClient = MockRemoteConfigClient()
      |> \.features .~ [feature.rawValue: true]

    withEnvironment(remoteConfigClient: mockRemoteConfigClient) {
      XCTAssertTrue(checkFeatureFlag())
    }
  }

  func testUseKeychainForOAuthTokenEnabled_RemoteConfig_FeatureFlag_False() {
    self
      .assert(
        featureFlagIsFalse: featureUseKeychainForOAuthTokenEnabled,
        whenRemoteConfigFeatureIsFalse: .useKeychainForOAuthToken
      )
  }

  func testUseKeychainForOAuthTokenEnabled_RemoteConfig_FeatureFlag_True() {
    self
      .assert(
        featureFlagIsTrue: featureUseKeychainForOAuthTokenEnabled,
        whenRemoteConfigFeatureIsTrue: .useKeychainForOAuthToken
      )
  }
}
