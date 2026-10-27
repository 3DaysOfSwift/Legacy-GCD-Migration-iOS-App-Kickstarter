import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Observation
import ReactiveSwift
import XCTest

@MainActor
final class ProjectMediaFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testFeedObservationPublishesInitialFlagBeforeReloadAndSaveDoesNotReload() async {
    let provider = ControlledMediaProvider()
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    let state = feature.feedState(route: route)
    var initialFlagAtReload = false
    withObservationTracking {
      _ = state.fetchedItems
    } onChange: {
      MainActor.assumeIsolated { initialFlagAtReload = state.isInitialLoadComplete }
    }
    await feature.loadFeed(route: route)
    XCTAssertTrue(initialFlagAtReload)
    var reloadedForSave = false
    withObservationTracking {
      _ = state.fetchedItems
    } onChange: {
      MainActor.assumeIsolated { reloadedForSave = true }
    }
    let save = feature.toggleSaved(route: route, projectID: "one")
    await save?.value
    XCTAssertFalse(reloadedForSave)
    XCTAssertTrue(state.items[0].isSaved)
    XCTAssertFalse(state.fetchedItems[0].isSaved)
  }

  func testFeedEquivalentLoadsShareAndEmptyRefreshRetainsExistingItems() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseFeed = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    let state = feature.feedState(route: route)
    let first = feature.requestFeed(route: route)
    let duplicate = feature.requestFeed(route: route)
    await provider.waitForFeeds(1)
    XCTAssertTrue(state.isLoading)
    try provider.finishFeed(0, items: provider.feedItems)
    await first.value
    await duplicate.value
    XCTAssertEqual(provider.feedCount, 1)
    XCTAssertTrue(state.isInitialLoadComplete)
    XCTAssertEqual(state.items.count, 2)
    provider.pauseFeed = false
    provider.feedItems = []
    await feature.loadFeed(route: route)
    XCTAssertTrue(state.error is ProjectMediaFeature.FeedError)
    XCTAssertEqual(state.items.count, 2, "Failed refresh does not erase usable data")
    XCTAssertFalse(state.isLoading)
  }

  func testFeedReleaseAndAccountChangeRejectLateData() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseFeed = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let firstRoute = UUID(), secondRoute = UUID()
    let releasedState = feature.feedState(route: firstRoute)
    let oldAccountState = feature.feedState(route: secondRoute)
    let released = feature.requestFeed(route: firstRoute)
    await provider.waitForFeeds(1)
    let oldAccount = feature.requestFeed(route: secondRoute)
    await provider.waitForFeeds(2)
    feature.release(route: firstRoute)
    await withEnvironment(currentUser: .template) {
      do {
        try provider.finishFeed(0, items: provider.feedItems)
        try provider.finishFeed(1, items: provider.feedItems)
      } catch {
        XCTFail("Missing controlled feed completion: \(error)")
      }
      await released.value
      await oldAccount.value
      XCTAssertTrue(releasedState.items.isEmpty)
      XCTAssertTrue(oldAccountState.items.isEmpty)
    }
  }

  func testWatchWritesShareEquivalentIntentAndSerializeChangesPerProject() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let save = feature.requestWatch(projectID: "one", watched: true)
    let duplicate = feature.requestWatch(projectID: "one", watched: true)
    let unsave = feature.requestWatch(projectID: "one", watched: false)
    let other = feature.requestWatch(projectID: "two", watched: true)
    await provider.waitForWatches(2)
    XCTAssertEqual(provider.watches.map(\.id).sorted(), ["one", "two"])
    XCTAssertTrue(provider.watches.allSatisfy(\.watched), "Unsave must wait for the first save")
    let index = try XCTUnwrap(provider.watches.firstIndex { $0.id == "one" })
    try provider.finishWatch(index)
    await provider.waitForWatches(3)
    XCTAssertEqual(provider.watches.last?.id, "one")
    XCTAssertEqual(provider.watches.last?.watched, false)
    provider.finishAllWatches()
    _ = try await save.value
    _ = try await duplicate.value
    _ = try await unsave.value
    _ = try await other.value
    XCTAssertEqual(provider.watches.count, 3)
  }

  func testFailedSaveRollsBackOnlyLatestIntentAndDoesNotReloadFeed() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    await feature.loadFeed(route: route)
    let state = feature.feedState(route: route)
    let save = try XCTUnwrap(feature.toggleSaved(route: route, projectID: "one"))
    XCTAssertTrue(state.items[0].isSaved)
    XCTAssertEqual(state.items[0].watchesCount, 4)
    XCTAssertFalse(state.fetchedItems[0].isSaved, "Save must not trigger a feed reload")
    await provider.waitForWatches(1)
    try provider.finishWatch(0, failure: true)
    await save.value
    XCTAssertFalse(state.items[0].isSaved)
    XCTAssertEqual(state.items[0].watchesCount, 3)
    XCTAssertEqual(state.saveFailedItemID, "one")
    feature.clearSaveFailure(route: route)
    XCTAssertNil(state.saveFailedItemID)
    let retry = try XCTUnwrap(feature.toggleSaved(route: route, projectID: "one"))
    await provider.waitForWatches(2)
    try provider.finishWatch(1)
    await retry.value
    XCTAssertTrue(state.items[0].isSaved)
  }

  func testRapidSaveUnsavePreservesLatestProjectionWhenOlderWriteFails() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    await feature.loadFeed(route: route)
    let state = feature.feedState(route: route)
    let first = try XCTUnwrap(feature.toggleSaved(route: route, projectID: "one"))
    let last = try XCTUnwrap(feature.toggleSaved(route: route, projectID: "one"))
    XCTAssertFalse(state.items[0].isSaved)
    XCTAssertEqual(state.items[0].watchesCount, 3)
    await provider.waitForWatches(1)
    try provider.finishWatch(0, failure: true)
    await provider.waitForWatches(2)
    await first.value
    XCTAssertNil(state.saveFailedItemID, "An obsolete failure must not undo the latest intent")
    try provider.finishWatch(1)
    await last.value
    XCTAssertFalse(state.items[0].isSaved)
    XCTAssertEqual(provider.watches.map(\.watched), [true, false])
  }

  func testRouteReleaseDoesNotCancelDurableWatchAndAccountSwitchSkipsQueuedWrite() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    await feature.loadFeed(route: route)
    let save = try XCTUnwrap(feature.toggleSaved(route: route, projectID: "one"))
    await provider.waitForWatches(1)
    feature.release(route: route)
    try provider.finishWatch(0)
    await save.value
    XCTAssertEqual(provider.watches.count, 1)

    let first = feature.requestWatch(projectID: "two", watched: true)
    let queued = feature.requestWatch(projectID: "two", watched: false)
    await provider.waitForWatches(2)
    await withEnvironment(currentUser: .template) {
      provider.finishAllWatches()
      if case .failure(is CancellationError) = await first.result {} else { XCTFail("Stale success") }
      if case .failure(is CancellationError) = await queued.result {}
      else { XCTFail("Queued old-account write") }
      XCTAssertEqual(provider.watches.count, 2)
    }
  }

  func testDuplicateEventSharesButStartAndCompletionRemainIndependent() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    var received: [Bool] = []
    let observation = feature.completions.observeValues { received.append($0.1) }
    defer { observation?.dispose() }
    let start = feature.requestReport(route: route, project: Project.template, completed: false)
    let duplicate = feature.requestReport(route: route, project: Project.template, completed: false)
    await provider.waitForRequests(1)
    let completed = feature.requestReport(route: route, project: Project.template, completed: true)
    await provider.waitForRequests(2)
    XCTAssertEqual(provider.events, [false, true])
    XCTAssertFalse(start.isCancelled)
    try provider.finish(1)
    await completed.value
    try provider.finish(0)
    await start.value
    await duplicate.value
    XCTAssertEqual(received, [true, false])
  }

  func testReleaseCancelsOnlyItsRouteAndDoesNotPublishLateSuccess() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID(), other = UUID()
    var received: [UUID] = []
    let observation = feature.completions.observeValues { received.append($0.0) }
    defer { observation?.dispose() }
    let first = feature.requestReport(route: route, project: Project.template, completed: false)
    await provider.waitForRequests(1)
    let second = feature.requestReport(route: other, project: Project.template, completed: false)
    await provider.waitForRequests(2)
    feature.release(route: route)
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
    try provider.finish(0)
    try provider.finish(1)
    await first.value
    await second.value
    XCTAssertEqual(received, [other])
  }

  func testAccountChangeSuppressesCompletionAndCancelledCallerDoesNotStart() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    var received = 0
    let observation = feature.completions.observeValues { _ in received += 1 }
    defer { observation?.dispose() }
    let pending = feature.requestReport(route: UUID(), project: Project.template, completed: true)
    await provider.waitForRequests(1)
    AppEnvironment.pushEnvironment(currentUser: .template)
    defer { AppEnvironment.popEnvironment() }
    try provider.finish(0)
    await pending.value
    let cancelled = Task { await feature.report(route: UUID(), project: Project.template, completed: false) }
    cancelled.cancel()
    await cancelled.value
    XCTAssertEqual(provider.events, [true])
    XCTAssertEqual(received, 0)
  }

  func testFailedCounterDoesNotPublishSuccessOrRetry() async {
    let feature = ProjectMediaFeature(makeProvider: {
      AsyncProjectMediaProvider(service: MockService(incrementVideoStartError: .couldNotParseJSON))
    })
    var successes = 0
    let observation = feature.completions.observeValues { _ in successes += 1 }
    defer { observation?.dispose() }
    await feature.report(route: UUID(), project: Project.template, completed: false)
    XCTAssertEqual(successes, 0)
  }
}

