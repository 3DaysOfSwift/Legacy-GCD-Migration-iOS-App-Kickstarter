import Foundation
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class SearchLookupTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private let provider = ControlledSearchLookupProvider()
  private lazy var feature = SearchFeature(
    provider: AsyncSearchProjectsProvider(), lookupProvider: self.provider,
    lookupSleep: { _ in }, sleep: { _ in }
  )

  override func tearDown() {
    MainActor.assumeIsolated {
      self.feature.cancelFilterLookups()
      self.provider.releaseAll()
    }
    super.tearDown()
  }

  func testConstructionDoesNotFetchOrPublish() {
    XCTAssertTrue(self.provider.categories.keys.isEmpty)
    XCTAssertTrue(self.provider.locations.keys.isEmpty)
    XCTAssertTrue(self.feature.categoryOptions.isEmpty)
    XCTAssertFalse(self.feature.isLoadingSuggestions)
  }

  func testClearImmediatelyRejectsLateSuccessAndAllowsSameQueryAgain() async throws {
    let old = try XCTUnwrap(self.feature.requestLocations("Fairfax"))
    await self.provider.locations.waitForCount(1)
    await self.feature.searchLocations("")
    XCTAssertEqual(self.feature.locationQuery, "")
    XCTAssertTrue(self.feature.suggestedLocationOptions.isEmpty)
    XCTAssertFalse(self.feature.isLoadingSuggestions)

    // Deliberately non-cooperative transport returns after cancellation.
    try self.provider.locations.complete(0, .success([.template]))
    await old.value
    XCTAssertTrue(self.feature.suggestedLocationOptions.isEmpty)
    XCTAssertNil(self.feature.suggestedLocationsError)
    XCTAssertTrue(self.provider.locations.cancelledAtReturn.contains(0))

    let retry = try XCTUnwrap(self.feature.requestLocations("Fairfax"))
    await self.provider.locations.waitForCount(2)
    try self.provider.locations.complete(1, .success([.template]))
    await retry.value
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
  }

  func testClearRejectsLateError() async throws {
    let old = try XCTUnwrap(self.feature.requestLocations("old"))
    await self.provider.locations.waitForCount(1)
    await self.feature.searchLocations("")
    try self.provider.locations.complete(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await old.value
    XCTAssertNil(self.feature.suggestedLocationsError)
    XCTAssertFalse(self.feature.isLoadingSuggestions)
    XCTAssertTrue(self.feature.suggestedLocationOptions.isEmpty)
  }

  func testOldFailureAndCleanupCannotStopNewQuery() async throws {
    let old = try XCTUnwrap(self.feature.requestLocations("old"))
    await self.provider.locations.waitForCount(1)
    let current = try XCTUnwrap(self.feature.requestLocations("new"))
    await self.provider.locations.waitForCount(2)
    try self.provider.locations.complete(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await old.value
    XCTAssertTrue(self.feature.isLoadingSuggestions)
    XCTAssertNil(self.feature.suggestedLocationsError)
    XCTAssertEqual(self.feature.locationQuery, "new")
    try self.provider.locations.complete(1, .success([.template]))
    await current.value
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
  }

  func testNewSuccessRemainsAfterOldSuccessArrives() async throws {
    let old = try XCTUnwrap(self.feature.requestLocations("old"))
    await self.provider.locations.waitForCount(1)
    let current = try XCTUnwrap(self.feature.requestLocations("new"))
    await self.provider.locations.waitForCount(2)
    try self.provider.locations.complete(1, .success([.template]))
    await current.value
    try self.provider.locations.complete(0, .success([]))
    await old.value
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
    XCTAssertFalse(self.feature.isLoadingSuggestions)
  }

  func testEquivalentQuerySharesCompletionAndCancelledWaiterDoesNotCancelOwner() async throws {
    let operation = try XCTUnwrap(self.feature.requestLocations("same"))
    await self.provider.locations.waitForCount(1)
    let joined = try XCTUnwrap(self.feature.requestLocations("same"))
    var waiterFinished = false
    let waiterStarted = expectation(description: "waiter admitted")
    let waiter = Task { @MainActor in
      waiterStarted.fulfill()
      await self.feature.searchLocations("same")
      waiterFinished = true
    }
    await fulfillment(of: [waiterStarted], timeout: 2)
    waiter.cancel()
    XCTAssertFalse(waiterFinished)
    XCTAssertEqual(self.provider.locations.keys, ["same"])
    try self.provider.locations.complete(0, .success([.template]))
    await operation.value
    await joined.value
    await waiter.value
    XCTAssertTrue(waiterFinished)
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
    XCTAssertFalse(self.provider.locations.cancelledAtReturn.contains(0))
  }

  func testFailureRetainsPreviousSuggestionsAndRetryClearsError() async throws {
    let first = try XCTUnwrap(self.feature.requestLocations("first"))
    await self.provider.locations.waitForCount(1)
    try self.provider.locations.complete(0, .success([.template]))
    await first.value
    let failed = try XCTUnwrap(self.feature.requestLocations("retry"))
    await self.provider.locations.waitForCount(2)
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
    try self.provider.locations.complete(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await failed.value
    XCTAssertNotNil(self.feature.suggestedLocationsError)
    XCTAssertEqual(self.feature.suggestedLocationOptions, [.template])
    XCTAssertFalse(self.feature.isLoadingSuggestions)

    let retry = try XCTUnwrap(self.feature.requestLocations("retry"))
    await self.provider.locations.waitForCount(3)
    XCTAssertNil(self.feature.suggestedLocationsError)
    try self.provider.locations.complete(2, .success([]))
    await retry.value
    XCTAssertTrue(self.feature.suggestedLocationOptions.isEmpty)
  }

  func testWhitespaceIsStillAQueryAndPrecancelledCommandDoesNotAdmit() async throws {
    let cancelled = Task { @MainActor in await self.feature.searchLocations("ignored") }
    cancelled.cancel()
    await cancelled.value
    XCTAssertTrue(self.provider.locations.keys.isEmpty)
    let whitespace = try XCTUnwrap(self.feature.requestLocations(" "))
    await self.provider.locations.waitForCount(1)
    XCTAssertEqual(self.provider.locations.keys, [" "])
    try self.provider.locations.complete(0, .success([]))
    await whitespace.value
  }

  func testInitialOutputsAreEmptyAndIndependentDefaultsDoNotWaitForCategories() async throws {
    var defaults: [[Location]] = []
    var suggestions: [[Location]] = []
    let defaultsPublished = expectation(description: "defaults published independently")
    let firstObservation = self.feature.defaultLocations.observeValues {
      defaults.append($0)
      if $0 == [.template] { defaultsPublished.fulfill() }
    }
    let secondObservation = self.feature.suggestedLocations.observeValues { suggestions.append($0) }
    defer { firstObservation?.dispose(); secondObservation?.dispose() }
    let first = self.feature.requestFilterOptions()
    let duplicate = self.feature.requestFilterOptions()
    XCTAssertEqual(defaults, [[]])
    XCTAssertEqual(suggestions, [[]])
    await self.provider.categories.waitForCount(1)
    await self.provider.locations.waitForCount(1)
    XCTAssertEqual(self.provider.categories.keys, ["categories"])
    XCTAssertEqual(self.provider.locations.keys, ["defaults"])
    try self.provider.locations.complete(0, .success([.template]))
    // The default command publishes independently of the still-suspended categories.
    await fulfillment(of: [defaultsPublished], timeout: 2)
    XCTAssertEqual(self.feature.defaultLocationOptions, [.template])
    XCTAssertTrue(self.feature.isLoadingCategories)
    try self.provider.categories.complete(0, .success([.art]))
    await first.value
    await duplicate.value
    XCTAssertEqual(self.feature.categoryOptions, [.art])
    XCTAssertEqual(self.provider.cachedCategories, [.art])
    XCTAssertFalse(self.feature.isLoadingCategories)
    XCTAssertFalse(self.feature.isLoadingDefaultLocations)
  }

  func testNonemptyCategoryCacheIsImmediateAndDoesNotFetch() async throws {
    self.provider.cachedCategories = [.art, .games]
    let operation = self.feature.requestFilterOptions()
    XCTAssertEqual(self.feature.categoryOptions, [.art, .games])
    XCTAssertFalse(self.feature.isLoadingCategories)
    await self.provider.locations.waitForCount(1)
    XCTAssertTrue(self.provider.categories.keys.isEmpty)
    try self.provider.locations.complete(0, .success([]))
    await operation.value
  }

  func testEmptyCacheFetchesAndFailuresRetryIndependently() async throws {
    self.provider.cachedCategories = []
    let first = self.feature.requestFilterOptions()
    await self.provider.categories.waitForCount(1)
    await self.provider.locations.waitForCount(1)
    try self.provider.categories.complete(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try self.provider.locations.complete(0, .success([.template]))
    await first.value
    XCTAssertNotNil(self.feature.categoryError)
    XCTAssertNil(self.feature.defaultLocationsError)
    XCTAssertEqual(self.feature.defaultLocationOptions, [.template])
    XCTAssertEqual(self.provider.cachedCategories, [])

    let retry = self.feature.requestFilterOptions()
    await self.provider.categories.waitForCount(2)
    await self.provider.locations.waitForCount(2)
    try self.provider.categories.complete(1, .success([.games]))
    try self.provider.locations.complete(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await retry.value
    XCTAssertNil(self.feature.categoryError)
    XCTAssertNotNil(self.feature.defaultLocationsError)
    XCTAssertEqual(self.feature.categoryOptions, [.games])
    XCTAssertFalse(self.feature.isLoadingDefaultLocations)
  }

  func testCancelledOptionsCannotPublishOrOverwriteCacheAfterRetry() async throws {
    let old = self.feature.requestFilterOptions()
    await self.provider.categories.waitForCount(1)
    await self.provider.locations.waitForCount(1)
    self.feature.cancelFilterLookups()
    let current = self.feature.requestFilterOptions()
    await self.provider.categories.waitForCount(2)
    await self.provider.locations.waitForCount(2)
    try self.provider.categories.complete(0, .success([.art]))
    try self.provider.locations.complete(0, .success([.template]))
    await old.value
    XCTAssertTrue(self.feature.isLoadingCategories)
    XCTAssertTrue(self.feature.isLoadingDefaultLocations)
    XCTAssertNil(self.provider.cachedCategories)
    try self.provider.categories.complete(1, .success([.games]))
    try self.provider.locations.complete(1, .success([]))
    await current.value
    XCTAssertEqual(self.provider.cachedCategories, [.games])
    XCTAssertTrue(self.feature.defaultLocationOptions.isEmpty)
  }

  func testLiveProviderMapsDefaultAndSuggestedLocationFixtures() async throws {
    let defaults: GraphAPI.DefaultLocationsQuery.Data = try testGraphObject(jsonString: threeLocationsResponseJSON)
    let suggestions: GraphAPI.LocationsByTermQuery.Data = try testGraphObject(jsonString: threeLocationsResponseJSON)
    AppEnvironment.pushEnvironment(apiService: MockService(fetchGraphQLResponses: [
      (GraphAPI.DefaultLocationsQuery.self, defaults),
      (GraphAPI.LocationsByTermQuery.self, suggestions)
    ]))
    defer { AppEnvironment.popEnvironment() }
    let provider = AsyncSearchLookupProvider()
    let defaultValues = try await provider.fetchDefaultLocations()
    let suggestedValues = try await provider.fetchLocations(query: "Fairfax")
    XCTAssertEqual(defaultValues.count, 3)
    XCTAssertEqual(suggestedValues, defaultValues)
    XCTAssertEqual(suggestedValues.first?.displayableName, "Fairfax, VA")
  }

  func testLiveProviderUsesExistingCacheAndMockCategoryFixture() async throws {
    let cache = KSCache()
    let provider = AsyncSearchLookupProvider()
    AppEnvironment.pushEnvironment(
      apiService: MockService(fetchGraphCategoriesResult: .success(
        RootCategoriesEnvelope(rootCategories: [.art, .games])
      )), cache: cache
    )
    defer { AppEnvironment.popEnvironment() }
    XCTAssertNil(provider.cachedCategories)
    let categories = try await provider.fetchCategories()
    provider.cache(categories: categories)
    XCTAssertEqual(cache[KSCache.ksr_discoveryFiltersCategories] as? [KsApi.Category], [.art, .games])
    XCTAssertEqual(provider.cachedCategories, [.art, .games])
  }
}

/// Suspends even when cancelled: tests control late success/failure delivery.
@MainActor
private final class LookupGate<Value> {
  private(set) var keys: [String] = []
  private var pending: [Int: CheckedContinuation<Value, Error>] = [:]
  private(set) var cancelledAtReturn: Set<Int> = []
  private var onStart: (() -> Void)?

  func value(key: String) async throws -> Value {
    let index = self.keys.count
    self.keys.append(key)
    defer {
      if Task.isCancelled { self.cancelledAtReturn.insert(index) }
    }
    return try await withCheckedThrowingContinuation { continuation in
      self.pending[index] = continuation
      self.onStart?()
    }
  }

  func complete(_ index: Int, _ result: Result<Value, Error>) throws {
    let continuation = try XCTUnwrap(self.pending.removeValue(forKey: index))
    continuation.resume(with: result)
  }

  func waitForCount(_ count: Int) async {
    guard self.keys.count < count else { return }
    let started = XCTestExpectation(description: "lookup admitted")
    self.onStart = { [weak self] in if self?.keys.count == count { started.fulfill() } }
    defer { self.onStart = nil }
    let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func releaseAll() {
    let pending = self.pending
    self.pending.removeAll()
    for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
  }
}

@MainActor
private final class ControlledSearchLookupProvider: SearchLookupProvider {
  var cachedCategories: [KsApi.Category]?
  let categories = LookupGate<[KsApi.Category]>()
  let locations = LookupGate<[Location]>()

  func cache(categories: [KsApi.Category]) { self.cachedCategories = categories }
  func fetchCategories() async throws -> [KsApi.Category] { try await self.categories.value(key: "categories") }
  func fetchDefaultLocations() async throws -> [Location] { try await self.locations.value(key: "defaults") }
  func fetchLocations(query: String) async throws -> [Location] { try await self.locations.value(key: query) }
  func releaseAll() { self.categories.releaseAll(); self.locations.releaseAll() }
}

private let threeLocationsResponseJSON = """
{
    "locations": {
      "__typename": "LocationsConnection",
      "nodes": [
        {
          "__typename": "Location",
          "country": "US",
          "countryName": "United States",
          "displayableName": "Fairfax, VA",
          "id": "TG9jYXRpb24tMjQwMTM0OA==",
          "name": "Fairfax"
        },
        {
          "__typename": "Location",
          "country": "US",
          "countryName": "United States",
          "displayableName": "Fairfax, CA",
          "id": "TG9jYXRpb24tMjQwMTM0OQ==",
          "name": "Fairfax"
        },
        {
          "__typename": "Location",
          "country": "US",
          "countryName": "United States",
          "displayableName": "Fairfax, Jacksonville, FL",
          "id": "TG9jYXRpb24tMjkyMjk5NTk=",
          "name": "Fairfax"
        }
      ]
    }
}
"""
