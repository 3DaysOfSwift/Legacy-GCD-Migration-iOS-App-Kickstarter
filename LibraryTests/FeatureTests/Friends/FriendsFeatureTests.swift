import Foundation
import Prelude
import ReactiveSwift
import XCTest
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

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
    var values: [Bool] = []
    let a = self.feature.setFollowingResult(user: user, following: true).startWithResult { result in
      switch result {
      case .success(let user): values.append(user.isFriend == true)
      case .failure: XCTFail("Expected successful follow command")
      }
    }
    let b = self.feature.setFollowingResult(user: user, following: true).startWithResult { result in
      switch result {
      case .success(let user): values.append(user.isFriend == true)
      case .failure: XCTFail("Expected successful follow command")
      }
    }
    let c = self.feature.setFollowingResult(user: user, following: false).startWithResult { result in
      switch result {
      case .success(let user): values.append(user.isFriend == true)
      case .failure: XCTFail("Expected successful follow command")
      }
    }
    defer { a.dispose(); b.dispose(); c.dispose() }
    await self.provider.writes.waitFor(1)
    XCTAssertEqual(self.provider.operations, ["9:true"])
    try self.provider.writes.finish(0, .success(()))
    await self.provider.writes.waitFor(2)
    XCTAssertEqual(self.provider.operations, ["9:true", "9:false"])
    try self.provider.writes.finish(1, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(values.filter { $0 }.count, 2)
    XCTAssertEqual(values.last, false)
    XCTAssertEqual(self.feature.cached(user).isFriend, false)
  }

  func testDisposedObserverDoesNotCancelAdmittedWriteOrDuplicateRetry() async throws {
    var values = 0
    let old = self.feature.setFollowingResult(user: Self.user(1), following: true)
      .startWithResult { result in
        switch result {
        case .success: values += 1
        case .failure: XCTFail("Expected successful follow command")
        }
      }
    await self.provider.writes.waitFor(1)
    old.dispose()
    let next = self.feature.setFollowingResult(user: Self.user(1), following: true)
      .startWithResult { result in
        switch result {
        case .success: values += 1
        case .failure: XCTFail("Expected successful follow command")
        }
      }
    defer { next.dispose() }
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.operations, ["1:true"])
    XCTAssertEqual(values, 1)
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, true)
  }

  func testFailedWriteDoesNotPoisonQueueOrCacheAndIsNotAutomaticallyRetried() async throws {
    var errors = 0
    let first = self.feature.setFollowingResult(user: Self.user(1), following: true)
      .startWithFailed { _ in errors += 1 }
    let next = self.feature.setFollowingResult(user: Self.user(2), following: true).start()
    defer { first.dispose(); next.dispose() }
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(self.provider.operations, ["1:true", "2:true"])
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    XCTAssertEqual(self.feature.cached(Self.user(2)).isFriend, true)
  }

  func testNewSessionRejectsOldQueuedWriteAndOldCacheCommit() async throws {
    let first = self.feature.setFollowingResult(user: Self.user(1), following: true).start()
    let queued = self.feature.setFollowingResult(user: Self.user(2), following: true).start()
    defer { first.dispose(); queued.dispose() }
    await self.provider.writes.waitFor(1)
    self.session.sessionChanged()
    let current = self.feature.setFollowingResult(user: Self.user(3), following: true).start()
    defer { current.dispose() }
    await self.provider.writes.waitFor(2)
    try self.provider.writes.finish(1, .success(()))
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.operations, ["1:true", "3:true"])
    XCTAssertEqual(self.feature.cached(Self.user(1)).isFriend, false)
    XCTAssertEqual(self.feature.cached(Self.user(3)).isFriend, true)
  }

  func testDeferredProducerCannotBeAdmittedIntoNewSession() async {
    let deferred = self.feature.setFollowingResult(user: Self.user(1), following: true)
    self.session.sessionChanged()
    let subscription = deferred.start()
    defer { subscription.dispose() }
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.operations, [])
  }

  func testFollowAllIsOrderedAndInvalidatesOldPageBeforeRefresh() async throws {
    let page = self.feature.requestPage(route: self.route)
    await self.provider.pages.waitFor(1)
    let follow = self.feature.setFollowingResult(user: Self.user(1), following: true).start()
    let completed = expectation(description: "Follow all settled")
    let all = self.feature.followAllResult().startWithCompleted { completed.fulfill() }
    defer { follow.dispose(); all.dispose() }
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
    let follow = self.feature.setFollowingResult(user: Self.user(1), following: true).start()
    defer { follow.dispose() }
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
    let vm = FindFriendsFriendFollowCellViewModel(feature: self.feature)
    var hidden: [Bool] = []
    let subscription = vm.outputs.hideFollowButton.observeValues { hidden.append($0) }
    defer { subscription?.dispose() }
    vm.configureWith(friend: Self.user(1))
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    vm.configureWith(friend: Self.user(2))
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertEqual(hidden, [false])
    vm.configureWith(friend: Self.user(1))
    XCTAssertEqual(hidden, [false, true])
  }

  func testActivityAndFindFriendsShareFollowingStateWithoutSharingCellLifetime() async throws {
    let vm = ActivityFriendFollowCellViewModel(feature: self.feature)
    var activity = Activity.template
    activity = activity |> Activity.lens.user .~ Self.user(1)
    vm.configureWith(activity: activity)
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    activity = activity |> Activity.lens.user .~ Self.user(2)
    vm.configureWith(activity: activity)
    var hidden: [Bool] = []
    let subscription = vm.hideFollowButton.observeValues { hidden.append($0) }
    defer { subscription?.dispose() }
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    await self.scheduler.advance()
    XCTAssertTrue(hidden.isEmpty)
    let other = FindFriendsFriendFollowCellViewModel(feature: self.feature)
    var otherHidden: [Bool] = []
    let otherSubscription = other.hideFollowButton.observeValues { otherHidden.append($0) }
    defer { otherSubscription?.dispose() }
    other.configureWith(friend: Self.user(1))
    XCTAssertEqual(otherHidden, [true])
  }

  func testDelayedSuccessDoesNotReachReplacementSession() async throws {
    let vm = FindFriendsFriendFollowCellViewModel(feature: self.feature)
    var hidden: [Bool] = []
    let subscription = vm.hideFollowButton.observeValues { hidden.append($0) }
    defer { subscription?.dispose() }
    vm.configureWith(friend: Self.user(1))
    vm.followButtonTapped()
    await self.provider.writes.waitFor(1)
    try self.provider.writes.finish(0, .success(()))
    await self.feature.waitForOperations()
    self.session.sessionChanged()
    await self.scheduler.advance()
    XCTAssertEqual(hidden, [false])
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
