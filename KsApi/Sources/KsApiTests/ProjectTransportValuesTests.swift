import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class ProjectTransportValuesTests: XCTestCase {
  func testProjectSnapshotCrossesTaskBoundaryIndependently() async {
    var original = Project.template
    let snapshot = original
    let transferred = await Task.detached { snapshot }.value
    original.name = "Changed on caller"
    XCTAssertNotEqual(transferred.name, original.name)
    XCTAssertEqual(transferred.rewardData.rewards, original.rewardData.rewards)
    XCTAssertEqual(transferred.creator, original.creator)
  }

  func testStoryCopiesRichTextAndPreservesMissingVersusEmpty() async {
    let missing = ProjectStoryElements(htmlViewElements: [])
    let empty = ProjectStoryElements(htmlViewElements: [], richText: .init(items: []))
    let transferred = await Task.detached { empty }.value
    XCTAssertNil(missing.richText)
    XCTAssertEqual(transferred.richText, [])
  }

  func testSortedResponseKeepsInsertionSeparateFromParsedRewards() async throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "FetchSortedProjectRewardsById", withExtension: "json"))
    let data: GraphAPI.FetchSortedProjectRewardsByIdQuery.Data = try testGraphObject(
      fromResource: url, variables: ["projectId": 1_480_998_200, "location": "DE",
                                    "includeShippingRules": true, "includeLocalPickup": true])
    let response = SortedProjectRewardsResponse(data)
    let transferred = await Task.detached { response }.value
    XCTAssertEqual(transferred.rewards.count, 1)
    XCTAssertEqual(transferred.rewards.first?.title, "Germany reward (not featured)")
    XCTAssertEqual(transferred.rewards.first?.shippingRulesExpanded?.count, 1)
    XCTAssertEqual(transferred.noReward?.isNoReward, true)
  }

  func testAbsentProjectDoesNotProduceSyntheticNoReward() {
    let response = SortedProjectRewardsResponse(.init(project: nil))
    XCTAssertTrue(response.rewards.isEmpty)
    XCTAssertNil(response.noReward)
  }
}
