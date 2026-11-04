@testable import Kickstarter_iOS
import Foundation
import Prelude
import ReactiveSwift
import XCTest
@testable import KsApi


@MainActor
final class FriendsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledFriendsProvider()
  private let session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) }, currentUser: { .template },
    updateUser: { _ in })
  private lazy var feature = FriendsFeature(
    sessionFeature: self.session, makeProvider: { self.provider }, sleep: { _ in })
  private let route = UUID()

  override func tearDown() async throws {
    self.feature.reset()
    self.provider.pages.releaseAll()
    self.provider.statisticsGate.releaseAll()
    self.provider.writes.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testEquivalentPageAndStatsReadsShareWhileRemainingIndependent() async throws {
    let page = self.feature.requestPage(route: self.route)
    let duplicate = self.feature.requestPage(route: self.route)
    let stats = self.feature.requestStatistics(route: self.route)
    let duplicateStats = self.feature.requestStatistics(route: self.route)
    await self.provider.pages.waitFor(1)
    await self.provider.statisticsGate.waitFor(1)
    try self.provider.statisticsGate.finish(0, .success(.template))
    await stats.value
    await duplicateStats.value
    XCTAssertNotNil(self.feature.snapshot(route: self.route).statistics)
    XCTAssertTrue(self.feature.snapshot(route: self.route).users.isEmpty)
    try self.provider.pages.finish(0, .success(Self.page([1, 2], cursor: "next")))
    await page?.value
    await duplicate?.value
    XCTAssertEqual(self.provider.pages.count, 1)
    XCTAssertEqual(self.provider.statisticsGate.count, 1)
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.map(\.id), [1, 2])
  }

  func testPaginationAppendsIncludingDuplicatesAndStopsAtTerminalPage() async throws {
    let first = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(Self.page([1, 2], cursor: "next")))
    await first?.value
    let next = self.feature.requestPage(route: self.route, next: true)
    let duplicate = self.feature.requestPage(route: self.route, next: true)
    await self.provider.pages.waitFor(2)
    XCTAssertEqual(self.provider.cursors, [nil, "next"])
    try self.provider.pages.finish(1, .success(Self.page([2, 3])))
    await next?.value
    await duplicate?.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.map(\.id), [1, 2, 2, 3])
    await self.feature.loadNextPage(route: self.route)
    XCTAssertEqual(self.provider.pages.count, 2)
  }

  func testPageFailurePreservesUsersAndCursorForExplicitRetry() async throws {
    let first = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(Self.page([1], cursor: "next")))
    await first?.value
    let next = self.feature.requestPage(route: self.route, next: true)
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await next?.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.map(\.id), [1])
    XCTAssertNotNil(self.feature.snapshot(route: self.route).pageError)
    let retry = self.feature.requestPage(route: self.route, next: true)
    await self.provider.pages.waitFor(3)
    XCTAssertEqual(self.provider.cursors, [nil, "next", "next"])
    try self.provider.pages.finish(2, .success(Self.page([] , cursor: "ignored")))
    await retry?.value
    XCTAssertNil(self.feature.snapshot(route: self.route).pageError)
    await self.feature.loadNextPage(route: self.route)
    XCTAssertEqual(self.provider.pages.count, 3)
  }

  func testStatisticsFailureDoesNotFailFriendsList() async throws {
    let page = self.feature.requestPage(route: self.route)
    let stats = self.feature.requestStatistics(route: self.route)
    await self.provider.pages.waitFor(1)
    await self.provider.statisticsGate.waitFor(1)
    try self.provider.pages.finish(0, .success(Self.page([1])))
    try self.provider.statisticsGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await page?.value
    await stats.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.count, 1)
    XCTAssertNil(self.feature.snapshot(route: self.route).pageError)
    XCTAssertNotNil(self.feature.snapshot(route: self.route).statisticsError)
  }

  func testRefreshRejectsLatePaginationEvenWhenProviderIgnoresCancellation() async throws {
    let first = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(Self.page([1], cursor: "next")))
    await first?.value
    let next = self.feature.requestPage(route: self.route, next: true)
    await self.provider.pages.waitFor(2)
    let refresh = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(3)
    try self.provider.pages.finish(2, .success(Self.page([3])))
    await refresh?.value
    try self.provider.pages.finish(1, .success(Self.page([2])))
    await next?.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.map(\.id), [3])
  }

  func testReleasedRouteCannotPublishIntoReplacement() async throws {
    let old = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    self.feature.release(route: self.route)
    let replacement = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(1, .success(Self.page([2])))
    await replacement?.value
    try self.provider.pages.finish(0, .success(Self.page([1])))
    await old?.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.map(\.id), [2])
  }

  func testSameUserNewSessionSuppressesPendingPagesAndStatistics() async throws {
    let page = self.feature.requestPage(route: self.route)
    let stats = self.feature.requestStatistics(route: self.route)
    await self.provider.pages.waitFor(1)
    await self.provider.statisticsGate.waitFor(1)
    self.session.sessionChanged()
    try self.provider.pages.finish(0, .success(Self.page([1])))
    try self.provider.statisticsGate.finish(0, .success(.template))
    await page?.value
    await stats.value
    XCTAssertTrue(self.feature.snapshot(route: self.route).users.isEmpty)
    XCTAssertNil(self.feature.snapshot(route: self.route).statistics)
  }

  func testEquivalentPendingWritesShareButOppositeWritesRunInOrder() async throws {
    let user = Self.user(9)
    let a = self.feature.startFollowing(user: user, following: true)
    let b = self.feature.startFollowing(user: user, following: true)
    let c = self.feature.startFollowing(user: user, following: false)
    await self.provider.writes.waitFor(1)
    XCTAssertEqual(self.provider.operations, ["9:true"])
    try self.provider.writes.finish(0, .success(()))
    await self.provider.writes.waitFor(2)
    XCTAssertEqual(self.provider.operations, ["9:true", "9:false"])
    try self.provider.writes.finish(1, .success(()))
    let first = try await a.value
    let duplicate = try await b.value
    let last = try await c.value
    XCTAssertEqual(first.isFriend, true)
    XCTAssertEqual(duplicate.isFriend, true)
    XCTAssertEqual(last.isFriend, false)
    XCTAssertEqual(self.feature.cached(user).isFriend, false)
  }

  func testCancelledObserverDoesNotCancelAdmittedWriteOrDuplicateRetry() async throws {
    let old = self.feature.startFollowing(user: Self.user(1), following: true)
    await self.provider.writes.waitFor(1)
    old.cancel()
    let next = self.feature.startFollowing(user: Self.user(1), following: true)
    try self.provider.writes.finish(0, .success(()))
    _ = try await next.value
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.operations, ["1:true"])
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, true)
  }

  func testFailedWriteDoesNotPoisonQueueOrCacheAndIsNotAutomaticallyRetried() async throws {
    let first = self.feature.startFollowing(user: Self.user(1), following: true)
    let next = self.feature.startFollowing(user: Self.user(2), following: true)
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(()))
    do { _ = try await first.value; XCTFail("Expected failed follow") } catch { }
    _ = try await next.value
    XCTAssertEqual(self.provider.operations, ["1:true", "2:true"])
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    XCTAssertEqual(self.feature.cached(Self.user(2)).isFriend, true)
  }

  func testNewSessionRejectsOldQueuedWriteAndOldCacheCommit() async throws {
    let first = self.feature.startFollowing(user: Self.user(1), following: true)
    let queued = self.feature.startFollowing(user: Self.user(2), following: true)
    await self.provider.writes.waitFor(1)
    self.session.sessionChanged()
    let current = self.feature.startFollowing(user: Self.user(3), following: true)
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(()))
    try self.provider.writes.finish(0, .success(()))
    _ = await first.result
    _ = await queued.result
    _ = try await current.value
    XCTAssertEqual(self.provider.operations, ["1:true", "3:true"])
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    XCTAssertEqual(self.feature.cached(Self.user(3)).isFriend, true)
  }

  func testFollowAllIsOrderedAndInvalidatesOldPageBeforeRefresh() async throws {
    let page = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    let follow = self.feature.startFollowing(user: Self.user(1), following: true)
    let completed = expectation(description: "Follow all settled")
    let all = self.feature.followAllResult().startWithCompleted { completed.fulfill() }
    defer { follow.cancel(); all.dispose() }
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .success(()))
    await self.provider.writes.waitFor(2)
    XCTAssertEqual(self.provider.operations, ["1:true", "all"])
    try self.provider.writes.finish(1, .success(()))
    // Await the command lane without waiting on the deliberately suspended old page.
    await fulfillment(of: [completed], timeout: 2)
    try self.provider.pages.finish(0, .success(Self.page([1], cursor: "next")))
    await page?.value
    await self.feature.waitForOperations()
    XCTAssertTrue(self.feature.snapshot(route: self.route).users.isEmpty)
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    await self.feature.loadNextPage(route: self.route)
    XCTAssertEqual(self.provider.pages.count, 1)
  }

  func testNewReadWaitsForAdmittedWriteAndUsesSharedFollowState() async throws {
    let follow = self.feature.startFollowing(user: Self.user(1), following: true)
    defer { follow.cancel() }
    let page = self.feature.requestPage(route: self.route)
    await self.provider.writes.waitFor(1)
    XCTAssertEqual(self.provider.pages.count, 0)
    try self.provider.writes.finish(0, .success(()))
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success(Self.page([1])))
    await page?.value
    XCTAssertEqual(self.feature.snapshot(route: self.route).users.first?.isFriend, true)
  }

  func testReusedFindFriendsCellIgnoresPreviousFriendCompletion() async throws {
    let vm = FindFriendsFriendFollowCellViewModel(feature: self.feature, delay: {})
    vm.configureWith(friend: Self.user(1))
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    vm.configureWith(friend: Self.user(2))
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    await vm.waitForObservations()
    XCTAssertEqual(vm.hideFollowButton, false)
    vm.configureWith(friend: Self.user(1))
    XCTAssertEqual(vm.hideFollowButton, true)
  }

  func testActivityAndFindFriendsShareFollowingStateWithoutSharingCellLifetime() async throws {
    let vm = ActivityFriendFollowCellViewModel(feature: self.feature, delay: {})
    var activity = Activity.template
    activity = activity |> Activity.lens.user .~ Self.user(1)
    vm.configureWith(activity: activity)
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    activity = activity |> Activity.lens.user .~ Self.user(2)
    vm.configureWith(activity: activity)
    var hidden: [Bool] = []
    vm.onChange = { [weak vm] in if let value = vm?.hideFollowButton { hidden.append(value) } }
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    await vm.waitForObservation()
    XCTAssertTrue(hidden.isEmpty)
    let other = FindFriendsFriendFollowCellViewModel(feature: self.feature, delay: {})
    other.configureWith(friend: Self.user(1))
    XCTAssertEqual(other.hideFollowButton, true)
  }

  func testDelayedSuccessDoesNotReachReplacementSession() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let vm = FindFriendsFriendFollowCellViewModel(feature: self.feature, delay: { try await gate.request() })
    vm.configureWith(friend: Self.user(1))
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .success(()))
    await gate.waitFor(1)
    self.session.sessionChanged()
    try gate.finish(0, .success(()))
    await vm.waitForObservations()
    XCTAssertEqual(vm.hideFollowButton, false)
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
  }

  func testFollowAllDelayedRefreshCannotStartInReplacementSession() async throws {
    var currentUser = User.template
    currentUser.facebookConnected = true
    await withEnvironment(currentUser: currentUser) {
      do {
      let vm = FindFriendsViewModel(feature: self.feature)
      vm.configureWith(source: .findFriends)
      vm.viewDidLoad()
      await self.provider.pages.waitFor(1)
      await self.provider.statisticsGate.waitFor(1)
      try self.provider.pages.finish(0, .success(Self.page([1])))
      try self.provider.statisticsGate.finish(0, .success(.template))
      await self.feature.waitForOperations()
      vm.confirmFollowAllFriends()
      await self.provider.writes.waitFor(1)
      try self.provider.writes.finish(0, .success(()))
      await self.feature.waitForOperations()
      self.provider.immediatePage = Self.page([2])
      self.session.sessionChanged()
      await self.scheduler.advance(by: .seconds(2))
      await self.feature.waitForOperations()
      XCTAssertEqual(self.provider.cursors.count, 1)
      } catch { XCTFail("Unexpected fixture failure: \(error)") }
    }
  }

  func testNativeCommandsReturnOnlyAfterConfirmedState() async throws {
    let command = Task { try await self.feature.setFollowing(user: Self.user(1), following: true) }
    await self.provider.writes.waitFor(1)
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    try self.provider.writes.finish(0, .success(()))
    let user = try await command.value
    XCTAssertEqual(user.isFriend, true)
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, true)
    let all = Task { try await self.feature.followAll() }
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(()))
    try await all.value
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
  }

  private static func user(_ id: Int) -> User {
    var user = User.template
    user.id = id
    user.isFriend = false
    return user
  }
  private static func page(_ ids: [Int], cursor: String? = nil) -> FindFriendsEnvelope {
    FindFriendsEnvelope(contactsImported: true, urls: .init(api: .init(moreUsers: cursor)),
                        users: ids.map(Self.user))
  }
}

@MainActor
private final class ControlledFriendsProvider: FriendsProvider {
  let pages = AccountRequestGate<FindFriendsEnvelope>()
  let statisticsGate = AccountRequestGate<FriendStatsEnvelope>()
  let writes = AccountRequestGate<Void>()
  var immediatePage: FindFriendsEnvelope?
  var cursors: [String?] = []
  var operations: [String] = []
  func page(cursor: String?) async throws -> FindFriendsEnvelope {
    self.cursors.append(cursor)
    if let immediatePage { return immediatePage }
    return try await self.pages.request()
  }
  func statistics() async throws -> FriendStatsEnvelope { try await self.statisticsGate.request() }
  func setFollowing(userID: Int, following: Bool) async throws {
    self.operations.append("\(userID):\(following)")
    try await self.writes.request()
  }
  func followAll() async throws {
    self.operations.append("all")
    try await self.writes.request()
  }
}
