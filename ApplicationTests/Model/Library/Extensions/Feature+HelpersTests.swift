@testable import Kickstarter_iOS
import Foundation
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class FeatureHelpersTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  // MARK: - Segment

  func testFeatureSegment_isTrue() {
    let config = Config.template
      |> \.features .~ [Feature.segment.rawValue: true]

    withEnvironment(config: config) {
      XCTAssertTrue(featureSegmentIsEnabled())
    }
  }

  func testFeatureSegment_isFalse() {
    let config = Config.template
      |> \.features .~ [Feature.segment.rawValue: false]

    withEnvironment(config: config) {
      XCTAssertFalse(featureSegmentIsEnabled())
    }
  }

  func testFeatureSegment_isFalse_whenNil() {
    withEnvironment(config: .template) {
      XCTAssertFalse(featureSegmentIsEnabled())
    }
  }
}
