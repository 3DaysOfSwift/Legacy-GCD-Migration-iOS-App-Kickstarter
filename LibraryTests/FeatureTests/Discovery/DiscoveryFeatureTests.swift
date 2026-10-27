import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveSwift
import XCTest

@MainActor
final class DiscoveryFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testConstructionDoesNotLoadAnyFeed() {
    let provider = ControlledDiscoveryProvider()
    let feature = DiscoveryFeature(provider: provider)
    XCTAssertTrue(provider.requests.isEmpty)
    XCTAssertTrue(feature.snapshot(for: .magic).projects.isEmpty)
    XCTAssertFalse(feature.snapshot(for: .popular).isLoading)
  }

  func testAwaitableRefreshPublishesBeforeReturning() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let command = Task { await feature.refresh(sort: .magic, parameters: .defaults) }
    await provider.waitForCount(1)
    XCTAssertTrue(feature.snapshot(for: .magic).isLoading)
    try provider.complete(0, ids: [1, 2])
    await command.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1, 2])
    XCTAssertFalse(feature.snapshot(for: .magic).isLoading)
    XCTAssertNil(feature.snapshot(for: .magic).error)
  }

  func testAllFourFeedsLoadIndependentlyAndKeepTheirOwnSort() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let sorts: [DiscoveryParams.Sort] = [.magic, .popular, .newest, .endingSoon]
    var tasks: [Task<Void, Never>] = []
    for sort in sorts {
      tasks.append(feature.requestRefresh(sort: sort, parameters: .defaults))
      await provider.waitForCount(tasks.count)
    }
    for index in sorts.indices.reversed() {
      XCTAssertEqual(provider.requests[index].parameters.sort, sorts[index])
      try provider.complete(index, ids: [index + 1])
      await tasks[index].value
      XCTAssertEqual(feature.snapshot(for: sorts[index]).projects.map(\.id), [index + 1])
    }
  }

  func testEquivalentRefreshAndNextPageCallersShareInFlightWork() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let first = feature.requestRefresh(sort: .magic, parameters: .defaults)
    let duplicate = feature.requestRefresh(sort: .magic, parameters: .defaults)
    XCTAssertEqual(first, duplicate)
    XCTAssertEqual(first, feature.requestNextPage(sort: .magic))
    await provider.waitForCount(1)
    try provider.complete(0, ids: [1])
    await first.value
    let next = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    XCTAssertEqual(next, feature.requestNextPage(sort: .magic))
    await provider.waitForCount(2)
    try provider.complete(1, ids: [2])
    await next.value
    XCTAssertEqual(provider.requests.count, 2)
  }

  func testChangedFiltersRejectLateResponseWithoutClearingNewLoading() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let old = feature.requestRefresh(sort: .magic, parameters: .defaults)
    await provider.waitForCount(1)
    let changed = DiscoveryParams.defaults |> DiscoveryParams.lens.staffPicks .~ true
    let new = feature.requestRefresh(sort: .magic, parameters: changed)
    await provider.waitForCount(2)
    try provider.complete(0, ids: [10])
    await old.value
    XCTAssertTrue(feature.snapshot(for: .magic).projects.isEmpty)
    XCTAssertTrue(feature.snapshot(for: .magic).isLoading)
    try provider.complete(1, ids: [20])
    await new.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [20])
    XCTAssertEqual(feature.snapshot(for: .magic).parameters?.staffPicks, true)
  }

  func testRefreshRetainsCardsThenReplacesAndRejectsOldPagination() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let first = feature.requestRefresh(sort: .magic, parameters: .defaults)
    await provider.waitForCount(1)
    try provider.complete(0, ids: [1])
    await first.value
    let page = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    await provider.waitForCount(2)
    let refresh = feature.requestRefresh(sort: .magic, parameters: .defaults, force: true)
    await provider.waitForCount(3)
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1])
    try provider.complete(2, ids: [3])
    await refresh.value
    try provider.complete(1, ids: [2])
    await page.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [3])
  }

  func testPaginationUsesCursorDeduplicatesAndStopsAfterEmptyPage() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    XCTAssertNil(feature.requestNextPage(sort: .magic))
    let first = feature.requestRefresh(sort: .magic, parameters: .defaults)
    await provider.waitForCount(1)
    try provider.complete(0, ids: [1, 2], cursor: "page-two")
    await first.value
    let next = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    await provider.waitForCount(2)
    XCTAssertEqual(provider.requests[1].cursor, "page-two")
    try provider.complete(1, ids: [2, 3], cursor: "page-three")
    await next.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1, 2, 3])
    let last = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    await provider.waitForCount(3)
    try provider.complete(2, ids: [])
    await last.value
    XCTAssertFalse(feature.snapshot(for: .magic).hasMore)
    XCTAssertNil(feature.requestNextPage(sort: .magic))
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1, 2, 3])
  }

  func testPaginationFailureRetainsCardsAndRetriesSameCursor() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let first = feature.requestRefresh(sort: .magic, parameters: .defaults)
    await provider.waitForCount(1)
    try provider.complete(0, ids: [1], cursor: "retry-me")
    await first.value
    let next = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    await provider.waitForCount(2)
    try provider.fail(1)
    await next.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1])
    XCTAssertNotNil(feature.snapshot(for: .magic).error)
    XCTAssertFalse(feature.snapshot(for: .magic).isLoading)
    let retry = try XCTUnwrap(feature.requestNextPage(sort: .magic))
    await provider.waitForCount(3)
    XCTAssertEqual(provider.requests[2].cursor, "retry-me")
    try provider.complete(2, ids: [2])
    await retry.value
    XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [1, 2])
    XCTAssertNil(feature.snapshot(for: .magic).error)
  }

  func testCancelOneFeedDoesNotCancelAnotherAndRejectsLateResults() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let magic = feature.requestRefresh(sort: .magic, parameters: .defaults)
    await provider.waitForCount(1)
    let popular = feature.requestRefresh(sort: .popular, parameters: .defaults)
    await provider.waitForCount(2)
    feature.cancel(sort: .magic)
    XCTAssertFalse(feature.snapshot(for: .magic).isLoading)
    XCTAssertTrue(feature.snapshot(for: .popular).isLoading)
    try provider.complete(0, ids: [1])
    try provider.complete(1, ids: [2])
    await magic.value
    await popular.value
    XCTAssertTrue(feature.snapshot(for: .magic).projects.isEmpty)
    XCTAssertNil(feature.snapshot(for: .magic).error)
    XCTAssertEqual(feature.snapshot(for: .popular).projects.map(\.id), [2])
  }

  func testNativeDecoderPreservesSuccessAndServerErrorContract() throws {
    let url = try XCTUnwrap(URL(string: "https://example.invalid/discover"))
    let ok = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json; charset=utf-8"]))
    let envelope: DiscoveryEnvelope = try Service.decodeDiscoveryResponse(
      Data(#"{"projects":[],"urls":{"api":{"more_projects":"next"}},"stats":{"count":0}}"#.utf8), response: ok
    )
    XCTAssertTrue(envelope.projects.isEmpty)
    XCTAssertEqual(envelope.urls.api.moreProjects, "next")
    let denied = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]))
    XCTAssertThrowsError(try Service.decodeDiscoveryResponse(
      Data(#"{"error_messages":["Denied"],"http_code":403,"ksr_code":"invalid_access_token"}"#.utf8),
      response: denied
    ) as DiscoveryEnvelope) { error in
      XCTAssertEqual((error as? ErrorEnvelope)?.errorMessages, ["Denied"])
    }
    XCTAssertThrowsError(try Service.decodeDiscoveryResponse(Data("bad".utf8), response: ok) as DiscoveryEnvelope)
  }

  func testActivityReplacementRejectsLateSampleAndRetainsErrorSeparately() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let old = feature.requestActivitySample(sort: .magic)
    await provider.waitForCount(1)
    let new = feature.requestActivitySample(sort: .magic)
    await provider.waitForCount(2)
    try provider.complete(1, id: 2)
    await new.value
    try provider.complete(0, id: 1)
    await old.value
    XCTAssertEqual(feature.snapshot(for: .magic).activitySample.map(\.id), [2])
    let failure = feature.requestActivitySample(sort: .magic)
    await provider.waitForCount(3)
    try provider.fail(2)
    await failure.value
    XCTAssertEqual(feature.snapshot(for: .magic).activitySample.map(\.id), [2])
    XCTAssertNotNil(feature.snapshot(for: .magic).activityError)
    XCTAssertNil(feature.snapshot(for: .magic).error)
  }

  func testOwnerCancellationRejectsLateActivityWithoutAffectingOtherFeed() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let magic = feature.requestActivitySample(sort: .magic)
    await provider.waitForCount(1)
    let popular = feature.requestActivitySample(sort: .popular)
    await provider.waitForCount(2)
    feature.cancel(sort: .magic)
    try provider.complete(0, id: 1)
    try provider.complete(1, id: 2)
    await magic.value
    await popular.value
    XCTAssertTrue(feature.snapshot(for: .magic).activitySample.isEmpty)
    XCTAssertNil(feature.snapshot(for: .magic).activityError)
    XCTAssertEqual(feature.snapshot(for: .popular).activitySample.map(\.id), [2])
  }

  func testMockUsesSameDemoDiscoveryFixturesThroughNativeAsyncRoute() async throws {
    let service = MockService.publicDemo()
    let envelope = try await service.discoveryPage(params: .defaults)
    XCTAssertFalse(envelope.projects.isEmpty)
    XCTAssertTrue(envelope.projects.allSatisfy { $0.name.hasPrefix("[Demo]") })
    let next = try await service.discoveryPage(paginationURL: envelope.urls.api.moreProjects)
    XCTAssertFalse(next.projects.isEmpty)
  }

  func testRecommendationDefaultsAndFilterSelectionBelongToFeatureWithoutFetching() {
    let provider = ControlledDiscoveryProvider()
    let feature = DiscoveryFeature(provider: provider)
    let optedIn = User.template |> User.lens.optedOutOfRecommendations .~ false
    let optedOut = User.template |> User.lens.optedOutOfRecommendations .~ true
    XCTAssertEqual(DiscoveryFeature.initialParameters(for: nil).includePOTD, true)
    XCTAssertEqual(DiscoveryFeature.initialParameters(for: optedOut).includePOTD, true)
    XCTAssertEqual(DiscoveryFeature.initialParameters(for: optedIn), .recommendedDefaults)
    let parameters = DiscoveryParams.defaults |> DiscoveryParams.lens.category .~ .art
    feature.selectFilter(parameters)
    XCTAssertEqual(feature.selectedParameters, parameters)
    XCTAssertTrue(provider.requests.isEmpty, "Selection must not eagerly fetch hidden feeds")
  }

  func testDelayedProjectsFromPreviousAccountCannotPublish() async throws {
    let provider = ControlledDiscoveryProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    let firstUser = User.template |> User.lens.id .~ 1
    let secondUser = User.template |> User.lens.id .~ 2
    await withEnvironment(currentUser: firstUser) {
      let old = feature.requestRefresh(sort: .magic, parameters: .defaults)
      await provider.waitForCount(1)
      await withEnvironment(currentUser: secondUser) {
        XCTAssertNil(feature.requestNextPage(sort: .magic), "Do not reuse another account's cursor/task")
        let new = feature.requestRefresh(sort: .magic, parameters: .defaults)
        XCTAssertNotEqual(old, new, "Same filters under another account are not equivalent work")
        await provider.waitForCount(2)
        do { try provider.complete(0, ids: [1]) } catch { XCTFail("\(error)") }
        await old.value
        XCTAssertTrue(feature.snapshot(for: .magic).projects.isEmpty)
        XCTAssertTrue(feature.snapshot(for: .magic).isLoading)
        XCTAssertNil(feature.snapshot(for: .magic).error)
        do { try provider.complete(1, ids: [2]) } catch { XCTFail("\(error)") }
        await new.value
        XCTAssertEqual(feature.snapshot(for: .magic).projects.map(\.id), [2])
      }
    }
  }

  func testDelayedActivityFromPreviousAccountCannotPublish() async {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = DiscoveryFeature(provider: provider, sleep: { _ in })
    await withEnvironment(currentUser: User.template |> User.lens.id .~ 1) {
      let old = feature.requestActivitySample(sort: .magic)
      await provider.waitForCount(1)
      await withEnvironment(currentUser: User.template |> User.lens.id .~ 2) {
        do { try provider.complete(0, id: 1) } catch { XCTFail("\(error)") }
        await old.value
        XCTAssertTrue(feature.snapshot(for: .magic).activitySample.isEmpty)
        XCTAssertNil(feature.snapshot(for: .magic).activityError)
      }
    }
  }
}

