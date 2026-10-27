import Foundation
import ReactiveSwift
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import XCTest

@MainActor
final class DiscussionFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private func feature(_ provider: ControlledDiscussionProvider) -> DiscussionFeature {
    DiscussionFeature(makeProvider: { provider }, sleep: { _ in try Task.checkCancellation() })
  }

  func testProjectPaginationUsesReturnedCursorAndStopsAfterEmptyPage() async {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    let route = UUID()
    provider.envelope.cursor = "next"
    await feature.loadFirstPage(route: route, source: .project("original"))
    await feature.loadNextPage(route: route)
    XCTAssertEqual(provider.requests.count, 2)
    XCTAssertEqual(provider.requests[0].slug, "original")
    XCTAssertNil(provider.requests[0].cursor)
    XCTAssertEqual(provider.requests[1].slug, provider.envelope.slug)
    XCTAssertEqual(provider.requests[1].cursor, "next")
    provider.envelope.comments = []
    await feature.loadNextPage(route: route)
    await feature.loadNextPage(route: route)
    XCTAssertEqual(provider.requests.count, 3)
    XCTAssertTrue(feature.snapshot(for: route).comments.isEmpty)
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
  }

  func testUpdatePaginationUsesEnvelopeUpdateIdentity() async {
    let provider = ControlledDiscussionProvider()
    provider.envelope.slug = nil
    provider.envelope.updateID = "encoded-update"
    provider.envelope.cursor = "older"
    let feature = self.feature(provider)
    let route = UUID()
    await feature.loadFirstPage(route: route, source: .update("42"))
    await feature.loadNextPage(route: route)
    XCTAssertEqual(provider.requests.map(\.updateID), ["42", "encoded-update"])
    XCTAssertEqual(provider.requests.map(\.cursor), [nil, "older"])
    XCTAssertTrue(provider.requests.allSatisfy { $0.slug == nil })
  }

  func testRepliesPreserveBackwardCursorAndTotalCount() async {
    let provider = ControlledDiscussionProvider()
    provider.replyEnvelope.cursor = "previous"
    let feature = self.feature(provider)
    let route = UUID()
    await feature.loadFirstPage(route: route, source: .replies("root"))
    await feature.loadNextPage(route: route)
    XCTAssertEqual(provider.replyIDs, ["root", provider.replyEnvelope.comment.id])
    XCTAssertEqual(provider.replyCursors, [nil, "previous"])
    XCTAssertEqual(feature.snapshot(for: route).totalCount, provider.replyEnvelope.totalCount)
    XCTAssertEqual(feature.snapshot(for: route).comments, provider.replyEnvelope.replies)
  }

  func testEquivalentReadsShareAndRefreshRejectsLatePageWithoutCancellingOtherRoute() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID(), otherRoute = UUID()
    let first = feature.requestFirstPage(route: route, source: .project("old"))
    let duplicate = feature.requestFirstPage(route: route, source: .project("old"))
    await provider.waitForRequests(1)
    let independent = feature.requestFirstPage(route: otherRoute, source: .project("other"))
    await provider.waitForRequests(2)
    let fresh = feature.requestFirstPage(route: route, source: .project("new"), refresh: true)
    await provider.waitForRequests(3)
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(independent.isCancelled)
    try provider.finish(2, envelope: .multipleCommentTemplate)
    await fresh.value
    try provider.finish(0, envelope: .singleCommentTemplate)
    await first.value
    await duplicate.value
    try provider.finish(1, envelope: .singleCommentTemplate)
    await independent.value
    XCTAssertEqual(feature.snapshot(for: route).comments, CommentsEnvelope.multipleCommentTemplate.comments)
    XCTAssertEqual(
      feature.snapshot(for: otherRoute).comments,
      CommentsEnvelope.singleCommentTemplate.comments
    )
  }

  func testNextPageFailureKeepsCursorAndDataAndRetryRecovers() async {
    let provider = ControlledDiscussionProvider()
    provider.envelope.cursor = "retry-cursor"
    let feature = self.feature(provider)
    let route = UUID()
    await feature.loadFirstPage(route: route, source: .project("test"))
    let previous = feature.snapshot(for: route).comments
    provider.fail = true
    await feature.loadNextPage(route: route)
    XCTAssertNotNil(feature.snapshot(for: route).error)
    XCTAssertEqual(feature.snapshot(for: route).comments, previous)
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
    provider.fail = false
    await feature.loadNextPage(route: route)
    XCTAssertEqual(provider.requests.map(\.cursor), [nil, "retry-cursor", "retry-cursor"])
    XCTAssertNil(feature.snapshot(for: route).error)
  }

  func testAccountChangeRejectsLatePageAndOldCursor() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let pending = feature.requestFirstPage(route: route, source: .project("test"))
    await provider.waitForRequests(1)
    AppEnvironment.pushEnvironment(currentUser: .template)
    defer { AppEnvironment.popEnvironment() }
    try provider.finish(0, envelope: .singleCommentTemplate)
    await pending.value
    XCTAssertTrue(feature.snapshot(for: route).comments.isEmpty)
    XCTAssertNil(feature.snapshot(for: route).error)
    XCTAssertNil(feature.requestNextPage(route: route))
    provider.pause = false
    await feature.loadFirstPage(route: route, source: .project("test"))
    XCTAssertEqual(provider.requests.count, 2)
  }

  func testMissingEnvelopeDoesNotInventEmptyPageOrVisibleError() async {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    let route = UUID()
    await feature.loadFirstPage(route: route, source: .project("test"))
    let previous = feature.snapshot(for: route).comments
    provider.missingEnvelope = true
    var pages = 0
    let observation = feature.pageValues.observeValues { _ in pages += 1 }
    defer { observation?.dispose() }
    await feature.loadNextPage(route: route)
    XCTAssertEqual(pages, 0)
    XCTAssertEqual(feature.snapshot(for: route).comments, previous)
    XCTAssertNil(feature.snapshot(for: route).error)
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
  }

  func testReleaseCancelsReadAndPreCancelledCommandDoesNotAdmit() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let pending = feature.requestFirstPage(route: route, source: .project("test"))
    await provider.waitForRequests(1)
    feature.release(route: route)
    XCTAssertTrue(pending.isCancelled)
    try provider.finish(0, envelope: .singleCommentTemplate)
    await pending.value
    let cancelled = Task { await feature.loadFirstPage(route: route, source: .project("test")) }
    cancelled.cancel()
    await cancelled.value
    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertTrue(feature.snapshot(for: route).comments.isEmpty)
  }

  func testUpdateNavigationSharesThenSupersedesAndSilentlyRejectsObsoleteResponse() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseUpdates = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    var updates: [Int] = []
    let observation = feature.updateValues.observeValues { updates.append($0.1.id) }
    defer { observation?.dispose() }
    let first = feature.requestUpdate(route: route, id: 1, project: .id(9))
    let duplicate = feature.requestUpdate(route: route, id: 1, project: .id(9))
    await provider.waitForUpdates(1)
    let second = feature.requestUpdate(route: route, id: 2, project: .id(9))
    await provider.waitForUpdates(2)
    try provider.finishUpdate(1, id: 2)
    await second.value
    try provider.finishUpdate(0, id: 1)
    await first.value
    await duplicate.value
    XCTAssertEqual(updates, [2])
    XCTAssertEqual(provider.updateIDs, [1, 2])
  }

  func testContextAndUpdateRoutesAreIndependentAndFailuresStaySilent() async {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    var projects: [Project] = [], updates: [Int] = []
    let p = feature.projectValues.observeValues { projects.append($0.1) }
    let u = feature.updateValues.observeValues { updates.append($0.1.id) }
    defer { p?.dispose(); u?.dispose() }
    let route = UUID()
    await feature.loadProject(route: route, param: .id(9))
    await feature.loadUpdate(route: route, id: 7, project: .id(9))
    provider.fail = true
    await feature.loadProject(route: route, param: .id(10))
    await feature.loadUpdate(route: route, id: 8, project: .id(9))
    XCTAssertEqual(projects.count, 1)
    XCTAssertEqual(updates, [7])
  }
}

