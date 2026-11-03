@testable import Kickstarter_Framework
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import SnapshotTesting
import UIKit

final class BetaToolsViewControllerTests: TestCase {
  override func setUp() async throws {
    try await super.setUp()
    UIView.setAnimationsEnabled(false)
  }

  override func tearDown() async throws {
    UIView.setAnimationsEnabled(true)
    try await super.tearDown()
  }

  func testBetaToolsViewController() {
    let service = MockService(serverConfig: ServerConfig.staging)

    withEnvironment(apiService: service, language: .en, mainBundle: MockBundle()) {
      let controller = BetaToolsViewController.instantiate()
      let (parent, _) = traitControllers(device: .phone4_7inch, orientation: .portrait, child: controller)

      self.scheduler.run()

      assertSnapshot(matching: parent.view, as: .image)
    }
  }
}
