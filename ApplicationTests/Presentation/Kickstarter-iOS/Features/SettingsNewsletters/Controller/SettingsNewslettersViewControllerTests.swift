import UIKit
@testable import Kickstarter_iOS

@testable import KsApi


import Prelude
import SnapshotTesting
import XCTest

internal final class SettingsNewslettersViewControllerTests: TestCase {
  override func setUp() async throws {
    try await super.setUp()
    UIView.setAnimationsEnabled(false)
  }

  override func tearDown() async throws {
    UIView.setAnimationsEnabled(true)
    try await super.tearDown()
  }

  func testSettingsNewslettersViewController() {
    let currentUser = User.template

    combos(Language.allLanguages, [Device.phone4_7inch, Device.phone5_8inch, Device.pad]).forEach {
      language, device in

      withEnvironment(currentUser: currentUser, language: language) {
        let controller = Storyboard.SettingsNewsletters.instantiate(
          SettingsNewslettersViewController.self
        )
        let (parent, _) = traitControllers(device: device, orientation: .portrait, child: controller)
        parent.view.frame.size.height = 1_300


        assertSnapshot(
          matching: parent.view,
          as: .image(perceptualPrecision: 0.98),
          named: "lang_\(language)_device_\(device)"
        )
      }
    }
  }
}
