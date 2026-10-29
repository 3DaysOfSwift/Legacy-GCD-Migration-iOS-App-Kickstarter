import AVFoundation
import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Observation
import Prelude
import ReactiveSwift
import XCTest
import UIKit

@MainActor
final class ProjectMediaFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private func pageModel(media: ProjectMediaFeature) -> ProjectPageViewModel {
    let service = MockService()
    let discussion = DiscussionFeature(
      sessionFeature: media.sessionFeature,
      makeProvider: { AsyncDiscussionProvider(service: service) }
    )
    let details = ProjectDetailsFeature(
      sessionFeature: media.sessionFeature,
      discussionFeature: discussion,
      makeProvider: { AsyncProjectDetailsProvider(service: service) },
      useFastLoading: { false },
      includeRichText: { true }
    )
    return ProjectPageViewModel(projectDetailsFeature: details, projectMediaFeature: media)
  }

  func testCampaignImageSharesPendingReadAndFailureAllowsRetry() async throws {
    let gate = AccountRequestGate<UIImage>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(loadImage: { _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let route = UUID(), url = URL(fileURLWithPath: "/tmp/campaign-image")
    let first = feature.requestImage(route: route, url: url)
    let shared = feature.requestImage(route: route, url: url)
    await gate.waitFor(1)
    try gate.finish(0, .failure(URLError(.cannotDecodeContentData)))
    for request in [first, shared] {
      if case .success = await request.result { XCTFail("Image error was swallowed") }
    }
    let retry = feature.requestImage(route: route, url: url)
    await gate.waitFor(2)
    let image = UIImage()
    try gate.finish(1, .success(image))
    let result = try await retry.value
    XCTAssertTrue(result === image)
    XCTAssertEqual(gate.count, 2)
  }

  func testPageCancellationDoesNotCancelOtherPagesImage() async throws {
    let gate = AccountRequestGate<UIImage>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(loadImage: { _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let route = UUID(), url = URL(fileURLWithPath: "/tmp/campaign-image")
    let old = feature.requestImage(route: route, url: url)
    await gate.waitFor(1)
    let independent = feature.requestImage(route: UUID(), url: url)
    await gate.waitFor(2)
    feature.cancelImages(route: route)
    let replacement = feature.requestImage(route: route, url: url)
    await gate.waitFor(3)
    let image = UIImage()
    try gate.finish(0, .success(image)) // Deliberately noncooperative late completion.
    if case .failure(is CancellationError) = await old.result {} else { XCTFail("Cancelled image escaped") }
    try gate.finish(1, .success(image)); try gate.finish(2, .success(image))
    let a = try await independent.value, b = try await replacement.value
    XCTAssertTrue(a === image); XCTAssertTrue(b === image)
  }

  func testCampaignImageReplacementAndExitRejectObsoleteDelivery() async throws {
    let gate = AccountRequestGate<UIImage>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(loadImage: { _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let model = self.pageModel(media: feature)
    let first = model.prepareImage(slot: "row", url: URL(fileURLWithPath: "/tmp/old")) { _ in XCTFail("Old row received image") }
    await gate.waitFor(1)
    var received = 0
    let second = model.prepareImage(slot: "row", url: URL(fileURLWithPath: "/tmp/new")) { _ in received += 1 }
    await gate.waitFor(2)
    try gate.finish(1, .success(UIImage())); await second.value
    try gate.finish(0, .success(UIImage())); await first.value
    XCTAssertEqual(received, 1)
    let exit = model.prepareImage(slot: "another", url: URL(fileURLWithPath: "/tmp/late")) { _ in XCTFail("Exited page received image") }
    await gate.waitFor(3)
    model.cancelImagePreparation()
    try gate.finish(2, .success(UIImage())); await exit.value
  }

  func testProjectReplacementAndReleaseCancelImageDelivery() async throws {
    let gate = AccountRequestGate<UIImage>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(loadImage: { _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    var model: ProjectPageViewModel? = self.pageModel(media: feature)
    let request = try XCTUnwrap(model).prepareImage(slot: "row", url: URL(fileURLWithPath: "/tmp/old")) { _ in XCTFail("Old project image escaped") }
    await gate.waitFor(1)
    model?.configureWith(projectOrParam: .left(.template), refInfo: nil)
    try gate.finish(0, .success(UIImage())); await request.value
    let releasedRequest = try XCTUnwrap(model).prepareImage(slot: "row", url: URL(fileURLWithPath: "/tmp/new")) { _ in XCTFail("Released view model received image") }
    await gate.waitFor(2)
    weak var released = model
    model = nil
    XCTAssertNil(released)
    try gate.finish(1, .success(UIImage())); await releasedRequest.value
  }

  func testPreparationSharesSlotAndFailureAllowsRetry() async throws {
    let gate = AccountRequestGate<PreparedProjectMedia>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(preparePlayback: { _, _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let route = UUID(), url = URL(fileURLWithPath: "/tmp/synthetic-video")
    let first = feature.requestPreparation(route: route, slot: "row", url: url, thumbnail: nil)
    let shared = feature.requestPreparation(route: route, slot: "row", url: url, thumbnail: nil)
    await gate.waitFor(1)
    try gate.finish(0, .failure(URLError(.cannotDecodeContentData)))
    for request in [first, shared] {
      if case .success = await request.result { XCTFail("Preparation error was swallowed") }
    }
    let retry = feature.requestPreparation(route: route, slot: "row", url: url, thumbnail: nil)
    await gate.waitFor(2)
    let player = AVPlayer()
    try gate.finish(1, .success(PreparedProjectMedia(player: player)))
    let prepared = try await retry.value
    XCTAssertTrue(prepared.player === player)
    XCTAssertEqual(gate.count, 2)
  }

  func testChangedMediaRejectsOldSlotAndOtherPageRemainsIndependent() async throws {
    let gate = AccountRequestGate<PreparedProjectMedia>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(preparePlayback: { _, _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let route = UUID(), other = UUID(), url = URL(fileURLWithPath: "/tmp/synthetic-video")
    let old = feature.requestPreparation(route: route, slot: "row", url: url, thumbnail: nil)
    await gate.waitFor(1)
    let current = feature.requestPreparation(route: route, slot: "row", url: url, thumbnail: url)
    await gate.waitFor(2)
    let independent = feature.requestPreparation(route: other, slot: "row", url: url, thumbnail: nil)
    await gate.waitFor(3)
    feature.cancelPreparations(route: route)
    for index in 0...2 { try gate.finish(index, .success(PreparedProjectMedia(player: AVPlayer()))) }
    for request in [old, current] {
      if case .failure(is CancellationError) = await request.result {} else { XCTFail("Obsolete page received media") }
    }
    _ = try await independent.value
  }

  func testPageExitSuppressesLatePreparationDelivery() async throws {
    let gate = AccountRequestGate<PreparedProjectMedia>()
    defer { gate.releaseAll() }
    let feature = ProjectMediaFeature(preparePlayback: { _, _ in try await gate.request() }, makeProvider: { ControlledMediaProvider() })
    let model = self.pageModel(media: feature)
    let waiter = model.prepareMedia(slot: "row", url: URL(fileURLWithPath: "/tmp/synthetic-video"), thumbnail: nil) { _ in
      XCTFail("Exited page received prepared media")
    }
    await gate.waitFor(1)
    model.cancelMediaPreparation()
    try gate.finish(0, .success(PreparedProjectMedia(player: AVPlayer())))
    await waiter.value
  }

  func testReadinessObservationCancelsWhileItemRemainsUnknown() async {
    let item = AVPlayerItem(asset: AVMutableComposition())
    let request = Task { try await ProjectMediaPreparation.waitUntilReady(item) }
    await Task.yield()
    request.cancel()
    if case .failure(is CancellationError) = await request.result {} else { XCTFail("Readiness did not cancel") }
  }

  func testNativePreparationRejectsMissingLocalAsset() async {
    do {
      _ = try await ProjectMediaPreparation.load(url: URL(fileURLWithPath: "/tmp/" + UUID().uuidString + ".mp4"), thumbnailURL: nil)
      XCTFail("Missing media must fail")
    } catch { XCTAssertFalse(error is CancellationError) }
  }

  func testNativePreparationLoadsLocalAudioWithoutThumbnail() async throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: url) }
    // Uncompressed mono PCM, 100ms at 44.1kHz. No encoder or live service needed.
    var bytes = Data()
    func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
    func uint16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
    func uint32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
    let length: UInt32 = 4410 * 2
    text("RIFF"); uint32(36 + length); text("WAVEfmt "); uint32(16)
    uint16(1); uint16(1); uint32(44100); uint32(88200); uint16(2); uint16(16)
    text("data"); uint32(length); bytes.append(Data(repeating: 0, count: Int(length)))
    try bytes.write(to: url)
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 0.1, accuracy: 0.01)
    let finished = expectation(description: "Local asset readiness")
    var result: Result<PreparedProjectMedia, Error>?
    let task = Task {
      do { result = .success(try await ProjectMediaPreparation.load(url: url, thumbnailURL: nil)) }
      catch { result = .failure(error) }
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 5)
    task.cancel()
    await task.value
    let media = try XCTUnwrap(result).get()
    XCTAssertEqual(media.player.currentItem?.status, .readyToPlay)
    XCTAssertNil(media.thumbnail)
  }

  func testOrdinaryAndVideoSavesShareTheMutationQueueAndCache() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let project = Project.template
    provider.feedItems = [ControlledMediaProvider.item(project.graphID)]
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    await feature.loadFeed(route: route)
    let intent = feature.prepareWatch(projectID: project.graphID, watched: true, previous: false)
    var received = 0
    let observation = feature.watchResult(project: project, intent: intent).startWithValues { _ in received += 1 }
    defer { observation.dispose() }
    await provider.waitForWatches(1)
    let duplicate = feature.toggleSaved(route: route, projectID: project.graphID)
    XCTAssertEqual(provider.watches.count, 1)
    let unsave = feature.toggleSaved(route: route, projectID: project.graphID)
    try provider.finishWatch(0)
    await provider.waitForWatches(2)
    XCTAssertEqual(provider.watches.map(\.watched), [true, false])
    try provider.finishWatch(1)
    await duplicate?.value
    await unsave?.value
    await feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertEqual(received, 0, "Newer video intent supersedes the older button response")
    XCTAssertEqual(feature.cached(project).personalization.isStarred, false)
    XCTAssertFalse(feature.feedState(route: route).items[0].isSaved)
  }

  func testDisposedSaveObservationStillSettlesAdmittedWrite() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let project = Project.template
    let intent = feature.prepareWatch(projectID: project.graphID, watched: true, previous: false)
    var received = false
    let observation = feature.watchResult(project: project, intent: intent).startWithValues { _ in received = true }
    await provider.waitForWatches(1)
    observation.dispose()
    try provider.finishWatch(0)
    await feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertFalse(received)
    XCTAssertEqual(feature.cached(project).personalization.isStarred, true)
  }

  func testNewerSaveIntentCannotBeRolledBackByEarlierFailure() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let project = Project.template
    let first = feature.prepareWatch(projectID: project.graphID, watched: true, previous: false)
    let request = feature.submitWatch(first)
    await provider.waitForWatches(1)
    let second = feature.prepareWatch(projectID: project.graphID, watched: false, previous: true)
    let next = feature.submitWatch(second)
    try provider.finishWatch(0, failure: true)
    _ = await request.result
    await provider.waitForWatches(2)
    XCTAssertEqual(feature.cached(project).personalization.isStarred, false)
    try provider.finishWatch(1)
    _ = try await next.value
  }

  func testSameUserSessionReplacementRejectsSaveCompletion() async throws {
    let provider = ControlledMediaProvider()
    provider.pauseWatch = true
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let project = Project.template
    let intent = feature.prepareWatch(projectID: project.graphID, watched: true, previous: false)
    let task = feature.submitWatch(intent)
    await provider.waitForWatches(1)
    feature.sessionFeature.sessionChanged()
    try provider.finishWatch(0)
    do { _ = try await task.value; XCTFail("Old session must not commit") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertFalse(feature.cached(project).personalization.isStarred ?? false)
  }

  func testReusedCellDiscardsDebouncedRequestAndItsOptimisticCache() async {
    let provider = ControlledMediaProvider()
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let vm = WatchProjectViewModel(feature: feature)
    await withEnvironment(currentUser: .template) {
      let original = Project.template
      var replacement = original
      replacement.id += 1
      vm.configure(with: (original, .project, nil))
      vm.viewDidLoad()
      vm.saveButtonTapped(selected: false)
      XCTAssertEqual(feature.cached(original).personalization.isStarred, true)
      vm.configure(with: (replacement, .project, nil))
      await self.scheduler.advance(by: .seconds(1))
      await feature.waitForOperations()
      XCTAssertTrue(provider.watches.isEmpty)
      XCTAssertEqual(feature.cached(original).personalization.isStarred, false)
    }
  }

  func testCancellingOldPreparationDoesNotRevertNewerIntent() {
    let provider = ControlledMediaProvider()
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let project = Project.template
    let old = feature.prepareWatch(projectID: project.graphID, watched: true, previous: false)
    _ = feature.prepareWatch(projectID: project.graphID, watched: false, previous: true)
    feature.cancelPreparedWatch(old)
    XCTAssertEqual(feature.cached(project).personalization.isStarred, false)
  }

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

  func setWatched(id: String, watched: Bool) async throws -> WatchProjectResponseEnvelope {
    self.watches.append((id, watched))
    if !self.pauseWatch { return watched ? .watchTemplate : .unwatchTemplate }
    try await withCheckedThrowingContinuation { continuation in
      self.pendingWatches.append(continuation)
      for (count, expectation) in self.watchWaits where count == self.watches.count { expectation.fulfill() }
    }
    return watched ? .watchTemplate : .unwatchTemplate
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
