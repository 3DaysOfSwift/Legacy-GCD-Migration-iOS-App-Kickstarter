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

  func testFilterSelectionBuildsQueryAndChangingTextRetainsSelection() {
    let searchFeature = SearchFeature(provider: ControlledSearchProvider())
    let (query, input) = Signal<String, Never>.pipe()
    var parameters: DiscoveryParams?
    let observation = searchFeature.queryParameters(for: query).observeValues { parameters = $0 }
    defer { observation?.dispose() }
    searchFeature.filterSelection.publishInitialSelection()
    input.send(value: "art")
    searchFeature.selectFilter(.sort(.newest))
    searchFeature.selectFilter(.category(.rootCategory(.art)))
    searchFeature.selectFilter(.projectsWeLove(true))
    input.send(value: "books")
    searchFeature.updateQuery("books")

    XCTAssertEqual(parameters?.query, "books")
    XCTAssertEqual(parameters?.sort, .newest)
    XCTAssertEqual(parameters?.category?.id, Category.art.id)
    XCTAssertEqual(parameters?.staffPicks, true)
  }

  func testClearingQueryResetsFiltersAndSortButResetAllKeepsSort() {
    let searchFeature = SearchFeature(provider: ControlledSearchProvider())
    let (query, input) = Signal<String, Never>.pipe()
    var parameters: DiscoveryParams?
    let observation = searchFeature.queryParameters(for: query).observeValues { parameters = $0 }
    defer { observation?.dispose() }
    searchFeature.filterSelection.publishInitialSelection()
    input.send(value: "art")
    searchFeature.selectFilter(.sort(.newest))
    searchFeature.selectFilter(.category(.rootCategory(.art)))
    searchFeature.selectFilter(.projectsWeLove(true))
    searchFeature.resetFilters(.allFilters)
    XCTAssertEqual(parameters?.sort, .newest)
    XCTAssertNil(parameters?.category)
    XCTAssertNil(parameters?.staffPicks) // Unselected means no API filter, not "exclude".

    input.send(value: "")
    searchFeature.updateQuery("")
    XCTAssertEqual(parameters?.sort, .magic)
    XCTAssertEqual(parameters?.query, "")
  }

  func testFeatureTogglesFilterWithoutOwningModalPresentation() {
    let searchFeature = SearchFeature(provider: ControlledSearchProvider())
    let (query, input) = Signal<String, Never>.pipe()
    var parameters: DiscoveryParams?
    let observation = searchFeature.queryParameters(for: query).observeValues { parameters = $0 }
    defer { observation?.dispose() }
    searchFeature.filterSelection.publishInitialSelection()
    input.send(value: "art")
    searchFeature.toggleFilter(.projectsWeLove)
    XCTAssertEqual(parameters?.staffPicks, true)
    searchFeature.toggleFilter(.projectsWeLove)
    XCTAssertNil(parameters?.staffPicks)
  }

  func testNativeQueryDefaultsNeedNoInitialSignalOrSubscriber() {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider)
    let parameters = feature.queryParameters(for: "  art  ")

    XCTAssertEqual(parameters.query, "  art  ", "Query whitespace remains unchanged")
    XCTAssertEqual(parameters.sort, .magic)
    XCTAssertEqual(parameters.state, .all)
    XCTAssertEqual(parameters.perPage, 15)
    XCTAssertNil(parameters.category)
    XCTAssertNil(parameters.location)
    XCTAssertNil(parameters.percentRaised)
    XCTAssertNil(parameters.amountRaised)
    XCTAssertNil(parameters.goal)
    XCTAssertNil(parameters.recommended)
    XCTAssertNil(parameters.starred)
    XCTAssertNil(parameters.staffPicks)
    XCTAssertNil(parameters.social)
    XCTAssertTrue(provider.requests.isEmpty, "Reading selection must not start transport")
    XCTAssertNil(feature.parameters, "Building parameters must not pretend a request ran")
  }

  func testNativeQueryContainsEverySelectedFieldWithoutSubscribers() {
    let feature = SearchFeature(provider: ControlledSearchProvider())
    let location = Location(
      country: "US", displayableName: "Somerville, MA", id: 1,
      localizedName: "Somerville, MA", name: "Somerville, MA"
    )
    feature.selectFilter(.sort(.newest))
    feature.selectFilter(.category(.rootCategory(.art)))
    feature.selectFilter(.projectState(.live))
    feature.selectFilter(.percentRaised(.bucket_2))
    feature.selectFilter(.amountRaised(.bucket_3))
    feature.selectFilter(.goal(.bucket_4))
    feature.selectFilter(.location(location))
    feature.toggleFilter(.recommended)
    feature.toggleFilter(.savedProjects)
    feature.toggleFilter(.projectsWeLove)
    feature.toggleFilter(.following)

    let parameters = feature.queryParameters(for: "ceramics")
    XCTAssertEqual(parameters.sort, .newest)
    XCTAssertEqual(parameters.category?.id, Category.art.id)
    XCTAssertEqual(parameters.state, .live)
    XCTAssertEqual(parameters.percentRaised, .bucket_2)
    XCTAssertEqual(parameters.amountRaised, .bucket_3)
    XCTAssertEqual(parameters.goal, .bucket_4)
    XCTAssertEqual(parameters.location, location)
    XCTAssertEqual(parameters.recommended, true)
    XCTAssertEqual(parameters.starred, true)
    XCTAssertEqual(parameters.staffPicks, true)
    XCTAssertEqual(parameters.social, true)

    feature.updateQuery("pottery")
    XCTAssertEqual(feature.queryParameters(for: "ceramics"), parameters)
    feature.toggleFilter(.recommended)
    feature.toggleFilter(.savedProjects)
    feature.toggleFilter(.projectsWeLove)
    feature.toggleFilter(.following)
    let untoggled = feature.queryParameters(for: "pottery")
    XCTAssertNil(untoggled.recommended)
    XCTAssertNil(untoggled.starred)
    XCTAssertNil(untoggled.staffPicks)
    XCTAssertNil(untoggled.social)
  }

  func testNativeResetAllPreservesSortAndClearResetsSortWithoutSubscribers() {
    let feature = SearchFeature(provider: ControlledSearchProvider())
    feature.selectFilter(.sort(.newest))
    feature.selectFilter(.category(.rootCategory(.art)))
    feature.selectFilter(.projectState(.live))
    feature.selectFilter(.percentRaised(.bucket_2))
    feature.selectFilter(.amountRaised(.bucket_3))
    feature.selectFilter(.goal(.bucket_4))
    feature.toggleFilter(.following)
    feature.resetFilters(.allFilters)

    let defaults = SearchFeature(provider: ControlledSearchProvider()).queryParameters(for: "")
    var expected = defaults
    expected.sort = .newest
    XCTAssertEqual(feature.queryParameters(for: ""), expected)
    feature.updateQuery("")
    XCTAssertEqual(feature.queryParameters(for: ""), defaults)
  }

  func testScopedResetKeepsUnrelatedCategoryAndSort() {
    let feature = SearchFeature(provider: ControlledSearchProvider())
    feature.selectFilter(.sort(.newest))
    feature.selectFilter(.category(.rootCategory(.art)))
    feature.selectFilter(.goal(.bucket_4))
    feature.selectFilter(.amountRaised(.bucket_3))
    feature.selectFilter(.percentRaised(.bucket_2))
    feature.resetFilters(.goal)
    let parameters = feature.queryParameters(for: "art")
    XCTAssertNil(parameters.goal)
    XCTAssertEqual(parameters.amountRaised, .bucket_3)
    XCTAssertEqual(parameters.percentRaised, .bucket_2)
    XCTAssertEqual(parameters.category?.id, Category.art.id)
    XCTAssertEqual(parameters.sort, .newest)
  }

  func testLegacyQueryAdapterWaitsForInitialSelectionAndMatchesNativeQuery() {
    let feature = SearchFeature(provider: ControlledSearchProvider())
    let (query, input) = Signal<String, Never>.pipe()
    var received: [DiscoveryParams] = []
    let observation = feature.queryParameters(for: query).observeValues { received.append($0) }
    defer { observation?.dispose() }
    input.send(value: "art")
    feature.selectFilter(.sort(.newest))
    feature.selectFilter(.category(.rootCategory(.art)))
    XCTAssertTrue(received.isEmpty, "Keep the legacy initial-emission barrier")
    feature.filterSelection.publishInitialSelection()
    XCTAssertEqual(received.count, 1)
    XCTAssertEqual(received.last, feature.queryParameters(for: "art"))
    feature.selectFilter(.goal(.bucket_4))
    XCTAssertEqual(received.last, feature.queryParameters(for: "art"))
    input.send(value: "books")
    XCTAssertEqual(received.last, feature.queryParameters(for: "books"))
  }

  func testLegacyResetKeepsPerFieldOrderAndDuplicateEmissions() {
    let feature = SearchFeature(provider: ControlledSearchProvider())
    let (query, input) = Signal<String, Never>.pipe()
    var received: [DiscoveryParams] = []
    let observation = feature.queryParameters(for: query).observeValues { received.append($0) }
    defer { observation?.dispose() }
    feature.filterSelection.publishInitialSelection()
    input.send(value: "art")
    feature.selectFilter(.sort(.newest))
    feature.selectFilter(.category(.rootCategory(.art)))
    feature.selectFilter(.projectState(.live))
    feature.selectFilter(.percentRaised(.bucket_2))
    feature.selectFilter(.amountRaised(.bucket_3))
    feature.selectFilter(.goal(.bucket_4))
    feature.selectFilter(.following(true))
    feature.selectFilter(.recommended(true))
    feature.selectFilter(.projectsWeLove(true))
    feature.selectFilter(.savedProjects(true))
    let beforeReset = feature.queryParameters(for: "art")
    received.removeAll()
    feature.resetFilters(.allFilters)

    var expected = beforeReset
    var expectedEmissions: [DiscoveryParams] = []
    expected.category = nil
    expectedEmissions.append(expected)
    expected.state = .all
    expectedEmissions.append(expected)
    expected.percentRaised = nil
    expectedEmissions.append(expected)
    expected.location = nil
    expectedEmissions.append(expected)
    expected.amountRaised = nil
    expectedEmissions.append(expected)
    expected.goal = nil
    expectedEmissions.append(expected)
    expected.social = nil
    expectedEmissions.append(expected)
    expected.recommended = nil
    expectedEmissions.append(expected)
    expected.staffPicks = nil
    expectedEmissions.append(expected)
    expected.starred = nil
    expectedEmissions.append(expected)
    XCTAssertEqual(received, expectedEmissions, "Ten ordered emissions, including unchanged location")

    received.removeAll()
    feature.updateQuery("")
    XCTAssertEqual(received.count, 11, "Clear resets ten filters, then sort")
    XCTAssertEqual(received.last?.sort, .magic)
    received.removeAll()
    feature.selectFilter(.sort(.magic))
    feature.selectFilter(.sort(.magic))
    XCTAssertEqual(received.count, 2, "Do not silently deduplicate UI/analytics events")
  }

  func testSuccessfulSearchPublishesDataCountAndLoading() async throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); searchFeature.cancelSearch() }
    var currentTask: Task<Void, Never>?
    let data = try self.fixture("SearchQuery_FiveResults")

    currentTask = searchFeature.requestSearch(parameters: self.parameters("ceramics"))
    await provider.waitForRequestCount(1)
    XCTAssertTrue(searchFeature.isLoading)
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertEqual(provider.requests.first?.parameters.query, "ceramics")

    try provider.complete(0, with: data)
    await currentTask?.value

    XCTAssertEqual(searchFeature.projects, data.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertEqual(searchFeature.totalCount, 200)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertNil(searchFeature.searchError)
  }

  func testReplacementClearsResultsAndSuppressesObsoleteCompletion() async throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); searchFeature.cancelSearch() }
    var currentTask: Task<Void, Never>?
    let oldData = try self.fixture("SearchQuery_FiveResults")
    let newData = try self.fixture("SearchQuery_AnotherFiveResults")

    currentTask = searchFeature.requestSearch(parameters: self.parameters("old"))
    let oldTask = currentTask
    await provider.waitForRequestCount(1)
    currentTask = searchFeature.requestSearch(parameters: self.parameters("new"))
    await provider.waitForRequestCount(2)

    XCTAssertEqual(provider.requests.count, 2)

    try provider.complete(1, with: newData)
    await currentTask?.value
    let latestProjects = searchFeature.projects

    // A badly behaved transport can finish after its task is cancelled.
    try provider.complete(0, with: oldData)
    await oldTask?.value

    XCTAssertEqual(searchFeature.parameters?.query, "new")
    XCTAssertEqual(searchFeature.projects, latestProjects)
    XCTAssertEqual(latestProjects, newData.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertFalse(searchFeature.isLoading)

    currentTask = searchFeature.requestSearch(parameters: self.parameters("replacement"))
    await provider.waitForRequestCount(3)
    XCTAssertTrue(searchFeature.projects.isEmpty)
    XCTAssertTrue(searchFeature.isLoading)
    searchFeature.cancelSearch()
    provider.releaseAll()
    await currentTask?.value
  }

  func testNextPageAppendsAndEmptyPageEndsPagination() async throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); searchFeature.cancelSearch() }
    var currentTask: Task<Void, Never>?
    let first = try self.fixture("SearchQuery_FiveResults")
    let second = try self.fixture("SearchQuery_AnotherFiveResults")
    let empty = try self.fixture("SearchQuery_EmptyResults")

    currentTask = searchFeature.requestSearch(parameters: self.parameters("art"))
    await provider.waitForRequestCount(1)
    try provider.complete(0, with: first)
    await currentTask?.value
    currentTask = searchFeature.requestNextPage()
    await provider.waitForRequestCount(2)

    XCTAssertEqual(provider.requests.count, 2)
    XCTAssertEqual(provider.requests.last?.parameters.query, "art")
    XCTAssertEqual(provider.requests.last?.cursor, first.projects?.pageInfo.endCursor)

    try provider.complete(1, with: second)
    await currentTask?.value
    let expected = (first.projects?.nodes?.compactMap { $0 } ?? [])
      + (second.projects?.nodes?.compactMap { $0 } ?? [])
    XCTAssertEqual(searchFeature.projects, expected)

    currentTask = searchFeature.requestNextPage()
    await provider.waitForRequestCount(3)
    try provider.complete(2, with: empty)
    await currentTask?.value
    currentTask = searchFeature.requestNextPage()

    XCTAssertEqual(provider.requests.count, 3)
    XCTAssertEqual(searchFeature.projects, expected)
    XCTAssertFalse(searchFeature.isLoading)
  }

  func testFailureRetainsErrorAndChangedQueryRecovers() async throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); searchFeature.cancelSearch() }
    var currentTask: Task<Void, Never>?
    currentTask = searchFeature.requestSearch(parameters: self.parameters("failed"))
    await provider.waitForRequestCount(1)
    try provider.fail(0)
    await currentTask?.value
    XCTAssertNotNil(searchFeature.searchError)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertTrue(searchFeature.projects.isEmpty)

    currentTask = searchFeature.requestSearch(parameters: self.parameters("recovered"))
    await provider.waitForRequestCount(2)
    XCTAssertNil(searchFeature.searchError)
    try provider.complete(1, with: self.fixture("SearchQuery_FiveResults"))
    await currentTask?.value

    XCTAssertEqual(searchFeature.projects.count, 5)
    XCTAssertFalse(searchFeature.isLoading)
    XCTAssertNil(searchFeature.searchError)
  }

  func testFailedPagePreservesExistingProjectsAndCanRetry() async throws {
    let provider = ControlledSearchProvider()
    let searchFeature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); searchFeature.cancelSearch() }
    var currentTask: Task<Void, Never>?
    currentTask = searchFeature.requestSearch(parameters: self.parameters("art"))
    await provider.waitForRequestCount(1)
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    await currentTask?.value
    let firstPage = searchFeature.projects

    currentTask = searchFeature.requestNextPage()
    await provider.waitForRequestCount(2)
    try provider.fail(1)
    await currentTask?.value
    XCTAssertEqual(searchFeature.projects, firstPage)
    XCTAssertNotNil(searchFeature.searchError)
    XCTAssertFalse(searchFeature.isLoading)

    currentTask = searchFeature.requestNextPage()
    await provider.waitForRequestCount(3)
    try provider.complete(2, with: self.fixture("SearchQuery_AnotherFiveResults"))
    await currentTask?.value
    XCTAssertEqual(searchFeature.projects.count, 10)
    XCTAssertNil(searchFeature.searchError)
  }

  func testAwaitableSearchAndPageCommandsShareExecutionUntilPublication() async throws {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); feature.cancelSearch() }
    let parameters = self.parameters("shared")
    let firstEntered = expectation(description: "first waiter entered")
    let secondEntered = expectation(description: "second waiter entered")
    var completions = 0
    let first = Task {
      firstEntered.fulfill()
      await feature.search(parameters: parameters)
      completions += 1
    }
    defer { first.cancel() }
    await fulfillment(of: [firstEntered], timeout: 2)
    await provider.waitForRequestCount(1)
    let second = Task {
      secondEntered.fulfill()
      await feature.search(parameters: parameters)
      completions += 1
    }
    defer { second.cancel() }
    await fulfillment(of: [secondEntered], timeout: 2)
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertEqual(completions, 0, "Neither await may return while its shared request is unfinished")
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    await first.value
    await second.value
    XCTAssertEqual(completions, 2)
    XCTAssertEqual(feature.projects.count, 5)

    let page = Task { await feature.loadNextPage() }
    defer { page.cancel() }
    await provider.waitForRequestCount(2)
    let duplicateEntered = expectation(description: "duplicate page waiter")
    var duplicateFinished = false
    let duplicate = Task {
      duplicateEntered.fulfill()
      await feature.loadNextPage()
      duplicateFinished = true
    }
    defer { duplicate.cancel() }
    await fulfillment(of: [duplicateEntered], timeout: 2)
    XCTAssertEqual(provider.requests.count, 2)
    XCTAssertFalse(duplicateFinished)
    try provider.complete(1, with: self.fixture("SearchQuery_AnotherFiveResults"))
    await page.value
    await duplicate.value
    XCTAssertTrue(duplicateFinished)
    XCTAssertEqual(feature.projects.count, 10, "A shared page is appended exactly once")
    XCTAssertFalse(feature.isLoading)
  }

  func testCancelledWaiterDoesNotCancelSharedSearch() async throws {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); feature.cancelSearch() }
    let parameters = self.parameters("shared")
    let first = Task { await feature.search(parameters: parameters) }
    defer { first.cancel() }
    await provider.waitForRequestCount(1)
    let entered = expectation(description: "second waiter")
    let second = Task {
      entered.fulfill()
      await feature.search(parameters: parameters)
    }
    defer { second.cancel() }
    await fulfillment(of: [entered], timeout: 2)
    second.cancel()
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    await first.value
    await second.value
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertEqual(feature.projects.count, 5)
    XCTAssertNil(feature.searchError)
  }

  func testQueryReplacementDuringPageCannotAppendOrClearNewerOperation() async throws {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); feature.cancelSearch() }
    let initial = feature.requestSearch(parameters: self.parameters("old"))
    await provider.waitForRequestCount(1)
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    await initial.value
    let page = Task { await feature.loadNextPage() }
    defer { page.cancel() }
    await provider.waitForRequestCount(2)
    let replacement = feature.requestSearch(parameters: self.parameters("new"))
    await provider.waitForRequestCount(3)
    try provider.complete(1, with: self.fixture("SearchQuery_AnotherFiveResults"))
    await page.value
    XCTAssertTrue(feature.isLoading, "Old cleanup cannot clear the replacement's loading state")
    XCTAssertTrue(feature.projects.isEmpty)
    let repeatedPage = feature.requestNextPage()
    XCTAssertEqual(provider.requests.count, 3, "Do not use the old cursor during replacement")
    try provider.complete(2, with: self.fixture("SearchQuery_FiveResults"))
    await replacement.value
    await repeatedPage?.value
    XCTAssertEqual(feature.projects.count, 5)
    XCTAssertEqual(feature.parameters?.query, "new")
  }

  func testOwnerCancellationIgnoresLateResultAndAllowsRetry() async throws {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); feature.cancelSearch() }
    let old = feature.requestSearch(parameters: self.parameters("cancel"))
    await provider.waitForRequestCount(1)
    feature.cancelSearch()
    XCTAssertFalse(feature.isLoading)
    try provider.complete(0, with: self.fixture("SearchQuery_FiveResults"))
    await old.value
    XCTAssertTrue(feature.projects.isEmpty)
    XCTAssertNil(feature.searchError)
    let retry = feature.requestSearch(parameters: self.parameters("cancel"))
    await provider.waitForRequestCount(2)
    try provider.complete(1, with: self.fixture("SearchQuery_FiveResults"))
    await retry.value
    XCTAssertEqual(feature.projects.count, 5)
  }

  func testAlreadyCancelledCallerDoesNotStartRequest() async {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider)
    let caller = Task { await feature.search(parameters: self.parameters("cancelled")) }
    caller.cancel()
    await caller.value
    XCTAssertTrue(provider.requests.isEmpty)
    XCTAssertNil(feature.parameters)
    XCTAssertFalse(feature.isLoading)
  }

  func testNoCursorAndNoInitialRequestAreAwaitableNoOps() async throws {
    let provider = ControlledSearchProvider()
    let feature = SearchFeature(provider: provider, sleep: { _ in })
    defer { provider.releaseAll(); feature.cancelSearch() }
    await feature.loadNextPage()
    XCTAssertTrue(provider.requests.isEmpty)
    let search = Task { await feature.search(parameters: self.parameters("empty")) }
    defer { search.cancel() }
    await provider.waitForRequestCount(1)
    try provider.complete(0, with: self.fixture("SearchQuery_EmptyResults"))
    await search.value
    await feature.loadNextPage()
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertTrue(feature.projects.isEmpty)
    XCTAssertFalse(feature.isLoading)
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
    var continuation: CheckedContinuation<GraphAPI.SearchQuery.Data, Error>?

    init(
      parameters: DiscoveryParams, cursor: String?,
      continuation: CheckedContinuation<GraphAPI.SearchQuery.Data, Error>
    ) {
      self.parameters = parameters
      self.cursor = cursor
      self.continuation = continuation
    }
  }

  private(set) var requests: [Request] = []
  private var arrivals: [(Int, XCTestExpectation)] = []

  func fetchPage(
    parameters: DiscoveryParams, cursor: String?
  ) async throws -> GraphAPI.SearchQuery.Data {
    // Intentionally ignore cancellation: the Feature must reject late results.
    return try await withCheckedThrowingContinuation { continuation in
      self.requests.append(Request(
        parameters: parameters, cursor: cursor, continuation: continuation
      ))
      let satisfied = self.arrivals.filter { self.requests.count >= $0.0 }
      self.arrivals.removeAll { self.requests.count >= $0.0 }
      satisfied.forEach { $0.1.fulfill() }
    }
  }

  func waitForRequestCount(_ count: Int) async {
    guard self.requests.count < count else { return }
    let arrival = XCTestExpectation(description: "request \(count) admitted")
    self.arrivals.append((count, arrival))
    let result = await XCTWaiter.fulfillment(of: [arrival], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func complete(_ index: Int, with data: GraphAPI.SearchQuery.Data) throws {
    let request = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index] : nil)
    let continuation = try XCTUnwrap(request.continuation)
    request.continuation = nil
    continuation.resume(returning: data)
  }

  func fail(_ index: Int) throws {
    let request = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index] : nil)
    let continuation = try XCTUnwrap(request.continuation)
    request.continuation = nil
    continuation.resume(throwing: ErrorEnvelope.couldNotParseJSON)
  }

  func releaseAll() {
    for request in self.requests {
      request.continuation?.resume(throwing: CancellationError())
      request.continuation = nil
    }
  }
}
