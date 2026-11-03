@testable import Kickstarter_iOS
// @testable import Kickstarter_Framework


import UIKit
import XCTest

@MainActor
final class UIAlertControllerTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  func testRequiresPopOverConfiguration_iPad_isTrue() {
    let device = MockDevice.init(userInterfaceIdiom: .pad)
    withEnvironment(device: device) {
      XCTAssertTrue(UIAlertController.requiresPopOverConfiguration(.actionSheet))
    }
  }

  func testRequiresPopOverConfiguration_iPhone_isFalse() {
    let device = MockDevice.init(userInterfaceIdiom: .phone)
    withEnvironment(device: device) {
      XCTAssertFalse(UIAlertController.requiresPopOverConfiguration(.actionSheet))
    }
  }
}
