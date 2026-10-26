import Combine
import Foundation
import GraphAPI
import ImageIO
@testable import KsApi
import ReactiveSwift
import XCTest

final class DemoCatalogTests: XCTestCase {
  func testDatesAreRelativeToAnInjectedLaunchDate() throws {
    let date = Foundation.Date(timeIntervalSince1970: 1_792_987_200)
    let catalogue = DemoCatalog(referenceDate: date)
    let later = DemoCatalog(referenceDate: date.addingTimeInterval(86_400))
    for (project, nextDayProject) in zip(catalogue.projects, later.projects) {
      let deadline = try XCTUnwrap(project.dates.deadline)
      let daysRemaining = (deadline - date.timeIntervalSince1970) / 86_400
      if project.state == .successful {
        XCTAssertEqual(daysRemaining, -3)
        XCTAssertGreaterThanOrEqual(project.stats.percentFunded, 100)
      } else {
        XCTAssertTrue((2...25).contains(daysRemaining))
      }
      XCTAssertLessThan(try XCTUnwrap(project.dates.launchedAt), date.timeIntervalSince1970)
      XCTAssertEqual(try XCTUnwrap(nextDayProject.dates.deadline) - deadline, 86_400)
    }
    XCTAssertEqual(catalogue.projects.map(\.dates.deadline), DemoCatalog(referenceDate: date).projects.map(\.dates.deadline))
  }

  func testEveryDemoPhotoAndAvatarHasALocalImageRoute() throws {
    for project in DemoCatalog().projects {
      let images = [project.photo.full, project.photo.med, project.photo.small,
        project.photo.size1024x768, project.creator.avatar.large,
        project.creator.avatar.medium, project.creator.avatar.small].compactMap { $0 }
      for image in images {
        let url = try XCTUnwrap(URL(string: image))
        XCTAssertTrue(DemoImageURLProtocol.canInit(with: URLRequest(url: url)))
      }
    }
    let production = try XCTUnwrap(URL(string: "https://www.kickstarter.com/photo.png"))
    XCTAssertFalse(DemoImageURLProtocol.canInit(with: URLRequest(url: production)))
  }

