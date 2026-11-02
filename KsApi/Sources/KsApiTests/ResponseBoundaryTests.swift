import GraphAPI
import ApolloTestSupport
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class ResponseBoundaryTests: XCTestCase {
  func testProfilePageCopiesCardsAndPaginationAcrossTaskBoundary() async throws {
    let mock = GraphAPI.ProjectCardFragment.mockProjectsConnectionQuery(numberOfProjects: 2)
    let data = GraphAPI.FetchMyBackedProjectsQuery.Data.from(mock)
    let page = ProfileProjectsResponse(data)
    let transferred = await Task.detached { page }.value
    let nodes = data.projects?.nodes?.compactMap { $0 } ?? []
    XCTAssertFalse(nodes.isEmpty)
    XCTAssertEqual(transferred.projects.map(\.pid), nodes.map { $0.fragments.projectCardFragment.pid })
    XCTAssertEqual(transferred.cursor,
      data.projects?.pageInfo.hasNextPage == true ? data.projects?.pageInfo.endCursor : nil)
  }

  func testMissingSavedPageIsEmptyAndTerminal() async {
    let page = ProfileProjectsResponse(GraphAPI.FetchMySavedProjectsQuery.Data(projects: nil))
    let transferred = await Task.detached { page }.value
    XCTAssertTrue(transferred.projects.isEmpty)
    XCTAssertNil(transferred.cursor)
  }

  func testMissingSearchPageIsEmptyAndTerminal() async {
    let page = SearchPageResponse(GraphAPI.SearchQuery.Data(projects: nil))
    let transferred = await Task.detached { page }.value
    XCTAssertTrue(transferred.projects.isEmpty)
    XCTAssertFalse(transferred.hasNextPage)
    XCTAssertNil(transferred.endCursor)
    XCTAssertEqual(transferred.totalCount, 0)
  }

  func testRichTextExampleRetainsDetachedElements() async {
    let project = RichTextExampleResponse(id: "sample", name: "Example", richText: .init(items: []))
    let transferred = await Task.detached { project }.value
    XCTAssertEqual(transferred.id, "sample")
    XCTAssertEqual(transferred.name, "Example")
    XCTAssertEqual(transferred.richText, [])
  }
  func testSessionSetupKeepsFlagsAndDecodingAcrossTaskBoundary() async throws {
    let data = Data(#"{"email":"demo@example.test","enabledFeatures":["ios_mixpanel"],"ppoHasAction":true,"backingActionCount":3}"#.utf8)
    var setup = try JSONDecoder().decode(GraphUserSetup.self, from: data)
    let snapshot = setup
    let transferred = await Task.detached { snapshot }.value
    setup.enabledFeatures = []
    XCTAssertEqual(transferred.enabledFeatures, [.iosMixpanel])
    XCTAssertEqual(transferred.backingActionCount, 3)
    XCTAssertTrue(setup.enabledFeatures.isEmpty)
  }

}