@MainActor
private final class ControlledActivityProvider: DiscoveryProvider {
  private var continuations: [CheckedContinuation<ActivityEnvelope?, Error>?] = []
  private var arrivals: [(Int, XCTestExpectation)] = []

  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    XCTFail("Activity commands must not load projects")
    throw CancellationError()
  }

  func activitySample() async throws -> ActivityEnvelope? {
    try await withCheckedThrowingContinuation { continuation in
      self.continuations.append(continuation)
      let ready = self.arrivals.filter { self.continuations.count >= $0.0 }
      self.arrivals.removeAll { self.continuations.count >= $0.0 }
      ready.forEach { $0.1.fulfill() }
    }
  }

  func waitForCount(_ count: Int) async {
    guard self.continuations.count < count else { return }
    let arrival = XCTestExpectation(description: "activity request \(count)")
    self.arrivals.append((count, arrival))
    let result = await XCTWaiter.fulfillment(of: [arrival], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func complete(_ index: Int, id: Int) throws {
    let continuation = try XCTUnwrap(self.continuations.indices.contains(index) ? self.continuations[index] : nil)
    self.continuations[index] = nil
    continuation.resume(returning: ActivityEnvelope(
      activities: [Activity.template |> Activity.lens.id .~ id],
      urls: .init(api: .init(moreActivities: "next"))
    ))
  }

  func fail(_ index: Int) throws {
    let continuation = try XCTUnwrap(self.continuations.indices.contains(index) ? self.continuations[index] : nil)
    self.continuations[index] = nil
    continuation.resume(throwing: ErrorEnvelope.couldNotParseJSON)
  }

  func releaseAll() {
    for index in self.continuations.indices {
      self.continuations[index]?.resume(throwing: CancellationError())
      self.continuations[index] = nil
    }
  }
}

@MainActor
private final class ControlledDiscoveryProvider: DiscoveryProvider {
  struct Request {
    let parameters: DiscoveryParams
    let cursor: String?
    var continuation: CheckedContinuation<DiscoveryEnvelope, Error>?
  }
  private(set) var requests: [Request] = []
  private var arrivals: [(Int, XCTestExpectation)] = []

  func page(parameters: DiscoveryParams, cursor: String?) async throws -> DiscoveryEnvelope {
    // Deliberately ignore cancellation to exercise the Feature's identity guard.
    try await withCheckedThrowingContinuation { continuation in
      self.requests.append(Request(parameters: parameters, cursor: cursor, continuation: continuation))
      let ready = self.arrivals.filter { self.requests.count >= $0.0 }
      self.arrivals.removeAll { self.requests.count >= $0.0 }
      ready.forEach { $0.1.fulfill() }
    }
  }

  func activitySample() async throws -> ActivityEnvelope? { nil }

  func waitForCount(_ count: Int) async {
    guard self.requests.count < count else { return }
    let arrival = XCTestExpectation(description: "discovery request \(count)")
    self.arrivals.append((count, arrival))
    let result = await XCTWaiter.fulfillment(of: [arrival], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func complete(_ index: Int, ids: [Int], cursor: String = "next") throws {
    let continuation = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index].continuation : nil)
    self.requests[index].continuation = nil
    continuation.resume(returning: DiscoveryEnvelope.template
      |> DiscoveryEnvelope.lens.projects .~ ids.map { Project.template |> Project.lens.id .~ $0 }
      |> DiscoveryEnvelope.lens.urls.api.moreProjects .~ cursor)
  }

  func fail(_ index: Int) throws {
    let continuation = try XCTUnwrap(self.requests.indices.contains(index) ? self.requests[index].continuation : nil)
    self.requests[index].continuation = nil
    continuation.resume(throwing: ErrorEnvelope.couldNotParseErrorEnvelopeJSON)
  }

  func releaseAll() {
    for index in self.requests.indices {
      self.requests[index].continuation?.resume(throwing: CancellationError())
      self.requests[index].continuation = nil
    }
  }
}
