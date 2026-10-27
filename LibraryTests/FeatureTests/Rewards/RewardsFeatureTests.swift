import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import XCTest

@MainActor
final class RewardsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private func feature(_ provider: ControlledRewardsProvider, move: Bool = false) -> RewardsFeature {
    RewardsFeature(
      makeProvider: { provider },
      moveNoReward: { move },
      sleep: { _ in try Task.checkCancellation() }
    )
  }

  func testPreservesOrderAndShippingRulesAndFiltersFutureRewards() async {
    let provider = ControlledRewardsProvider()
    let future = Reward.template |> Reward.lens.startsAt .~ Date.distantFuture.timeIntervalSince1970
    provider.rewards = [Reward.shipsToUSAReward, future, Reward.digitalReward]
    let feature = self.feature(provider)
    let route = UUID()
    await feature.load(route: route, project: .template, location: .usa)
    XCTAssertEqual(provider.countries, ["US"])
    XCTAssertEqual(
      feature.snapshot(for: route).rewards.map(\.id),
      [Reward.noReward.id, Reward.shipsToUSAReward.id, Reward.digitalReward.id]
    )
    XCTAssertEqual(
      feature.snapshot(for: route).rewards[1].shippingRulesExpanded,
      Reward.shipsToUSAReward.shippingRulesExpanded
    )
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
    XCTAssertNil(feature.snapshot(for: route).error)
  }

  func testNoRewardPlacementFollowsExperimentAndShippingEligibility() async {
    let provider = ControlledRewardsProvider()
    provider.rewards = [Reward.shipsToUSAReward, Reward.digitalReward]
    let feature = self.feature(provider, move: true)
    let route = UUID()
    await feature.load(route: route, project: .template, location: .australia)
    XCTAssertEqual(
      feature.snapshot(for: route).rewards.map(\.id),
      [Reward.noReward.id, Reward.shipsToUSAReward.id, Reward.digitalReward.id]
    )
    provider.rewards = [Reward.digitalReward]
    await feature.load(route: route, project: .template, location: nil)
    XCTAssertEqual(
      feature.snapshot(for: route).rewards.map(\.id),
      [Reward.digitalReward.id, Reward.noReward.id]
    )
  }

  func testEquivalentCallsShareOneRequestAndChangedCountryRejectsLateCompletion() async throws {
    let provider = ControlledRewardsProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let first = feature.requestLoad(route: route, project: .template, location: .usa)
    let duplicate = feature.requestLoad(route: route, project: .template, location: .usa)
    await provider.waitForRequests(1)
    XCTAssertEqual(provider.countries, ["US"])
    let second = feature.requestLoad(route: route, project: .template, location: .australia)
    await provider.waitForRequests(2)
    XCTAssertTrue(first.isCancelled)
    try provider.finish(1, rewards: [Reward.digitalReward])
    await second.value
    try provider.finish(0, rewards: [Reward.shipsToUSAReward])
    await first.value
    await duplicate.value
    XCTAssertEqual(feature.snapshot(for: route).rewards.map(\.id), [Reward.digitalReward.id])
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
  }

  func testFailureKeepsLastSuccessfulDataAndRetryClearsError() async {
    let provider = ControlledRewardsProvider()
    let feature = self.feature(provider)
    let route = UUID()
    await feature.load(route: route, project: .template, location: nil)
    let cached = feature.snapshot(for: route).rewards
    provider.fail = true
    await feature.load(route: route, project: .template, location: .usa)
    XCTAssertEqual(feature.snapshot(for: route).rewards, cached)
    XCTAssertNotNil(feature.snapshot(for: route).error)
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
    provider.fail = false
    await feature.load(route: route, project: .template, location: .usa)
    XCTAssertNil(feature.snapshot(for: route).error)
  }

  func testIndependentRoutesAndCancellationDoNotPublishOrCancelAnotherScreen() async throws {
    let provider = ControlledRewardsProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let firstRoute = UUID(), secondRoute = UUID()
    let first = feature.requestLoad(route: firstRoute, project: .template, location: nil)
    let second = feature.requestLoad(route: secondRoute, project: .template, location: nil)
    await provider.waitForRequests(2)
    feature.release(route: firstRoute)
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
    try provider.finish(0, rewards: [Reward.shipsToUSAReward])
    try provider.finish(1, rewards: [Reward.digitalReward])
    await first.value
    await second.value
    XCTAssertTrue(feature.snapshot(for: firstRoute).rewards.isEmpty)
    XCTAssertEqual(feature.snapshot(for: secondRoute).rewards, [Reward.digitalReward])
  }

  func testAccountChangeRejectsOldResultAndNewAccountCannotJoinIt() async throws {
    let provider = ControlledRewardsProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let first = feature.requestLoad(route: route, project: .template, location: nil)
    await provider.waitForRequests(1)
    AppEnvironment.pushEnvironment(currentUser: User.template)
    defer { AppEnvironment.popEnvironment() }
    do {
      try provider.finish(0, rewards: [Reward.shipsToUSAReward])
      await first.value
      XCTAssertTrue(feature.snapshot(for: route).rewards.isEmpty)
      let signedIn = feature.requestLoad(route: route, project: .template, location: nil)
      await provider.waitForRequests(2)
      try provider.finish(1, rewards: [Reward.digitalReward])
      await signedIn.value
      XCTAssertEqual(feature.snapshot(for: route).rewards, [Reward.digitalReward])
    }
  }

  func testCancelledCallerDoesNotStartWork() async {
    let provider = ControlledRewardsProvider()
    let feature = self.feature(provider)
    let task = Task { await feature.load(route: UUID(), project: .template, location: nil) }
    task.cancel()
    await task.value
    XCTAssertTrue(provider.countries.isEmpty)
  }
}

@MainActor
private final class ControlledRewardsProvider: RewardsProvider {
  var rewards = [Reward.digitalReward]
  var countries: [String?] = []
  var fail = false
  var pause = false
  private var pending: [CheckedContinuation<[Reward], Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []

  func rewards(projectID _: Int, country: String?, inserter: any NoRewardInserter) async throws -> [Reward] {
    self.countries.append(country)
    if self.pause {
      return try await withCheckedThrowingContinuation { continuation in
        self.pending.append(continuation)
        for (count, expectation) in self.waits where self.countries.count == count { expectation.fulfill() }
      }
    }
    if self.fail { throw ErrorEnvelope.graphError("fixture failure") }
    return inserter.insert(noReward: .noReward, intoRewards: self.rewards)
  }

  func waitForRequests(_ count: Int) async {
    if self.countries.count >= count { return }
    let expectation = XCTestExpectation(description: "Rewards request \(count)")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int, rewards: [Reward]) throws {
    guard self.pending.indices.contains(index) else { XCTFail("Missing request"); return }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: rewards)
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}
