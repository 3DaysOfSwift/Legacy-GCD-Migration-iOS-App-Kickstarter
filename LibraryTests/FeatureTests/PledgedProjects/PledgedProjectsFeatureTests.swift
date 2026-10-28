import Combine
import Foundation
import GraphAPI
import XCTest

@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers

@MainActor
final class PledgedProjectsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let provider = ControlledPledgedProjectsProvider()
  private let session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) }, currentUser: { .template },
    updateUser: { _ in })
  private lazy var feature = PledgedProjectsFeature(
    sessionFeature: self.session, makeProvider: { self.provider }, tiers: { [.tier1PaymentFailed] })
  private let route = UUID()
  private var snapshots: [PledgedProjectsFeature.Snapshot] = []
  private var subscription: AnyCancellable?
  private func observe() {
    self.subscription = self.feature.snapshots(route: self.route).sink { [weak self] in
      self?.snapshots.append($0)
    }
  }
  override func tearDown() async throws {
    self.feature.reset()
    self.provider.gate.releaseAll()
    await self.feature.waitForOperations()
    self.subscription = nil
    try await super.tearDown()
  }
  func testEquivalentFirstPageSharesPendingRequest() async throws {
    self.observe()
    let first = self.feature.requestFirstPage(route: self.route)
    let second = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    try self.provider.gate.finish(0, .success(try .fakeOverview()))
    await first.value
    await second.value
    XCTAssertEqual(self.provider.inputs.count, 1)
    XCTAssertNil(self.provider.inputs[0].cursor)
    XCTAssertEqual(self.provider.inputs[0].limit, 10)
    XCTAssertEqual(self.snapshots.count, 3)
    XCTAssertEqual(self.snapshots.last?.values.count, 3)
    XCTAssertEqual(self.snapshots.last?.page, 1)
  }
  func testPaginationAppendsThenTerminalLoadMoreReturnsWithoutRequest() async throws {
    self.observe()
    let first = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    try self.provider.gate.finish(0, .success(try .fakeOverview(1...3, more: true)))
    await first.value
    let next = Task { await self.feature.loadMore(route: self.route) }
    await self.provider.gate.waitFor(2)
    XCTAssertEqual(self.provider.inputs[1].cursor, "3")
    try self.provider.gate.finish(1, .success(try .fakeOverview(4...5)))
    await next.value
    XCTAssertEqual(self.snapshots.last?.values.map(\.projectId), [1, 2, 3, 4, 5])
    XCTAssertEqual(self.snapshots.last?.page, 2)
    await self.feature.loadMore(route: self.route)
    XCTAssertEqual(self.provider.inputs.count, 2)
  }
  func testRefreshRejectsLatePaginationCompletion() async throws {
    self.observe()
    let first = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    try self.provider.gate.finish(0, .success(try .fakeOverview(1...3, more: true)))
    await first.value
    let next = Task { await self.feature.loadMore(route: self.route) }
    await self.provider.gate.waitFor(2)
    let refresh = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(3)
    try self.provider.gate.finish(2, .success(try .fakeOverview(9...9)))
    await refresh.value
    try self.provider.gate.finish(1, .success(try .fakeOverview(4...5)))
    await next.value
    XCTAssertEqual(self.snapshots.last?.values.map(\.projectId), [9])
    XCTAssertEqual(self.snapshots.last?.page, 1)
  }
  func testReleaseRejectsLateNonCooperativeResponse() async throws {
    self.observe()
    let task = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    self.feature.release(route: self.route)
    try self.provider.gate.finish(0, .success(try .fakeOverview()))
    await task.value
    XCTAssertEqual(self.snapshots.count, 2)
    XCTAssertFalse(self.snapshots.contains { $0.hasLoaded })
  }
  func testAccountReplacementClearsCardsAndRejectsOldResponse() async throws {
    self.observe()
    let old = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    self.session.sessionChanged()
    self.feature.reset()
    let new = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(2)
    try self.provider.gate.finish(1, .success(try .fakeOverview(9...9)))
    await new.value
    try self.provider.gate.finish(0, .success(try .fakeOverview()))
    await old.value
    XCTAssertEqual(self.snapshots.last?.values.map(\.projectId), [9])
  }
  func testFailureDoesNotRetryAndExplicitRefreshRecovers() async throws {
    self.observe()
    let first = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(1)
    try self.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await first.value
    XCTAssertNotNil(self.snapshots.last?.error)
    XCTAssertEqual(self.provider.inputs.count, 1)
    let retry = self.feature.requestFirstPage(route: self.route)
    await self.provider.gate.waitFor(2)
    try self.provider.gate.finish(1, .success(try .fakeOverview(nil)))
    await retry.value
    XCTAssertEqual(self.snapshots.last, .empty)
  }
  func testRoutesDoNotCancelEachOther() async throws {
    self.observe()
    let first = self.feature.requestFirstPage(route: self.route)
    let second = self.feature.requestFirstPage(route: UUID())
    await self.provider.gate.waitFor(2)
    try self.provider.gate.finish(0, .success(try .fakeOverview()))
    try self.provider.gate.finish(1, .success(try .fakeOverview(nil)))
    await first.value
    await second.value
    XCTAssertEqual(self.snapshots.last?.values.count, 3)
  }
}

@MainActor
private final class ControlledPledgedProjectsProvider: PledgedProjectsProvider {
  let gate = AccountRequestGate<GraphAPI.FetchPledgedProjectsQuery.Data>()
  var inputs: [(tiers: [PledgeProjectsOverviewSort], cursor: String?, limit: Int)] = []
  func page(tiers: [PledgeProjectsOverviewSort], cursor: String?, limit: Int) async throws
    -> GraphAPI.FetchPledgedProjectsQuery.Data
  {
    self.inputs.append((tiers, cursor, limit))
    return try await self.gate.request()
  }
}
extension GraphAPI.FetchPledgedProjectsQuery.Data {
  fileprivate static func fakeOverview(_ range: ClosedRange<Int>? = 1...3, more: Bool = false)
    throws -> Self
  {
    try GraphAPI.FetchPledgedProjectsQuery.fakeData(cursors: range, hasNextPage: more)
  }
}
