import Foundation
import Prelude
import ReactiveSwift
import XCTest

@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers

@MainActor
final class RewardsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private func feature(_ provider: ControlledRewardsProvider, move: Bool = false) -> RewardsFeature
  {
    RewardsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }
      ),
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
    let firstRoute = UUID()
    let secondRoute = UUID()
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

  private func shippingFeature(_ provider: ControlledShippingProvider) -> RewardsFeature {
    RewardsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }
      ), makeProvider: { provider }, sleep: { _ in try Task.checkCancellation() })
  }

  func testShippingSelectionPriorityAndExplicitChanges() async {
    let provider = ControlledShippingProvider()
    provider.locations = [.australia, .canada, .usa]
    let feature = self.shippingFeature(provider)
    let route = UUID()
    await withEnvironment(config: .template |> Config.lens.countryCode .~ "AU") {
      await feature.loadShippingLocations(
        route: route, projectID: 1, selectedLocationID: Location.canada.id,
        hasShippableRewards: true
      )
      XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .canada)
      await feature.loadShippingLocations(
        route: route, projectID: 1, selectedLocationID: -1, hasShippableRewards: true
      )
      XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .australia)
      feature.selectShippingLocation(.usa, route: route)
      XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .usa)
    }
    await withEnvironment(config: .template |> Config.lens.countryCode .~ "XX") {
      await feature.loadShippingLocations(
        route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
      )
      XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .usa)
      provider.locations = [.canada, .australia]
      await feature.loadShippingLocations(
        route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
      )
      XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .canada)
    }
  }

  func testDigitalRewardsDoNotFetchAndEmptyDestinationsAreSuccessfulNilSelection() async {
    let provider = ControlledShippingProvider()
    let feature = self.shippingFeature(provider)
    let route = UUID()
    await feature.loadShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: false
    )
    XCTAssertTrue(provider.projectIDs.isEmpty)
    XCTAssertNil(feature.shippingSnapshot(for: route).selectedLocation)
    XCTAssertNil(feature.shippingSnapshot(for: route).error)
    await feature.loadShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    XCTAssertEqual(provider.projectIDs, [1])
    XCTAssertTrue(feature.shippingSnapshot(for: route).locations.isEmpty)
    XCTAssertNil(feature.shippingSnapshot(for: route).error)
  }

  func testShippingFailureRetainsSelectionAndRetryRecovers() async {
    let provider = ControlledShippingProvider()
    provider.locations = [.usa, .canada]
    let feature = self.shippingFeature(provider)
    let route = UUID()
    await feature.loadShippingLocations(
      route: route, projectID: 1, selectedLocationID: Location.canada.id, hasShippableRewards: true
    )
    provider.fail = true
    await feature.loadShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    XCTAssertEqual(feature.shippingSnapshot(for: route).locations, [.usa, .canada])
    XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .canada)
    XCTAssertNotNil(feature.shippingSnapshot(for: route).error)
    XCTAssertFalse(feature.shippingSnapshot(for: route).isLoading)
    provider.fail = false
    await feature.loadShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    XCTAssertNil(feature.shippingSnapshot(for: route).error)
    XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .usa)
  }

  func testShippingDuplicatesShareAndChangedBackingRejectsLateResponse() async throws {
    let provider = ControlledShippingProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.shippingFeature(provider)
    let route = UUID()
    let first = feature.requestShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    let duplicate = feature.requestShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    await provider.waitForRequests(1)
    let replacement = feature.requestShippingLocations(
      route: route, projectID: 1, selectedLocationID: Location.canada.id, hasShippableRewards: true
    )
    await provider.waitForRequests(2)
    XCTAssertEqual(provider.projectIDs, [1, 1])
    XCTAssertTrue(first.isCancelled)
    try provider.finish(1, locations: [.usa, .canada])
    await replacement.value
    try provider.finish(0, locations: [.australia])
    await first.value
    await duplicate.value
    XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .canada)
    XCTAssertEqual(feature.shippingSnapshot(for: route).locations, [.usa, .canada])
  }

  func testShippingRouteReleaseCancelsOnlyItsReadAndRejectsLateResults() async throws {
    let provider = ControlledShippingProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.shippingFeature(provider)
    let firstRoute = UUID()
    let secondRoute = UUID()
    let first = feature.requestShippingLocations(
      route: firstRoute, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    let second = feature.requestShippingLocations(
      route: secondRoute, projectID: 2, selectedLocationID: nil, hasShippableRewards: true
    )
    await provider.waitForRequests(2)
    feature.releaseShippingLocations(route: firstRoute)
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
    try provider.finish(0, locations: [.australia])
    try provider.finish(1, locations: [.canada])
    await first.value
    await second.value
    XCTAssertTrue(feature.shippingSnapshot(for: firstRoute).locations.isEmpty)
    XCTAssertEqual(feature.shippingSnapshot(for: secondRoute).selectedLocation, .canada)
  }

  func testShippingAccountChangeRejectsOldCompletion() async throws {
    let provider = ControlledShippingProvider()
    provider.pause = true
    defer { provider.releaseAll() }
    let feature = self.shippingFeature(provider)
    let route = UUID()
    let first = feature.requestShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    await provider.waitForRequests(1)
    AppEnvironment.pushEnvironment(currentUser: User.template)
    defer { AppEnvironment.popEnvironment() }
    try provider.finish(0, locations: [.usa])
    await first.value
    XCTAssertTrue(feature.shippingSnapshot(for: route).locations.isEmpty)
    XCTAssertNil(feature.shippingSnapshot(for: route).error)
    let signedIn = feature.requestShippingLocations(
      route: route, projectID: 1, selectedLocationID: nil, hasShippableRewards: true
    )
    await provider.waitForRequests(2)
    try provider.finish(1, locations: [.canada])
    await signedIn.value
    XCTAssertEqual(feature.shippingSnapshot(for: route).selectedLocation, .canada)
  }

  func testCancelledShippingCallerDoesNotAdmitWork() async {
    let provider = ControlledShippingProvider()
    let feature = self.shippingFeature(provider)
    let task = Task {
      await feature.loadShippingLocations(
        route: UUID(), projectID: 1, selectedLocationID: nil, hasShippableRewards: true
      )
    }
    task.cancel()
    await task.value
    XCTAssertTrue(provider.projectIDs.isEmpty)
  }
}

