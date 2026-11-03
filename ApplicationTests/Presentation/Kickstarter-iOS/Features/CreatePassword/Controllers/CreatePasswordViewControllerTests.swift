import UIKit
@testable import Kickstarter_iOS

import XCTest

final class CreatePasswordViewControllerTests: XCTestCase {
  func testViewDidLoadAddsChildTableViewController() {
    let vc = CreatePasswordViewController.instantiate()
    _ = vc.view

    XCTAssertTrue(vc.children.first is CreatePasswordTableViewController)
  }
}
