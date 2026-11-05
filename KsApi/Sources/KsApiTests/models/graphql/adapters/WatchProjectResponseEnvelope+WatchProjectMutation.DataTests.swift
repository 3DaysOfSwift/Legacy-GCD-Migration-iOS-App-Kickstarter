import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class WatchProjectResponseEnvelope_WatchProjectMutationTests: XCTestCase {
  func test_envelopeFrom() {
    let mock = Mock<GraphAPITestMocks.Mutation>()
    mock.watchProject = Mock<GraphAPITestMocks.WatchProjectPayload>()
    mock.watchProject?.project = Mock<GraphAPITestMocks.Project>()
    mock.watchProject?.project?.id = "id"
    mock.watchProject?.project?.isWatched = true
    mock.watchProject?.project?.watchesCount = 100

    let data = GraphAPI.WatchProjectMutation.Data.from(mock)

    XCTAssertNotNil(data.watchProject)
    XCTAssertNotNil(data.watchProject?.project)

    let envelope = WatchProjectResponseEnvelope.from(data)

    XCTAssertEqual(envelope?.watchProject.project.id, "id")
    XCTAssertEqual(envelope?.watchProject.project.isWatched, true)
    XCTAssertEqual(envelope?.watchProject.project.watchesCount, 100)
  }

  func test_envelopeFrom_ReturnsNil() {
    let erroredData: GraphAPI.UnwatchProjectMutation.Data = try! testGraphObject(jsonString: "{}")
    XCTAssertNil(WatchProjectResponseEnvelope.from(erroredData))
  }
}
