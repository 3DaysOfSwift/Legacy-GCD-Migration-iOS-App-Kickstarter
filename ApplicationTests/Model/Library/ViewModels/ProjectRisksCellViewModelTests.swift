@testable import Kickstarter_iOS
import XCTest

@MainActor
internal final class ProjectRisksCellViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConfigurationReplacesDescription() {
    let vm = ProjectRisksCellViewModel()
    XCTAssertNil(vm.descriptionLabelText)
    vm.configureWith(value: "Hello World")
    XCTAssertEqual(vm.descriptionLabelText, "Hello World")
    vm.configureWith(value: "Updated")
    XCTAssertEqual(vm.descriptionLabelText, "Updated")
  }
}
