import GraphAPI
import KsApi
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
    let first = AppModel(searchFeature: firstFeature)
    let second = AppModel(searchFeature: secondFeature)

    XCTAssertTrue(first.searchFeature === firstFeature)
    XCTAssertTrue(second.searchFeature === secondFeature)
    XCTAssertFalse(first.searchFeature === second.searchFeature)
    XCTAssertEqual(firstProvider.requestCount, 0)
    XCTAssertEqual(secondProvider.requestCount, 0)
    XCTAssertNil(first.searchFeature.parameters)
    XCTAssertNil(second.searchFeature.parameters)
  }
}

@MainActor
private final class NoRequestSearchProvider: SearchProjectsProvider {
  private(set) var requestCount = 0

  func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> {
    self.requestCount += 1
    return .empty
  }
}
