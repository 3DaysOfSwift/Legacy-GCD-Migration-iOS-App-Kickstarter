import GraphAPI
import Prelude
import XCTest

@testable import KsApi
@testable import Library

@MainActor
final class DeveloperExamplesFeatureTests: XCTestCase {
  private var provider: ControlledExamplesProvider!
  private var feature: DeveloperExamplesFeature!
  private let route = UUID()

  override func setUp() async throws {
    try await super.setUp()
    let provider = ControlledExamplesProvider()
    self.provider = provider
    self.feature = DeveloperExamplesFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }
      ),
      makeProvider: { provider })
  }
  override func tearDown() async throws {
    self.feature.reset()
    self.provider.pages.releaseAll()
    self.provider.lists.releaseAll()
    self.provider.lookups.releaseAll()
    try await super.tearDown()
  }
  private func page(_ ids: [Int], cursor: String = "next") -> DiscoveryEnvelope {
    DiscoveryEnvelope.template
      |> DiscoveryEnvelope.lens.projects .~ ids.map { Project.template |> Project.lens.id .~ $0 }
      |> DiscoveryEnvelope.lens.urls.api.moreProjects .~ cursor
  }
  private var item: DeveloperExamplesFeature.ProjectItem {
    .init(id: "one", name: "Example", richText: .init(items: []))
  }
  private func cancelled<T>(_ task: Task<T, Error>) async {
    if case .failure(is CancellationError) = await task.result {
    } else {
      XCTFail("Expected cancellation")
    }
  }

  func testInitialAndRefreshParametersAndStatusArePreserved() async throws {
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).statusText, "Waiting to load")
    let initial = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    XCTAssertEqual(self.provider.parameters[0], .defaults)
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).statusText, "Loading")
    try self.provider.pages.finish(0, .success(self.page([1, 2])))
    await initial.value
    XCTAssertEqual(
      self.feature.pageSnapshot(route: self.route).statusText, "Got 2 results; more are available")
    let refresh = Task { await self.feature.loadFirstPage(route: self.route, refreshing: true) }
    await self.provider.pages.waitFor(2)
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).projects.map(\.id), [1, 2])
    XCTAssertEqual(self.provider.parameters[1].staffPicks, true)
    XCTAssertEqual(self.provider.parameters[1].sort, .magic)
    try self.provider.pages.finish(1, .success(self.page([])))
    await refresh.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).statusText, "No results")
    XCTAssertFalse(self.feature.pageSnapshot(route: self.route).showProgressView)
  }

  func testEquivalentRefreshesShareAndNextPageAtEndReturns() async throws {
    let first = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    let admitted = expectation(description: "Second caller entered")
    let second = Task {
      admitted.fulfill()
      await self.feature.loadFirstPage(route: self.route)
    }
    await fulfillment(of: [admitted], timeout: 2)
    try self.provider.pages.finish(0, .success(self.page([])))
    await first.value
    await second.value
    await self.feature.loadNextPage(route: self.route)
    XCTAssertEqual(self.provider.pages.count, 1)
  }

  func testNextPageSharesAppendsDuplicatesAndEmptyPageEnds() async throws {
    let first = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(self.page([1])))
    await first.value
    let next = Task { await self.feature.loadNextPage(route: self.route) }
    await self.provider.pages.waitFor(2)
    let admitted = expectation(description: "Duplicate next caller entered")
    let duplicate = Task {
      admitted.fulfill()
      await self.feature.loadNextPage(route: self.route)
    }
    await fulfillment(of: [admitted], timeout: 2)
    XCTAssertEqual(self.provider.cursors[1], "next")
    try self.provider.pages.finish(1, .success(self.page([1, 2], cursor: "last")))
    await next.value
    await duplicate.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).projects.map(\.id), [1, 1, 2])
    let last = Task { await self.feature.loadNextPage(route: self.route) }
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .success(self.page([])))
    await last.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).statusText, "Loaded all results")
    await self.feature.loadNextPage(route: self.route)
    XCTAssertEqual(self.provider.pages.count, 3)
  }

  func testRefreshSupersedesNoncooperativeNextPage() async throws {
    let first = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(self.page([1])))
    await first.value
    let old = Task { await self.feature.loadNextPage(route: self.route) }
    await self.provider.pages.waitFor(2)
    let fresh = Task { await self.feature.loadFirstPage(route: self.route, refreshing: true) }
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .success(self.page([9])))
    await fresh.value
    try self.provider.pages.finish(1, .success(self.page([2])))
    await old.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).projects.map(\.id), [9])
  }

  func testPaginationFailureClearsRowsAndExplicitRefreshRetries() async throws {
    let first = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(self.page([1])))
    await first.value
    let failed = Task { await self.feature.loadNextPage(route: self.route) }
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(1, .failure(ErrorEnvelope.graphError("Offline")))
    await failed.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).statusText, "Error: Offline")
    XCTAssertTrue(self.feature.pageSnapshot(route: self.route).projects.isEmpty)
    let retry = Task { await self.feature.loadFirstPage(route: self.route, refreshing: true) }
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .success(self.page([4])))
    await retry.value
    XCTAssertEqual(self.feature.pageSnapshot(route: self.route).projects.map(\.id), [4])
  }

  func testReleaseRejectsLatePageAndIndependentRouteSurvives() async throws {
    let other = UUID()
    let old = Task { await self.feature.loadFirstPage(route: self.route) }
    await self.provider.pages.waitFor(1)
    let independent = Task { await self.feature.loadFirstPage(route: other) }
    await self.provider.pages.waitFor(2)
    self.feature.release(route: self.route)
    try self.provider.pages.finish(0, .success(self.page([1])))
    try self.provider.pages.finish(1, .success(self.page([2])))
    await old.value
    await independent.value
    XCTAssertTrue(self.feature.pageSnapshot(route: self.route).projects.isEmpty)
    XCTAssertEqual(self.feature.pageSnapshot(route: other).projects.map(\.id), [2])
  }

  func testRichTextListSharesAndCachesAcrossTemporaryDisappearance() async throws {
    let first = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(1)
    let admitted = expectation(description: "List caller entered")
    let second = Task {
      admitted.fulfill()
      await self.feature.loadRichTextProjects(route: self.route)
    }
    await fulfillment(of: [admitted], timeout: 2)
    try self.provider.lists.finish(0, .success([self.item]))
    await first.value
    await second.value
    self.feature.suspend(route: self.route)
    await self.feature.loadRichTextProjects(route: self.route)
    XCTAssertEqual(self.provider.lists.count, 1)
    XCTAssertEqual(self.feature.richTextSnapshot(route: self.route).projects, [self.item])
    XCTAssertFalse(self.feature.richTextSnapshot(route: self.route).isLoading)
  }

  func testRichTextFailureAndEmptySuccessCanRetry() async throws {
    let first = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(1)
    let error = NSError(
      domain: "Example", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"])
    try self.provider.lists.finish(0, .failure(error))
    await first.value
    XCTAssertEqual(self.feature.richTextSnapshot(route: self.route).errorMessage, "Offline")
    let retry = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(2)
    XCTAssertNil(self.feature.richTextSnapshot(route: self.route).errorMessage)
    try self.provider.lists.finish(1, .success([]))
    await retry.value
    let again = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(3)
    try self.provider.lists.finish(2, .success([self.item]))
    await again.value
    XCTAssertEqual(self.feature.richTextSnapshot(route: self.route).projects.count, 1)
  }

  func testSuspendedListIgnoresLateErrorAndCanReopen() async throws {
    let old = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(1)
    self.feature.suspend(route: self.route)
    let new = Task { await self.feature.loadRichTextProjects(route: self.route) }
    await self.provider.lists.waitFor(2)
    try self.provider.lists.finish(1, .success([self.item]))
    await new.value
    try self.provider.lists.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await old.value
    XCTAssertNil(self.feature.richTextSnapshot(route: self.route).errorMessage)
    XCTAssertEqual(self.feature.richTextSnapshot(route: self.route).projects, [self.item])
  }

  func testSlugAndURLSharePendingLookup() async throws {
    let first = Task {
      try await self.feature.loadProject(input: "owner/project", route: self.route)
    }
    await self.provider.lookups.waitFor(1)
    let admitted = expectation(description: "URL caller entered")
    let second = Task {
      admitted.fulfill()
      return try await self.feature.loadProject(
        input: "https://www.kickstarter.com/projects/owner/project/rewards", route: self.route)
    }
    await fulfillment(of: [admitted], timeout: 2)
    try self.provider.lookups.finish(0, .success(self.item))
    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertEqual(firstValue, self.item)
    XCTAssertEqual(secondValue, self.item)
    XCTAssertEqual(self.provider.slugs, ["owner/project"])
  }

  func testClearingInputCancelsOldLookupWithoutReportingNotFound() async throws {
    let old = Task { try await self.feature.loadProject(input: "owner/old", route: self.route) }
    await self.provider.lookups.waitFor(1)
    let invalid = try await self.feature.loadProject(input: "", route: self.route)
    XCTAssertNil(invalid)
    try self.provider.lookups.finish(0, .success(self.item))
    await self.cancelled(old)
    XCTAssertEqual(self.provider.lookups.count, 1)
  }

  func testChangedSlugAndReleaseRejectLateLookups() async throws {
    let old = Task { try await self.feature.loadProject(input: "owner/old", route: self.route) }
    await self.provider.lookups.waitFor(1)
    let new = Task { try await self.feature.loadProject(input: "owner/new", route: self.route) }
    await self.provider.lookups.waitFor(2)
    try self.provider.lookups.finish(0, .success(self.item))
    await self.cancelled(old)
    self.feature.release(route: self.route)
    try self.provider.lookups.finish(1, .success(self.item))
    await self.cancelled(new)
  }

  func testSessionReplacementRejectsAllExampleResults() async throws {
    let page = Task { await self.feature.loadFirstPage(route: self.route) }
    let list = Task { await self.feature.loadRichTextProjects(route: self.route) }
    let lookup = Task {
      try await self.feature.loadProject(input: "owner/project", route: self.route)
    }
    await self.provider.pages.waitFor(1)
    await self.provider.lists.waitFor(1)
    await self.provider.lookups.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    self.feature.reset()
    try self.provider.pages.finish(0, .success(self.page([1])))
    try self.provider.lists.finish(0, .success([self.item]))
    try self.provider.lookups.finish(0, .success(self.item))
    await page.value
    await list.value
    await self.cancelled(lookup)
    XCTAssertTrue(self.feature.pageSnapshot(route: self.route).projects.isEmpty)
    XCTAssertTrue(self.feature.richTextSnapshot(route: self.route).projects.isEmpty)
  }
}

@MainActor private final class ControlledExamplesProvider: DeveloperExamplesProvider {
  let pages = AccountRequestGate<DiscoveryEnvelope>()
  let lists = AccountRequestGate<[DeveloperExamplesFeature.ProjectItem]>()
  let lookups = AccountRequestGate<DeveloperExamplesFeature.ProjectItem?>()
  var parameters: [DiscoveryParams] = []
  var cursors: [String?] = []
  var slugs: [String] = []
  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    self.parameters.append(parameters)
    self.cursors.append(cursor)
    return try await self.pages.request()
  }
  func projects() async throws -> [DeveloperExamplesFeature.ProjectItem] {
    try await self.lists.request()
  }
  func project(slug: String) async throws -> DeveloperExamplesFeature.ProjectItem? {
    self.slugs.append(slug)
    return try await self.lookups.request()
  }
}