@MainActor
private final class ControlledMediaProvider: ProjectMediaProvider {
  var feedItems = [ControlledMediaProvider.item("one"), ControlledMediaProvider.item("two")]
  var pauseFeed = false
  var feedCount = 0
  var pauseWatch = false
  var watches: [(id: String, watched: Bool)] = []
  private var pendingFeeds: [CheckedContinuation<[VideoFeedItem], Error>?] = []
  private var pendingWatches: [CheckedContinuation<Void, Error>?] = []
  private var feedWaits: [(Int, XCTestExpectation)] = []
  private var watchWaits: [(Int, XCTestExpectation)] = []

  static func item(_ id: String) -> VideoFeedItem {
    VideoFeedItem(
      id: id, pid: 1, slug: id, projectURL: "https://example.com", title: id,
      creator: "Example", creatorImageURL: nil, statsText: "", badges: [],
      videoURL: nil, videoPreviewImageURL: nil, projectId: id, isSaved: false,
      sharesCount: 0, watchesCount: 3, percentFunded: 10
    )
  }

  func feed() async throws -> [VideoFeedItem] {
    self.feedCount += 1
    if !self.pauseFeed { return self.feedItems }
    return try await withCheckedThrowingContinuation { continuation in
      self.pendingFeeds.append(continuation)
      for (count, expectation) in self.feedWaits where count == self.feedCount { expectation.fulfill() }
    }
  }