@MainActor
private final class ControlledShippingProvider: RewardsProvider {
  func addOns(slug: String, locationID: String?) async throws -> [Reward]? {
    throw ErrorEnvelope.couldNotParseJSON
  }
  func fastAddOns(baseRewardID: Int, country: String) async throws -> [Reward] {
    throw ErrorEnvelope.couldNotParseJSON
  }
  var locations: [Location] = []
  var projectIDs: [Int] = []
  var fail = false
  var pause = false
  private var pending: [CheckedContinuation<[Location], Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []

  func rewards(
    projectID _: Int,
    country _: String?,
    inserter _: any NoRewardInserter
  ) async throws -> [Reward] {
    throw ErrorEnvelope.graphError("Unexpected rewards request")
  }

  func shippingLocations(projectID: Int) async throws -> [Location] {
    self.projectIDs.append(projectID)
    if self.pause {
      return try await withCheckedThrowingContinuation { continuation in
        self.pending.append(continuation)
        for (count, expectation) in self.waits where self.projectIDs.count == count {
          expectation.fulfill()
        }
      }
    }
    if self.fail { throw ErrorEnvelope.graphError("Shipping fixture failure") }
    return self.locations
  }

  func waitForRequests(_ count: Int) async {
    if self.projectIDs.count >= count { return }
    let expectation = XCTestExpectation(description: "Shipping request \(count)")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int, locations: [Location]) throws {
    guard self.pending.indices.contains(index) else {
      XCTFail("Missing request")
      return
    }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: locations)
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}

@MainActor
private final class ControlledRewardsProvider: RewardsProvider {
  func addOns(slug: String, locationID: String?) async throws -> [Reward]? {
    throw ErrorEnvelope.couldNotParseJSON
  }
  func fastAddOns(baseRewardID: Int, country: String) async throws -> [Reward] {
    throw ErrorEnvelope.couldNotParseJSON
  }
  func shippingLocations(projectID _: Int) async throws -> [Location] { [] }
  var rewards = [Reward.digitalReward]
  var countries: [String?] = []
  var fail = false
  var pause = false
  private var pending: [CheckedContinuation<[Reward], Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []

  func rewards(projectID _: Int, country: String?, inserter: any NoRewardInserter) async throws
    -> [Reward]
  {
    self.countries.append(country)
    if self.pause {
      return try await withCheckedThrowingContinuation { continuation in
        self.pending.append(continuation)
        for (count, expectation) in self.waits where self.countries.count == count {
          expectation.fulfill()
        }
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
    guard self.pending.indices.contains(index) else {
      XCTFail("Missing request")
      return
    }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: rewards)
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}

extension RewardsFeatureTests {
  func testDeferredAddOnsObservationCannotStartInReplacementSession() async {
    let fixture = AddOnsFixture()
    let result = fixture.result(UUID())
    fixture.session.sessionChanged()
    var interrupted = false
    let observation = result.startWithInterrupted { interrupted = true }
    defer { observation.dispose() }
    await fixture.feature.waitForAddOns()
    XCTAssertTrue(interrupted)
    XCTAssertEqual(fixture.provider.gate.count, 0)
  }

  func testCancelledAddOnsCallerDoesNotAdmitRequest() async {
    let fixture = AddOnsFixture()
    let task = Task {
      try await fixture.feature.addOns(
        route: UUID(), slug: "fixture",
        baseReward: fixture.reward, shippingRule: nil)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(fixture.provider.gate.count, 0)
  }

  func testAddOnCardsDoNotCombineOldRewardsWithNewProject() async throws {
    let fixture = AddOnsFixture()
    defer { fixture.provider.gate.releaseAll() }
    let vm = RewardAddOnSelectionViewModel(feature: fixture.feature)
    var cards: [RewardAddOnCardViewData] = []
    let subscription = vm.outputs.loadAddOnRewardsIntoDataSourceAndReloadTableView.observeValues {
      cards.append(contentsOf: $0.compactMap(\.rewardAddOnCardViewData))
    }
    defer { subscription?.dispose() }
    var project = Project.template
    let reward = Reward.digitalReward
      |> Reward.lens.hasAddOns .~ true
      |> Reward.lens.isAvailable .~ true
    func configuration() -> PledgeViewData {
      PledgeViewData(
        project: project, rewards: [reward], bonusSupport: nil,
        selectedShippingRule: nil, selectedQuantities: [reward.id: 1],
        selectedLocationId: nil, refTag: nil, context: .pledge)
    }
    vm.inputs.configure(with: configuration())
    vm.inputs.viewDidLoad()
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success([reward]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(cards.count, 1)
    project.id += 1
    project.slug = "replacement"
    vm.inputs.configure(with: configuration())
    await fixture.provider.gate.waitFor(2)
    XCTAssertEqual(
      cards.count, 1, "Changing configuration must not redraw old add-ons in the new project")
    try fixture.provider.gate.finish(1, .success([reward]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(cards.count, 2)
    XCTAssertEqual(cards.last?.project.id, project.id)
  }

  func testAddOnsSkipMissingNoRewardAndRewardsWithoutAddOns() async throws {
    let fixture = AddOnsFixture()
    for reward: Reward? in [nil, .noReward, Reward.template |> Reward.lens.hasAddOns .~ false] {
      let value = try await fixture.feature.addOns(
        route: UUID(), slug: "test", baseReward: reward, shippingRule: nil)
      XCTAssertNil(value)
    }
    XCTAssertEqual(fixture.provider.gate.count, 0)
  }

  func testAddOnsShareEquivalentPendingReadsAndRefreshAfterCompletion() async throws {
    let fixture = AddOnsFixture()
    defer { fixture.provider.gate.releaseAll() }
    let route = UUID()
    var values = 0
    let first = fixture.result(route).startWithResult {
      if case .success = $0 { values += 1 } else { XCTFail("Unexpected request error") }
    }
    let second = fixture.result(route).startWithResult {
      if case .success = $0 { values += 1 } else { XCTFail("Unexpected request error") }
    }
    defer {
      first.dispose()
      second.dispose()
    }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success([.template]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(values, 2)
    XCTAssertEqual(fixture.provider.gate.count, 1)
    let refresh = fixture.result(route).start()
    defer { refresh.dispose() }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success([]))
    await fixture.feature.waitForAddOns()
  }

  func testChangedAddOnLocationRejectsLateOldResponseAndOtherRouteSurvives() async throws {
    let fixture = AddOnsFixture()
    defer { fixture.provider.gate.releaseAll() }
    let route = UUID()
    var old = 0
    var new = 0
    var other = 0
    let first = fixture.result(route).startWithResult {
      if case .success = $0 { old += 1 } else { XCTFail("Unexpected request error") }
    }
    await fixture.provider.gate.waitFor(1)
    let second = fixture.result(route, shipping: .template).startWithResult {
      if case .success = $0 { new += 1 } else { XCTFail("Unexpected request error") }
    }
    let third = fixture.result(UUID()).startWithResult {
      if case .success = $0 { other += 1 } else { XCTFail("Unexpected request error") }
    }
    defer {
      first.dispose()
      second.dispose()
      third.dispose()
    }
    await fixture.provider.gate.waitFor(3)
    try fixture.provider.gate.finish(2, .success([.template]))
    try fixture.provider.gate.finish(1, .success([]))
    try fixture.provider.gate.finish(0, .success([.template]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(old, 0)
    XCTAssertEqual(new, 1)
    XCTAssertEqual(other, 1)
    XCTAssertEqual(fixture.provider.locations[1], ShippingRule.template.location.graphID)
  }

  func testReleasedAddOnsAndReplacedSameUserSessionSuppressLateResults() async throws {
    let fixture = AddOnsFixture()
    defer { fixture.provider.gate.releaseAll() }
    let route = UUID()
    var values = 0
    let first = fixture.result(route).startWithResult {
      if case .success = $0 { values += 1 } else { XCTFail("Unexpected request error") }
    }
    await fixture.provider.gate.waitFor(1)
    fixture.feature.releaseAddOns(route: route)
    try fixture.provider.gate.finish(0, .success([.template]))
    await fixture.feature.waitForAddOns()
    let second = fixture.result(route).startWithResult {
      if case .success = $0 { values += 1 } else { XCTFail("Unexpected request error") }
    }
    defer {
      first.dispose()
      second.dispose()
    }
    await fixture.provider.gate.waitFor(2)
    fixture.session.sessionChanged()
    try fixture.provider.gate.finish(1, .success([.template]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(values, 0)
  }

  func testAddOnsFailureDoesNotAutomaticallyRetryAndExplicitRetryRecovers() async throws {
    let fixture = AddOnsFixture()
    defer { fixture.provider.gate.releaseAll() }
    let route = UUID()
    var errors = 0
    var values = 0
    let first = fixture.result(route).startWithFailed { _ in errors += 1 }
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(errors, 1)
    XCTAssertEqual(fixture.provider.gate.count, 1)
    let retry = fixture.result(route).startWithResult {
      if case .success = $0 { values += 1 } else { XCTFail("Unexpected request error") }
    }
    defer {
      first.dispose()
      retry.dispose()
    }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success(nil))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(values, 1, "A successful nil response retains the bonus-only behavior")
  }

  func testFastAddOnsUseBaseRewardAndShippingCountryOrCountryFallback() async throws {
    let fixture = AddOnsFixture(fast: true)
    defer { fixture.provider.gate.releaseAll() }
    let first = fixture.result(UUID(), shipping: .template).start()
    await fixture.provider.gate.waitFor(1)
    try fixture.provider.gate.finish(0, .success([]))
    await fixture.feature.waitForAddOns()
    let second = fixture.result(UUID()).start()
    defer {
      first.dispose()
      second.dispose()
    }
    await fixture.provider.gate.waitFor(2)
    try fixture.provider.gate.finish(1, .success([]))
    await fixture.feature.waitForAddOns()
    XCTAssertEqual(fixture.provider.fastIDs, [fixture.reward.id, fixture.reward.id])
    XCTAssertEqual(
      fixture.provider.countries,
      [ShippingRule.template.location.country, AppEnvironment.current.countryCode])
    XCTAssertTrue(fixture.provider.slugs.isEmpty)
  }
}

@MainActor
private final class AddOnsFixture {
  let provider = ControlledAddOnsProvider()
  let session = SessionFeature(
    makeProvider: { AsyncSessionProvider(service: MockService()) }, currentUser: { .template })
  let reward = Reward.template |> Reward.lens.hasAddOns .~ true
  let fast: Bool
  init(fast: Bool = false) { self.fast = fast }
  lazy var feature = RewardsFeature(
    sessionFeature: self.session, makeProvider: { self.provider }, fastCheckout: { self.fast })
  func result(_ route: UUID, shipping: ShippingRule? = nil) -> SignalProducer<
    [Reward]?, ErrorEnvelope
  > {
    self.feature.addOnsResult(
      route: route, slug: "fixture", baseReward: self.reward, shippingRule: shipping)
  }
}

@MainActor
private final class ControlledAddOnsProvider: RewardsProvider {
  let gate = AccountRequestGate<[Reward]?>()
  var slugs: [String] = []
  var locations: [String?] = []
  var fastIDs: [Int] = []
  var countries: [String] = []
  func addOns(slug: String, locationID: String?) async throws -> [Reward]? {
    self.slugs.append(slug)
    self.locations.append(locationID)
    return try await self.gate.request()
  }
  func fastAddOns(baseRewardID: Int, country: String) async throws -> [Reward] {
    self.fastIDs.append(baseRewardID)
    self.countries.append(country)
    let value = try await self.gate.request()
    return try XCTUnwrap(value)
  }
  func shippingLocations(projectID: Int) async throws -> [Location] {
    throw ErrorEnvelope.couldNotParseJSON
  }
  func rewards(projectID: Int, country: String?, inserter: any NoRewardInserter) async throws
    -> [Reward]
  {
    throw ErrorEnvelope.couldNotParseJSON
  }
}