  func testLocalImageTransportDeliversDecodableDistinctPNGs() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DemoImageURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var illustrations = Set<Data>()
    for index in 0..<8 {
      for kind in ["project", "avatar"] {
        let url = try XCTUnwrap(URL(string: "https://images.demo.invalid/\(kind)/\(index).png"))
        let (data, response) = try await session.data(from: url)
        XCTAssertEqual(response.mimeType, "image/png")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, kind == "project" ? 640 : 128)
        XCTAssertEqual(image.height, kind == "project" ? 360 : 128)
        illustrations.insert(data)
      }
    }
    XCTAssertEqual(illustrations.count, 16)
    let missing = try XCTUnwrap(URL(string: "https://images.demo.invalid/project/99.png"))
    do {
      _ = try await session.data(from: missing)
      XCTFail("An unknown illustration must fail rather than access the network")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .fileDoesNotExist)
    }
  }

  func testCatalogueIsDeterministicAndClearlyFictional() {
    let first = DemoCatalog().projects
    let second = DemoCatalog().projects
    XCTAssertEqual(first.count, 24)
    XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    XCTAssertEqual(first.map(\.name), second.map(\.name))
    XCTAssertTrue(first.allSatisfy { $0.name.hasPrefix("[Demo]") })
  }

  func testSearchFindsMatchingNamesAndReturnsEmptyResultsHonestly() throws {
    let catalogue = DemoCatalog()
    let matches = try XCTUnwrap(catalogue.search(query(term: "FOREST")).projects)
    XCTAssertEqual(matches.totalCount, 3)
    XCTAssertTrue(try XCTUnwrap(matches.nodes).compactMap { $0 }.allSatisfy { $0.name.contains("Forest") })
    XCTAssertEqual(try catalogue.search(query(term: "no-such-project")).projects?.totalCount, 0)
  }

  func testPaginationHasNoDuplicatesAndTerminates() throws {
    let catalogue = DemoCatalog()
    let request = query()
    var ids: [Int] = []
    for _ in 0..<4 {
      let page = try XCTUnwrap(catalogue.search(request).projects)
      ids += try XCTUnwrap(page.nodes).compactMap { $0?.pid }
      request.cursor = .someOrNil(page.pageInfo.endCursor)
      if ids.count < 24 { XCTAssertTrue(page.pageInfo.hasNextPage) }
      else { XCTAssertFalse(page.pageInfo.hasNextPage); XCTAssertNil(page.pageInfo.endCursor) }
    }
    XCTAssertEqual(ids.count, 24)
    XCTAssertEqual(Set(ids).count, 24)
  }

  func testInvalidCursorAndSimulatedFailureDoNotPreventLaterSuccess() throws {
    let catalogue = DemoCatalog()
    let request = query()
    request.cursor = .some("-1")
    XCTAssertThrowsError(try catalogue.search(request))
    request.cursor = .some("9223372036854775807")
    XCTAssertThrowsError(try catalogue.search(request))
    XCTAssertThrowsError(try catalogue.search(query(term: "demo:error")))
    XCTAssertEqual(try catalogue.search(query()).projects?.totalCount, 24)
  }

  func testCategoryStateFundingAndSortAreApplied() throws {
    let catalogue = DemoCatalog()
    let request = query()
    request.categoryId = .some("12")
    request.state = .some(.case(.live))
    request.sort = .some(.case(.mostFunded))
    request.raised = .some(.case(.bucket2))
    let nodes = try XCTUnwrap(catalogue.search(request).projects?.nodes).compactMap { $0 }
    XCTAssertFalse(nodes.isEmpty)
    XCTAssertTrue(nodes.allSatisfy { $0.category?.name == "Games" && $0.projectState.value == .live })
    XCTAssertTrue(nodes.allSatisfy { $0.percentFunded >= 100 })
    let pledged = nodes.compactMap { $0.pledged.amount.flatMap(Int.init) }
    XCTAssertEqual(pledged, pledged.sorted(by: >))
  }

  func testDiscoveryAndGraphQLResolveToSameProjectDetails() throws {
    let catalogue = DemoCatalog()
    let firstPage = try catalogue.discovery(.defaults)
    let secondPage = try catalogue.discovery(paginationURL: firstPage.urls.api.moreProjects)
    XCTAssertTrue(Set(firstPage.projects.map(\.id)).isDisjoint(with: secondPage.projects.map(\.id)))
    let searchProject = try XCTUnwrap(catalogue.search(query()).projects?.nodes?.first ?? nil)
    let detail = try catalogue.project(.id(searchProject.pid))
    XCTAssertEqual(detail.name, searchProject.name)
    XCTAssertEqual(try catalogue.project(.slug(detail.slug)).id, detail.id)
    XCTAssertFalse(try catalogue.extraProperties(.id(detail.id)).extendedProjectProperties.story.htmlViewElements.isEmpty)
    XCTAssertThrowsError(try catalogue.project(.id(-1)))
  }

  func testPublicDemoDoesNotChangeDefaultTestMocks() throws {
    let request = query()
    let original: SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> = MockService().fetch(query: request)
    XCTAssertThrowsError(try XCTUnwrap(original.first()).get())
    let demo: SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> = MockService.publicDemo().fetch(query: request)
    XCTAssertEqual(try XCTUnwrap(demo.first()).get().projects?.totalCount, 24)
  }

  func testAsyncAndReactiveDemoResponsesAgree() async throws {
    let service = MockService.publicDemo()
    let asynchronous: GraphAPI.SearchQuery.Data? = try await service.fetch(query: query(term: "Ocean"))
    let reactive: SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> = service.fetch(query: query(term: "Ocean"))
    XCTAssertEqual(asynchronous?.projects?.totalCount, try XCTUnwrap(reactive.first()).get().projects?.totalCount)
  }

  func testLocationAndStateSurviveDiscoveryPagination() throws {
    let catalogue = DemoCatalog()
    var params = DiscoveryParams.defaults
    params.location = .brooklyn
    let first = try catalogue.discovery(params)
    let second = try catalogue.discovery(paginationURL: first.urls.api.moreProjects)
    XCTAssertEqual(first.projects.count + second.projects.count, 8)
    XCTAssertTrue((first.projects + second.projects).allSatisfy { $0.location?.id == Location.brooklyn.id })
    XCTAssertTrue(try catalogue.discovery(paginationURL: second.urls.api.moreProjects).projects.isEmpty)
    params.state = .successful
    XCTAssertTrue(try catalogue.discovery(params).projects.allSatisfy { $0.state == .successful })
  }

  func testGraphQLDatesUseEpochScalarAndFragmentsAreReadable() throws {
    let node = try XCTUnwrap(DemoCatalog().search(query()).projects?.nodes?.first ?? nil)
    XCTAssertNotNil(Double(node.stateChangedAt))
    XCTAssertNotNil(node.deadlineAt.flatMap(Double.init))
    XCTAssertEqual(node.fragments.projectCardFragment.name, node.name)
    XCTAssertEqual(node.fragments.backerDashboardProjectCellFragment.projectId, node.projectId)
  }

  func testCombineDiscoveryCompletesAndUsesSameCatalogue() {
    var projectIDs: [Int] = []
    var completed = false
    let subscription = MockService.publicDemo().fetchDiscovery_combine(params: .defaults)
      .sink(receiveCompletion: { completion in
        if case .finished = completion { completed = true }
        else { XCTFail("Demo discovery failed") }
      }, receiveValue: { projectIDs = $0.projects.map(\.id) })
    XCTAssertEqual(projectIDs, Array(DemoCatalog().projects.prefix(6)).map(\.id))
    XCTAssertTrue(completed)
    withExtendedLifetime(subscription) {}
  }

  func testDemoLoginDoesNotPretendToAuthenticate() throws {
    let response = MockService.publicDemo().login(email: "demo@example.invalid", password: "demo", code: nil)
    XCTAssertThrowsError(try XCTUnwrap(response.first()).get())
  }

  private func query(term: String? = nil) -> GraphAPI.SearchQuery {
    .init(term: .someOrNil(term), sort: .none, categoryId: .none, state: .none,
      raised: .none, locationId: .none, pledged: .none, goal: .none,
      showRecommended: .none, showSavedProjects: .none, showProjectsWeLove: .none,
      showFollowing: .none, first: .none, cursor: .none)
  }
}