  func setWatched(id: String, watched: Bool) async throws {
    self.watches.append((id, watched))
    if !self.pauseWatch { return }
    try await withCheckedThrowingContinuation { continuation in
      self.pendingWatches.append(continuation)
      for (count, expectation) in self.watchWaits where count == self.watches.count { expectation.fulfill() }
    }
  }

  func waitForFeeds(_ count: Int) async {
    if self.feedCount >= count { return }
    let expectation = XCTestExpectation(description: "Feed admission")
    self.feedWaits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func waitForWatches(_ count: Int) async {
    if self.watches.count >= count { return }
    let expectation = XCTestExpectation(description: "Watch admission")
    self.watchWaits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finishFeed(_ index: Int, items: [VideoFeedItem]) throws {
    guard self.pendingFeeds.indices.contains(index) else { XCTFail("Missing feed"); return }
    let continuation = try XCTUnwrap(self.pendingFeeds[index])
    self.pendingFeeds[index] = nil
    continuation.resume(returning: items)
  }

  func finishWatch(_ index: Int, failure: Bool = false) throws {
    guard self.pendingWatches.indices.contains(index) else { XCTFail("Missing watch"); return }
    let continuation = try XCTUnwrap(self.pendingWatches[index])
    self.pendingWatches[index] = nil
    if failure { continuation.resume(throwing: ErrorEnvelope.couldNotParseJSON) }
    else { continuation.resume() }
  }

  func finishAllWatches() {
    for index in self.pendingWatches.indices {
      let continuation = self.pendingWatches[index]
      self.pendingWatches[index] = nil
      continuation?.resume()
    }
  }

  var events: [Bool] = []
  private var pending: [CheckedContinuation<VoidEnvelope, Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []
  func report(project _: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope {
    self.events.append(completed)
    return try await withCheckedThrowingContinuation { continuation in
      self.pending.append(continuation)
      for (count, expectation) in self.waits where count == self.events.count { expectation.fulfill() }
    }
  }

  func waitForRequests(_ count: Int) async {
    if self.events.count >= count { return }
    let expectation = XCTestExpectation(description: "Media event admission")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int) throws {
    guard self.pending.indices.contains(index) else { XCTFail("Missing event"); return }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: VoidEnvelope())
  }

  func releaseAll() {
    for continuation in self.pendingFeeds { continuation?.resume(throwing: CancellationError()) }
    for continuation in self.pendingWatches { continuation?.resume(throwing: CancellationError()) }
    self.pendingFeeds.removeAll()
    self.pendingWatches.removeAll()
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}
