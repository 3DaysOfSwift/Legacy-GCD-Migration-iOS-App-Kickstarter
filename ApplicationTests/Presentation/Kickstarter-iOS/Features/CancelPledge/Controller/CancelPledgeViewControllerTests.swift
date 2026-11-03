import UIKit
@testable import Kickstarter_iOS
import Foundation

@testable import KsApi


import SnapshotTesting
import XCTest

final class CancelPledgeViewControllerTests: TestCase {
  override func setUp() async throws {
    try await super.setUp()
    UIView.setAnimationsEnabled(false)
  }

  override func tearDown() async throws {
    UIView.setAnimationsEnabled(true)
    try await super.tearDown()
  }

  func testCancelPledge() {
    let project = Project.cosmicSurgery

    let data = CancelPledgeViewData(
      project: project,
      projectName: project.name,
      omitUSCurrencyCode: project.stats.omitUSCurrencyCode,
      backingId: String(project.personalization.backing?.id ?? 0),
      pledgeAmount: 10
    )

    combos(Language.allLanguages, Device.allCases).forEach { language, device in
      withEnvironment(language: language) {
        let controller = CancelPledgeViewController.instantiate()
        controller.configure(with: data)
        let (parent, _) = traitControllers(device: device, orientation: .portrait, child: controller)

        assertSnapshot(
          matching: parent.view,
          as: .image(perceptualPrecision: 0.98),
          named: "lang_\(language)_device_\(device)"
        )
      }
    }
  }
}
