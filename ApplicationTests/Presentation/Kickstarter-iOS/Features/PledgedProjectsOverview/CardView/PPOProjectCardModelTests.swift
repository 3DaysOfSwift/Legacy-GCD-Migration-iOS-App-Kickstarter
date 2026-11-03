@testable import Kickstarter_iOS

import ApolloTestSupport
import Combine
import GraphAPI
import GraphAPITestMocks

@testable import KsApi
import XCTest

@MainActor
final class PPOProjectCardModelTests: XCTestCase {
  func testParsingNoAddress() throws {
    let model = try XCTUnwrap(self.mockModel(address: nil))
    XCTAssertNil(model.address.rawAddress)
  }

  func testParsingBasicAddress_skipsEmptyLines() throws {
    let address = Mock<GraphAPITestMocks.Address>(
      addressLine1: "123 First Street",
      addressLine2: "",
      city: "Los Angeles",
      countryCode: .case(.us),
      id: "0",
      phoneNumber: "",
      postalCode: "90025-1234",
      recipientName: "Firsty Lasty",
      region: "CA"
    )

    let model = try XCTUnwrap(self.mockModel(address: address))

    let lines = (try XCTUnwrap(model.address.rawAddress)).split(
      separator: "\n",
      omittingEmptySubsequences: false
    )
    XCTAssertEqual(lines, [
      "Firsty Lasty",
      "123 First Street",
      "Los Angeles, CA 90025-1234",
      "US"
    ])
  }

  func testParsingTwoLineAddress() throws {
    let address = Mock<GraphAPITestMocks.Address>(
      addressLine1: "123 First Street",
      addressLine2: "Apt #5678",
      city: "Los Angeles",
      countryCode: .case(.us),
      id: "0",
      postalCode: "90025-1234",
      recipientName: "Firsty Lasty",
      region: "CA"
    )

    let model = try XCTUnwrap(self.mockModel(address: address))

    let lines = (try XCTUnwrap(model.address.rawAddress)).split(
      separator: "\n",
      omittingEmptySubsequences: false
    )
    XCTAssertEqual(lines, [
      "Firsty Lasty",
      "123 First Street",
      "Apt #5678",
      "Los Angeles, CA 90025-1234",
      "US"
    ])
  }

  func testParsingTwoLineAddressPhone() throws {
    let address = Mock<GraphAPITestMocks.Address>(
      addressLine1: "123 First Street",
      addressLine2: "Apt #5678",
      city: "Los Angeles",
      countryCode: .case(.us),
      id: "0",
      phoneNumber: "(555) 555-5425",
      postalCode: "90025-1234",
      recipientName: "Firsty Lasty",
      region: "CA"
    )

    let model = try XCTUnwrap(self.mockModel(address: address))

    let lines = (try XCTUnwrap(model.address.rawAddress)).split(
      separator: "\n",
      omittingEmptySubsequences: false
    )
    XCTAssertEqual(lines, [
      "Firsty Lasty",
      "123 First Street",
      "Apt #5678",
      "Los Angeles, CA 90025-1234",
      "US",
      "(555) 555-5425"
    ])
  }

  func testResponsePreservesImageAnalyticsAndNavigation() throws {
    let edge = GraphAPI.FetchPledgedProjectsQuery.mockEdge(addressMock: nil)
    let node = GraphAPI.FetchPledgedProjectsQuery.Data.PledgeProjectsOverview.Pledges.Edge.Node
      .from(try XCTUnwrap(edge.node))
    let fragment = node.fragments.pPOCardFragment
    let project = try XCTUnwrap(fragment.backing?.fragments.pPOBackingFragment.project)
    let response = PledgedProjectsResponse.Card(fragment)
    let card = try XCTUnwrap(PPOProjectCardModel(card: response))
    XCTAssertEqual(card.image.absoluteString, project.fragments.pPOProjectFragment.image?.url)
    XCTAssertEqual(card.projectAnalytics.id, project.fragments.projectAnalyticsFragment.id)
    XCTAssertEqual(card.projectAnalytics.name, project.fragments.projectAnalyticsFragment.name)
    XCTAssertEqual(card.projectAnalytics.statsPledged, project.fragments.projectAnalyticsFragment.statsPledged)
    XCTAssertEqual(card.projectAnalytics.tags, project.fragments.projectAnalyticsFragment.tags)
    let expected = try XCTUnwrap(ProjectCardProperties(project.fragments.projectCardFragment))
    let initial = try XCTUnwrap(card.projectPageParam?.initialProject)
    XCTAssertEqual(initial.projectAnalyticsProperties.name, expected.projectAnalyticsProperties.name)
    XCTAssertEqual(initial.projectPamphletMainCellProperties.photo, expected.projectPamphletMainCellProperties.photo)
    XCTAssertEqual(initial.projectPamphletMainCellProperties.blurb, expected.projectPamphletMainCellProperties.blurb)
  }

  func testResponseCrossesTaskBoundaryWithoutTransportObjects() async throws {
    let response = PledgedProjectsResponse(try GraphAPI.FetchPledgedProjectsQuery.fakeData(
      cursors: 1...2, hasNextPage: false))
    let transferred = await _Concurrency.Task.detached { response }.value
    XCTAssertEqual(transferred.cards.count, response.cards.count)
    XCTAssertEqual(transferred.cards.first?.imageURL, response.cards.first?.imageURL)
    XCTAssertEqual(transferred.cards.first?.analytics?.id, response.cards.first?.analytics?.id)
    XCTAssertEqual(transferred.cursor, response.cursor)
    XCTAssertEqual(transferred.total, response.total)
  }

  private func mockModel(address: Mock<GraphAPITestMocks.Address>?) -> PPOProjectCardModel? {
    let mockEdge = GraphAPI.FetchPledgedProjectsQuery.mockEdge(addressMock: address)
    let node = GraphAPI.FetchPledgedProjectsQuery.Data.PledgeProjectsOverview.Pledges.Edge.Node
      .from(mockEdge.node!)
    return PPOProjectCardModel(node: node)
  }
}
