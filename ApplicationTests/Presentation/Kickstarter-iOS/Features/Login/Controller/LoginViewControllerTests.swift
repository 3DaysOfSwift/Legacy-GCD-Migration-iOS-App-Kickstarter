import UIKit
@testable import Kickstarter_iOS
import Foundation



import SnapshotTesting

internal final class LoginViewControllerTests: TestCase {
  func testView() {
    orthogonalCombos(Language.allLanguages, [Device.pad, Device.phone4_7inch, Device.phone5_8inch]).forEach {
      language, device in
      withEnvironment(language: language) {
        let controller = Storyboard.Login.instantiate(LoginViewController.self)
        let (parent, _) = traitControllers(device: device, orientation: .portrait, child: controller)


        assertSnapshot(
          matching: parent.view,
          as: .image(perceptualPrecision: 0.99),
          named: "lang_\(language)_device_\(device)"
        )
      }
    }
  }
}
