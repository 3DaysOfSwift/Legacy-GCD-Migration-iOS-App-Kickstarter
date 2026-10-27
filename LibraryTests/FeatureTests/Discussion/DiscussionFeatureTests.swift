import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveSwift
import XCTest

@MainActor
final class DiscussionFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testAccountSwitchDuringRetryDelayDoesNotSubmitUnderNewAccount() async {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    await withEnvironment(currentUser: .template) {
      let subscription = feature.retryCommentProducer(
        erroredComment: Comment.template.updatingStatus(to: .failed),
        commentableId: "project", parentId: nil
      ).start()
      defer { subscription.dispose() }
      await withEnvironment(currentUser: nil) {
        await self.scheduler.advance(by: .seconds(1))
        await feature.waitForMutations()
        XCTAssertTrue(provider.postInputs.isEmpty)
      }
    }
  }

  func testAccountSwitchDuringPostStatusDelaySuppressesOldPresentation() async {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    var values: [Comment] = []
    await withEnvironment(currentUser: .template) {
      let subscription = feature.postCommentProducer(
        project: .template, commentableId: "project", parentId: nil, user: .template, body: "old"
      ).startWithValues { values.append($0.0) }
      defer { subscription.dispose() }
      await feature.waitForMutations()
      await withEnvironment(currentUser: nil) {
        await self.scheduler.advance(by: .seconds(1))
        XCTAssertEqual(values.count, 1, "No confirmed old-session value delivered after the status delay")
      }
    }
  }

  func testCancelledWaiterDoesNotCancelSharedPost() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let original = feature.requestPost(
      operationID: "shared",
      body: "text",
      commentableID: "project",
      parentID: nil
    )
    await provider.waitForPosts(1)
    let entered = expectation(description: "Second caller entered")
    let waiter = Task {
      entered.fulfill()
      return try await feature.post(
        operationID: "shared",
        body: "text",
        commentableID: "project",
        parentID: nil
      )
    }
    defer { waiter.cancel() }
    await fulfillment(of: [entered], timeout: 2)
    waiter.cancel()
    provider.finishAllPosts()
    _ = try await original.value
    if case .failure(is CancellationError) = await waiter.result {}
    else { XCTFail("Cancelled waiter returned success") }
    XCTAssertEqual(provider.postInputs.count, 1)
  }

  private func feature(_ provider: ControlledDiscussionProvider) -> DiscussionFeature {
    DiscussionFeature(makeProvider: { provider }, sleep: { _ in try Task.checkCancellation() })
  }

  func testEquivalentPostsShareButDistinctAttemptsAndChangedBodiesDoNot() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let first = feature.requestPost(
      operationID: "attempt",
      body: "first",
      commentableID: "project",
      parentID: nil
    )
    let duplicate = feature.requestPost(
      operationID: "attempt",
      body: "first",
      commentableID: "project",
      parentID: nil
    )
    let changed = feature.requestPost(
      operationID: "attempt",
      body: "changed",
      commentableID: "project",
      parentID: nil
    )
    let intentionalRepeat = feature.requestPost(
      operationID: "another",
      body: "first",
      commentableID: "project",
      parentID: "root"
    )
    await provider.waitForPosts(3)
    XCTAssertEqual(provider.postInputs.map(\.body).sorted(), ["changed", "first", "first"])
    XCTAssertEqual(provider.postInputs.compactMap(\.parentId), ["root"])
    provider.finishAllPosts()
    let original = try await first.value
    let shared = try await duplicate.value
    _ = try await changed.value
    _ = try await intentionalRepeat.value
    XCTAssertEqual(original, shared)
    XCTAssertEqual(provider.postInputs.count, 3)
  }

  func testSixthPostQueuesWithoutLosingDistinctCommandsAndFailureReleasesSlot() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let tasks = (0..<6).map {
      feature.requestPost(operationID: "\($0)", body: "\($0)", commentableID: "project", parentID: nil)
    }
    await provider.waitForPosts(5)
    XCTAssertEqual(provider.postInputs.count, 5)
    try provider.finishPost(0, result: .failure(ErrorEnvelope.couldNotParseJSON))
    await provider.waitForPosts(6)
    XCTAssertEqual(provider.postInputs.last?.body, "5")
    provider.finishAllPosts()
    for task in tasks { _ = await task.result }
    XCTAssertEqual(Set(provider.postInputs.map(\.body)).count, 6)
  }

  func testFailedPostCanBeExplicitlyRetriedAndIsNeverAutomaticallyRetried() async throws {
    let provider = ControlledDiscussionProvider()
    provider.fail = true
    let feature = self.feature(provider)
    let failed = feature.requestPost(
      operationID: "retry",
      body: "kept text",
      commentableID: "update",
      parentID: "root"
    )
    if case .success = await failed.result { XCTFail("Expected failed write") }
    XCTAssertEqual(provider.postInputs.count, 1)
    provider.fail = false
    let comment = try await feature.post(
      operationID: "retry",
      body: "kept text",
      commentableID: "update",
      parentID: "root"
    )
    XCTAssertEqual(comment, .template)
    XCTAssertEqual(provider.postInputs.map(\.body), ["kept text", "kept text"])
    XCTAssertEqual(provider.postInputs.map(\.commentableId), ["update", "update"])
  }

  func testDisposingPresentationAndReleasingReadRouteDoNotCancelAdmittedPost() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    var values: [Comment] = []
    let subscription = feature.postCommentProducer(
      project: .template, commentableId: "project", parentId: nil, user: .template, body: "durable"
    ).startWithValues { values.append($0.0) }
    await provider.waitForPosts(1)
    subscription.dispose()
    feature.release(route: UUID())
    try provider.finishPost(0, result: .success(.template))
    await feature.waitForMutations()
    XCTAssertEqual(values.count, 1, "Only the immediate optimistic value reaches a disposed screen")
    XCTAssertEqual(provider.postInputs.count, 1)
  }

  func testAccountChangeRejectsPostCompletionAndQueuedWritesBeforeDispatch() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    await withEnvironment(currentUser: .template) {
      let tasks = (0..<6).map {
        feature.requestPost(operationID: "\($0)", body: "\($0)", commentableID: "project", parentID: nil)
      }
      await provider.waitForPosts(5)
      await withEnvironment(currentUser: nil) {
        provider.finishAllPosts()
        for task in tasks {
          switch await task.result {
          case .failure(is CancellationError): break
          default: XCTFail("Old-session writes cannot report success")
          }
        }
        XCTAssertEqual(provider.postInputs.count, 5, "Queued old-session post never reaches the transport")
      }
    }
  }

  func testBlockDuplicatesShareAndOtherTargetsRemainIndependent() async throws {
    let provider = ControlledDiscussionProvider()
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let first = feature.requestBlockUser(id: "one")
    let duplicate = feature.requestBlockUser(id: "one")
    let other = feature.requestBlockUser(id: "two")
    await provider.waitForBlocks(2)
    XCTAssertEqual(Set(provider.blockIDs), ["one", "two"])
    provider.finishAllBlocks()
    _ = try await first.value
    _ = try await duplicate.value
    _ = try await other.value
    XCTAssertEqual(provider.blockIDs.count, 2)
  }

  func testBlockFailureClearsOwnershipForRetryAndAccountChangeSuppressesDelivery() async throws {
    let provider = ControlledDiscussionProvider()
    let feature = self.feature(provider)
    provider.fail = true
    if case .success = await feature.requestBlockUser(id: "target").result { XCTFail("Expected error") }
    provider.fail = false
    _ = try await feature.blockUser(id: "target")
    XCTAssertEqual(provider.blockIDs, ["target", "target"])
    provider.pauseWrites = true
    defer { provider.releaseAll() }
    await withEnvironment(currentUser: .template) {
      let task = feature.requestBlockUser(id: "late")
      await provider.waitForBlocks(3)
      await withEnvironment(currentUser: nil) {
        provider.finishAllBlocks()
        if case .failure(is CancellationError) = await task.result {} else { XCTFail("Stale block success") }
      }
    }
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
  var pauseWrites = false
  var postInputs: [PostCommentInput] = []
  var blockIDs: [String] = []
  private var pendingPosts: [CheckedContinuation<Comment, Error>?] = []
  private var pendingBlocks: [CheckedContinuation<EmptyResponseEnvelope, Error>?] = []
  private var postWaits: [(Int, XCTestExpectation)] = []
  private var blockWaits: [(Int, XCTestExpectation)] = []

  func post(input: PostCommentInput) async throws -> Comment {
    self.postInputs.append(input)
    if self.pauseWrites {
      return try await withCheckedThrowingContinuation { continuation in
        self.pendingPosts.append(continuation)
        for (count, expectation) in self.postWaits
          where count == self.postInputs.count { expectation.fulfill() }
      }
    }
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return .template
  }

  func block(id: String) async throws -> EmptyResponseEnvelope {
    self.blockIDs.append(id)
    if self.pauseWrites {
      return try await withCheckedThrowingContinuation { continuation in
        self.pendingBlocks.append(continuation)
        for (count, expectation) in self.blockWaits
          where count == self.blockIDs.count { expectation.fulfill() }
      }
    }
    if self.fail { throw ErrorEnvelope.couldNotParseJSON }
    return EmptyResponseEnvelope()
  }

  func waitForPosts(_ count: Int) async {
    if self.postInputs.count >= count { return }
    let expectation = XCTestExpectation(description: "Comment mutation admission")
    self.postWaits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func waitForBlocks(_ count: Int) async {
    if self.blockIDs.count >= count { return }
    let expectation = XCTestExpectation(description: "Block mutation admission")
    self.blockWaits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finishPost(_ index: Int, result: Result<Comment, Error>) throws {
    guard self.pendingPosts.indices.contains(index) else { XCTFail("Missing post"); return }
    let continuation = try XCTUnwrap(self.pendingPosts[index])
    self.pendingPosts[index] = nil
    continuation.resume(with: result)
  }

  func finishAllPosts() {
    for index in self.pendingPosts.indices {
      let continuation = self.pendingPosts[index]
      self.pendingPosts[index] = nil
      continuation?.resume(returning: .template)
    }
  }

  func finishAllBlocks() {
    for index in self.pendingBlocks.indices {
      let continuation = self.pendingBlocks[index]
      self.pendingBlocks[index] = nil
      continuation?.resume(returning: EmptyResponseEnvelope())
    }
  }

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
    for continuation in self.pendingPosts { continuation?.resume(throwing: CancellationError()) }
    for continuation in self.pendingBlocks { continuation?.resume(throwing: CancellationError()) }
    self.pendingPosts.removeAll()
    self.pendingBlocks.removeAll()
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    for continuation in self.pendingUpdates { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
    self.pendingUpdates.removeAll()
  }
}
