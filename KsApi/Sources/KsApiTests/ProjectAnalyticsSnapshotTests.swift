@testable import KsApi
import XCTest

final class ProjectAnalyticsSnapshotTests: XCTestCase {
  func testSnapshotRetainsValuesAfterProjectChanges() {
    var project = Project.template
    let snapshot = ProjectAnalyticsSnapshot(project)
    let originalName = project.name
    project.name = "Changed after response"
    XCTAssertEqual(snapshot.name, originalName)
    XCTAssertEqual(snapshot.id, project.id)
    XCTAssertEqual(snapshot.statsCurrency, project.statsCurrency)
    XCTAssertEqual(snapshot.statsPercentFunded, project.statsPercentFunded)
    XCTAssertEqual(snapshot.personalizationIsBacking, project.personalizationIsBacking)
  }

  func testRelativeDatesRemainCalculatedAtEventTime() throws {
    let project = Project.template
    let snapshot = ProjectAnalyticsSnapshot(project)
    let deadline = try XCTUnwrap(snapshot.datesDeadline)
    let calendar = Calendar(identifier: .gregorian)
    let before = Date(timeIntervalSince1970: deadline - 7200)
    let after = Date(timeIntervalSince1970: deadline + 7200)
    XCTAssertEqual(snapshot.datesHoursRemaining(from: before, using: calendar), 2)
    XCTAssertEqual(snapshot.datesHoursRemaining(from: after, using: calendar), 0)
    XCTAssertEqual(snapshot.datesDuration(using: calendar), project.datesDuration(using: calendar))
  }

  func testSnapshotCanCrossTaskBoundary() async {
    let snapshot = ProjectAnalyticsSnapshot(Project.template)
    let returned = await _Concurrency.Task.detached { snapshot }.value
    XCTAssertEqual(returned.name, snapshot.name)
    XCTAssertEqual(returned.statsPledged, snapshot.statsPledged)
  }
}
