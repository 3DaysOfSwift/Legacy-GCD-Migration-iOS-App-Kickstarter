@testable import Kickstarter_iOS
import Experimentation


import XCTest

@MainActor
final class StatsigFeatureHelpersTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testFeatureIsFalse_whenStatsigFeatureOff() {
    let mockStatsigClient = MockStatsigWrapper()
    mockStatsigClient.features[.videoFeed] = false

    withEnvironment(statsigClient: mockStatsigClient) {
      XCTAssertFalse(featureVideoFeedEnabled())
    }
  }

  func testFeatureIsTrue_whenStatsigFeatureOn() {
    let mockStatsigClient = MockStatsigWrapper()
    mockStatsigClient.features[.videoFeed] = true

    withEnvironment(statsigClient: mockStatsigClient) {
      XCTAssertTrue(featureVideoFeedEnabled())
    }
  }
}
