import GraphAPI
@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
  func testGraphsRetainTheirInjectedFeaturesWithoutSharingState() {
    let firstProvider = NoRequestSearchProvider()
    let secondProvider = NoRequestSearchProvider()
    let firstFeature = SearchFeature(provider: firstProvider)
    let secondFeature = SearchFeature(provider: secondProvider)
    let firstDetails =
      ProjectDetailsFeature(makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let secondDetails =
      ProjectDetailsFeature(makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let first = AppModel(
      searchFeature: firstFeature,
      discoveryFeature: DiscoveryFeature(provider: NoRequestDiscoveryProvider()),
      projectDetailsFeature: firstDetails
    )
    let second = AppModel(
      searchFeature: secondFeature,
      discoveryFeature: DiscoveryFeature(provider: NoRequestDiscoveryProvider()),
      projectDetailsFeature: secondDetails
    )

    XCTAssertTrue(first.searchFeature === firstFeature)
    XCTAssertTrue(second.searchFeature === secondFeature)
    XCTAssertFalse(first.searchFeature === second.searchFeature)
    XCTAssertFalse(first.discoveryFeature === second.discoveryFeature)
    XCTAssertTrue(first.projectDetailsFeature === firstDetails)
    XCTAssertTrue(second.projectDetailsFeature === secondDetails)
    XCTAssertFalse(first.projectDetailsFeature === second.projectDetailsFeature)
    XCTAssertTrue(first.discoveryFeature.snapshot(for: .magic).projects.isEmpty)
    XCTAssertEqual(firstProvider.requestCount, 0)
    XCTAssertEqual(secondProvider.requestCount, 0)
    XCTAssertNil(first.searchFeature.parameters)
    XCTAssertNil(second.searchFeature.parameters)
  }
}

@MainActor
private final class NoRequestSearchProvider: SearchProjectsProvider {
  private(set) var requestCount = 0

  func fetchPage(
    parameters _: DiscoveryParams, cursor _: String?
  ) async throws -> GraphAPI.SearchQuery.Data {
    self.requestCount += 1
    throw CancellationError()
  }
}

@MainActor
private struct NoRequestDiscoveryProvider: DiscoveryProvider {
  func page(parameters _: DiscoveryParams, cursor _: String?) async throws -> DiscoveryEnvelope {
    XCTFail("Composition must not perform requests")
    throw CancellationError()
  }

  func activitySample() async throws -> ActivityEnvelope? {
    XCTFail("Composition must not perform requests")
    throw CancellationError()
  }
}
