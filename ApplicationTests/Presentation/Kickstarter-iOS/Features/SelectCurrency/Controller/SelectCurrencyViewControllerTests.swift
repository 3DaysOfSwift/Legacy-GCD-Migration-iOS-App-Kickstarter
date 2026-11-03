import UIKit
@testable import Kickstarter_iOS

@testable import KsApi


import Prelude
import SnapshotTesting
import XCTest

internal final class SelectCurrencyViewControllerTests: TestCase {
  override func setUp() async throws {
    try await super.setUp()
    UIView.setAnimationsEnabled(false)
  }

  override func tearDown() async throws {
    UIView.setAnimationsEnabled(true)
    try await super.tearDown()
  }

  func testView() {
    combos(Language.allLanguages, Device.allCases)
      .forEach { language, device in
        withEnvironment(language: language) {
          let vc = SelectCurrencyViewController.instantiate()
          vc.configure(with: .USD)
          let (parent, _) = traitControllers(device: device, orientation: .portrait, child: vc)

          assertSnapshot(
            matching: parent.view,
            as: .image(perceptualPrecision: 0.98),
            named: "lang_\(language)_device_\(device)"
          )
        }
      }
  }
}