@MainActor
private final class ControlledDiscussionProvider: DiscussionProvider {
  struct Request { let slug: String?; let updateID: String?; let cursor: String? }
  var envelope = CommentsEnvelope.singleCommentTemplate
  var replyEnvelope = CommentRepliesEnvelope.singleReplyTemplate
  var requests: [Request] = []
  var replyIDs: [String] = []
  var replyCursors: [String?] = []
  var updateIDs: [Int] = []
  var fail = false
  var missingEnvelope = false
  var pause = false
  var pauseUpdates = false
  private var pending: [CheckedContinuation<CommentsEnvelope, Error>?] = []
  private var pendingUpdates: [CheckedContinuation<Update, Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []
  private var updateWaits: [(Int, XCTestExpectation)] = []

  func comments(slug: String?, updateID: String?, cursor: String?) async throws -> CommentsEnvelope {
    self.requests.append(Request(slug: slug, updateID: updateID, cursor: cursor))
    if self.missingEnvelope { throw DiscussionResponseError.missingEnvelope }
    if self.pause {
      return try await withCheckedThrowingContinuation { continuation in
        self.pending.append(continuation)
        for (count, expectation) in self.waits where count == self.requests.count { expectation.fulfill() }
      }
    }
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return self.envelope
  }

  func replies(id: String, cursor: String?) async throws -> CommentRepliesEnvelope {
    self.replyIDs.append(id)
    self.replyCursors.append(cursor)
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return self.replyEnvelope
  }

  func project(param _: Param) async throws -> Project {
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return .template
  }

  func update(id: Int, project _: Param) async throws -> Update {
    self.updateIDs.append(id)
    if self.pauseUpdates {
      return try await withCheckedThrowingContinuation { continuation in
        self.pendingUpdates.append(continuation)
        for (count, expectation) in self.updateWaits
          where count == self.updateIDs.count { expectation.fulfill() }
      }
    }
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return Update.template |> Update.lens.id .~ id
  }

  func waitForRequests(_ count: Int) async {
    if self.requests.count >= count { return }
    let expectation = XCTestExpectation(description: "Discussion page admission")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func waitForUpdates(_ count: Int) async {
    if self.updateIDs.count >= count { return }
    let expectation = XCTestExpectation(description: "Update admission")
    self.updateWaits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int, envelope: CommentsEnvelope) throws {
    guard self.pending.indices.contains(index) else { XCTFail("Missing page"); return }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: envelope)
  }

  func finishUpdate(_ index: Int, id: Int) throws {
    guard self.pendingUpdates.indices.contains(index) else { XCTFail("Missing update"); return }
    let continuation = try XCTUnwrap(self.pendingUpdates[index])
    self.pendingUpdates[index] = nil
    continuation.resume(returning: Update.template |> Update.lens.id .~ id)
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    for continuation in self.pendingUpdates { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
    self.pendingUpdates.removeAll()
  }
}
