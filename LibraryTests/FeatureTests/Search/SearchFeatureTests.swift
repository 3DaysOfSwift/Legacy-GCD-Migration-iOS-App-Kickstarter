import Foundation
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class SearchFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConstructionDoesNotFetch() {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    XCTAssertTrue(provider.requests.isEmpty)
    XCTAssertTrue(searchFeature.projects.isEmpty)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertNil(searchFeature.searchError)
  }

  func testSuccessfulSearchPublishesDataCountAndLoading() throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    let data = try self.fixture("SearchQuery_FiveResults")

    searchFeature.search(parameters: self.parameters("ceramics"))
    XCTAssertTrue(searchFeature.isLoading)
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertEqual(provider.requests.first?.parameters.query, "ceramics")
    XCTAssertEqual(provider.requests.first?.debounce, false)

    try provider.complete(0, with: data)
    self.scheduler.run()

    XCTAssertEqual(searchFeature.projects, data.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertEqual(searchFeature.totalCount, 200)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertNil(searchFeature.searchError)
  }

  func testReplacementClearsResultsAndSuppressesObsoleteCompletion() throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    let oldData = try self.fixture("SearchQuery_FiveResults")
    let newData = try self.fixture("SearchQuery_AnotherFiveResults")

    searchFeature.search(parameters: self.parameters("old"))
    searchFeature.search(parameters: self.parameters("new"))

    XCTAssertEqual(provider.requests.count, 2)
    XCTAssertEqual(provider.requests.first?.isDisposed, true)
    XCTAssertEqual(provider.requests.last?.debounce, true)

    try provider.complete(1, with: newData)
    self.scheduler.run()
    let latestProjects = searchFeature.projects

    // A badly behaved transport can finish after its subscription is disposed.
    try provider.complete(0, with: oldData)
    self.scheduler.run()

    XCTAssertEqual(searchFeature.parameters?.query, "new")
    XCTAssertEqual(searchFeature.projects, latestProjects)
    XCTAssertEqual(latestProjects, newData.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertFalse(searchFeature.isLoading)

    searchFeature.search(parameters: self.parameters("replacement"))
    XCTAssertTrue(searchFeature.projects.isEmpty)
    XCTAssertTrue(searchFeature.isLoading)
  }

  func testNextPageAppendsAndEmptyPageEndsPagination() throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    let first = try self.fixture("SearchQuery_FiveResults")
    let second = try self.fixture("SearchQuery_AnotherFiveResults")
    let empty = try self.fixture("SearchQuery_EmptyResults")

    searchFeature.search(parameters: self.parameters("art"))
    try provider.complete(0, with: first)
    self.scheduler.run()
    searchFeature.loadNextPage()

    XCTAssertEqual(provider.requests.count, 2)
    XCTAssertEqual(provider.requests.last?.parameters.query, "art")
    XCTAssertEqual(provider.requests.last?.cursor, first.projects?.pageInfo.endCursor)
    XCTAssertEqual(provider.requests.last?.debounce, false)

    try provider.complete(1, with: second)
    self.scheduler.run()
    let expected = (first.projects?.nodes?.compactMap { $0 } ?? [])
      + (second.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertEqual(searchFeature.projects, expected)

    searchFeature.loadNextPage()
    try provider.complete(2, with: empty)
    self.scheduler.run()
    searchFeature.loadNextPage()

    XCTAssertEqual(provider.requests.count, 3)
    XCTAssertEqual(searchFeature.projects, expected)
    XCTAssertFalse(searchFeature.isLoading)
  }

  func testFailureRetainsErrorAndChangedQueryRecovers() throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    searchFeature.search(parameters: self.parameters("failed"))

    try provider.fail(0)
    self.scheduler.run()
    XCTAssertNotNil(searchFeature.searchError)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertTrue(searchFeature.projects.isEmpty)

    searchFeature.search(parameters: self.parameters("recovered"))
    XCTAssertNil(searchFeature.searchError)
    try provider.complete(1, with: self.fixture("SearchQuery_FiveResults"))
    self.scheduler.run()

    XCTAssertEqual(searchFeature.projects.count, 5)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertNil(searchFeature.searchError)
  }

  func testFailedPagePreservesExistingProjectsAndCanRetry() throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider)
    searchFeature.search(parameters: self.parameters("art"))
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    self.scheduler.run()
    let firstPage = searchFeature.projects

    searchFeature.loadNextPage()
    try provider.fail(1)
    self.scheduler.run()
    XCTAssertEqual(searchFeature.projects, firstPage)
    XCTAssertNotNil(searchFeature.searchError)
    XCTAssertFalse(searchFeature.isLoading)

    searchFeature.loadNextPage()
    try provider.complete(2, with: self.fixture("SearchQuery_AnotherFiveResults"))
    self.scheduler.run()
    XCTAssertEqual(searchFeature.projects.count, 10)
    XCTAssertNil(searchFeature.searchError)
  }

  private func parameters(_ query: String) -> DiscoveryParams {
    var parameters = DiscoveryParams.defaults
    parameters.query = query
    parameters.sort = .magic
    parameters.perPage = 15
    return parameters
  }

  private func fixture(_ name: String) throws -> GraphAPI.SearchQuery.Data {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
    return try testGraphObject(fromResource: url)
  }
}

@MainActor
private final class ControlledSearchProvider: SearchProjectsProvider {
  final class Request {
    let parameters: DiscoveryParams
    let cursor: String?
    let debounce: Bool
    let signal: Signal<GraphAPI.SearchQuery.Data, ErrorEnvelope>
    let observer: Signal<GraphAPI.SearchQuery.Data, ErrorEnvelope>.Observer
    var isDisposed = false

    init(parameters: DiscoveryParams, cursor: String?, debounce: Bool) {
      self.parameters = parameters
      self.cursor = cursor
      self.debounce = debounce
      (self.signal, self.observer) = Signal.pipe()
    }
  }

  private(set) var requests: [Request] = []

  func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> {
    let request = Request(parameters: parameters, cursor: cursor, debounce: debounce)
    self.requests.append(request)
    return request.signal.producer.on(disposed: { request.isDisposed = true })
  }

  func complete(_ index: Int, with data: GraphAPI.SearchQuery.Data) throws {
    let request = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index] : nil)
    request.observer.send(value: data)
    request.observer.sendCompleted()
  }

  func fail(_ index: Int) throws {
    let request = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index] : nil)
    request.observer.send(error: .couldNotParseJSON)
  }
}
