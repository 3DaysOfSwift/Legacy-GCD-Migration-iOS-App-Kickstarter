@testable import Kickstarter_iOS
@testable import KsApi
import XCTest

final class PledgeViewUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testBackerWithCompletedOrderGoesToPledgeManager() {
    var project = Project.template
    project.personalization.isBacking = true
    let backing = Backing.templateMadeWithPledgeManagment
    guard case let .web(url) = pledgeDestination(project: project, backing: backing) else {
      return XCTFail("Expected web pledge management")
    }
    XCTAssertEqual(url, backing.backingDetailsPageRoute)
  }

  func testCreatorGoesToNativePledge() {
    var project = Project.template
    project.personalization.isBacking = false
    let backing = Backing.templateMadeWithPledgeManagment
    guard case let .native(params) = pledgeDestination(project: project, backing: backing) else {
      return XCTFail("Expected native pledge management")
    }
    XCTAssertEqual(params.projectParam, .slug(project.slug))
    XCTAssertEqual(params.backingParam, .id(backing.id))
  }
}
