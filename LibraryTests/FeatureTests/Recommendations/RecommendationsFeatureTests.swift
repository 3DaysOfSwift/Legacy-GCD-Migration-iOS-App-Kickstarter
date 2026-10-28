@testable import KsApi
@testable import Library
import Prelude
import ReactiveSwift
import XCTest

@MainActor
final class RecommendationsFeatureTests: XCTestCase {
  private var provider: ControlledRecommendationsProvider!
  private var feature: RecommendationsFeature!
  private var values: [(UUID, RecommendationsFeature.Selection)] = []
  private var observation: Disposable?

  override func setUp() async throws {
    try await super.setUp()
    let provider = ControlledRecommendationsProvider()
    self.provider = provider
    let settings = SettingsFeature(
      sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
      makeProvider: { AsyncAccountPreferencesProvider(service: MockService()) }
    )
    self.feature = RecommendationsFeature(settingsFeature: settings, makeProvider: { provider }, sleep: { _ in })
    self.observation = self.feature.selections.observeValues { [weak self] in self?.values.append($0) }
  }

  override func tearDown() async throws {
    self.feature.reset()
    self.provider.categories.releaseAll()
    self.provider.pages.releaseAll()
    await self.feature.waitForOperations()
    self.observation?.dispose()
    try await super.tearDown()
  }

  private func project(_ id: Int) -> Project { .template |> Project.lens.id .~ id }

  func testCuratedCategoriesRunConcurrentlyPreserveDuplicatesAndBudget() async throws {
    let task = self.feature.request(.curated([.art, .tabletopGames]), route: UUID())
    await self.provider.pages.waitFor(2)
    XCTAssertEqual(self.provider.parameters.map(\.perPage), [15, 15])
    XCTAssertEqual(Set(self.provider.parameters.compactMap { $0.category?.id }), Set([Category.art.id, Category.tabletopGames.id]))
    XCTAssertTrue(self.provider.parameters.allSatisfy { $0.state == .live })
    try self.provider.pages.finish(1, .success([self.project(1)]))
    try self.provider.pages.finish(0, .success([self.project(1)]))
    await task.value
    XCTAssertEqual(self.values.first?.1.projects.map(\.id), [1, 1])
  }

  func testCuratedPartialFailureRetainsSuccessfulCategory() async throws {
    let task = self.feature.request(.curated([.art, .tabletopGames]), route: UUID())
    await self.provider.pages.waitFor(2)
    try self.provider.pages.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try self.provider.pages.finish(1, .success([self.project(2)]))
    await task.value
    XCTAssertEqual(self.values.first?.1.projects.map(\.id), [2])
  }

  func testEquivalentPendingInputSharesRequest() async throws {
    let route = UUID()
    let first = self.feature.request(.curated([.art]), route: route)
    let second = self.feature.request(.curated([.art]), route: route)
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success([]))
    await first.value
    await second.value
    XCTAssertEqual(self.provider.pages.count, 1)
    XCTAssertEqual(self.values.count, 1)
    XCTAssertTrue(try XCTUnwrap(self.values.first).1.projects.isEmpty)
  }

  func testClearingCategoriesSuppressesLateSuccess() async throws {
    let route = UUID()
    let first = self.feature.request(.curated([.art]), route: route)
    await self.provider.pages.waitFor(1)
    await self.feature.load(.curated([]), route: route)
    try self.provider.pages.finish(0, .success([self.project(1)]))
    await first.value
    XCTAssertTrue(self.values.isEmpty)
  }

  func testSeparateScreensDoNotCancelEachOther() async throws {
    let firstRoute = UUID()
    let secondRoute = UUID()
    let first = self.feature.request(.curated([.art]), route: firstRoute)
    await self.provider.pages.waitFor(1)
    let second = self.feature.request(.curated([.tabletopGames]), route: secondRoute)
    await self.provider.pages.waitFor(2)
    self.feature.release(route: firstRoute)
    try self.provider.pages.finish(0, .success([self.project(1)]))
    try self.provider.pages.finish(1, .success([self.project(2)]))
    await first.value
    await second.value
    XCTAssertEqual(self.values.map { $0.0 }, [secondRoute])
  }

  func testRecommendationsStopAfterThreeUniqueAlternatives() async throws {
    let task = self.feature.request(.afterBacking(self.project(1)), route: UUID())
    await self.provider.categories.waitFor(1)
    try self.provider.categories.finish(0, .success(.art))
    await self.provider.pages.waitFor(1)
    XCTAssertEqual(self.provider.parameters.first, RecommendationsFeature.recommendedParameters)
    try self.provider.pages.finish(0, .success([self.project(1), self.project(2), self.project(2), self.project(3), self.project(4)]))
    await task.value
    XCTAssertEqual(self.provider.pages.count, 1)
    XCTAssertEqual(Set(try XCTUnwrap(self.values.first).1.projects.map(\.id)), Set([2, 3, 4]))
    XCTAssertEqual(self.values.first?.1.category, .art)
  }

  func testFallbackOrderAndFailuresPreserveAvailableAlternatives() async throws {
    let project = self.project(1)
    let task = self.feature.request(.afterBacking(project), route: UUID())
    await self.provider.categories.waitFor(1)
    try self.provider.categories.finish(0, .success(.art))
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await self.provider.pages.waitFor(2)
    XCTAssertEqual(self.provider.parameters[1].similarTo, project)
    XCTAssertEqual(self.provider.parameters[1].perPage, 3)
    try self.provider.pages.finish(1, .success([self.project(1), self.project(2)]))
    await self.provider.pages.waitFor(3)
    XCTAssertEqual(self.provider.parameters[2].category, .art)
    XCTAssertEqual(self.provider.parameters[2].staffPicks, true)
    try self.provider.pages.finish(2, .success([self.project(2), self.project(3)]))
    await task.value
    XCTAssertEqual(self.values.first?.1.projects.map(\.id), [2, 3])
  }

  func testReconfiguredProjectKeepsCategoryPairedAndIgnoresOldLookup() async throws {
    let route = UUID()
    let first = self.feature.request(.afterBacking(self.project(1)), route: route)
    await self.provider.categories.waitFor(1)
    let second = self.feature.request(.afterBacking(self.project(2)), route: route)
    await self.provider.categories.waitFor(2)
    try self.provider.categories.finish(1, .success(.tabletopGames))
    await self.provider.pages.waitFor(1)
    try self.provider.pages.finish(0, .success([self.project(3), self.project(4), self.project(5)]))
    await second.value
    try self.provider.categories.finish(0, .success(.art))
    await first.value
    XCTAssertEqual(self.values.count, 1)
    XCTAssertEqual(self.values.first?.1.category, Category.tabletopGames.parent)
    XCTAssertEqual(self.provider.pages.count, 1)
  }

  func testSessionReplacementStopsFallbackAndSuppressesOutput() async throws {
    let task = self.feature.request(.afterBacking(self.project(1)), route: UUID())
    await self.provider.categories.waitFor(1)
    try self.provider.categories.finish(0, .success(.art))
    await self.provider.pages.waitFor(1)
    self.feature.sessionFeature.sessionChanged()
    try self.provider.pages.finish(0, .success([self.project(2)]))
    await task.value
    XCTAssertEqual(self.provider.pages.count, 1)
    XCTAssertTrue(self.values.isEmpty)
  }

  func testCategoryFailureDoesNotStartDiscovery() async throws {
    let task = self.feature.request(.afterBacking(self.project(1)), route: UUID())
    await self.provider.categories.waitFor(1)
    try self.provider.categories.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await task.value
    XCTAssertEqual(self.provider.pages.count, 0)
    XCTAssertTrue(self.values.isEmpty)
  }

  func testMissingProjectCategoryDoesNotRequest() async {
    let project = self.project(1) |> Project.lens.category .~ nil
    await self.feature.load(.afterBacking(project), route: UUID())
    XCTAssertEqual(self.provider.categories.count, 0)
    XCTAssertTrue(self.values.isEmpty)
  }

  func testClosingThanksSuppressesLateRecommendations() async throws {
    let vm = ThanksViewModel(recommendationsFeature: self.feature)
    vm.configure(with: (self.project(1), .template, nil, 1))
    await self.provider.categories.waitFor(1)
    vm.closeButtonTapped()
    try self.provider.categories.finish(0, .success(.art))
    await self.feature.waitForOperations()
    XCTAssertTrue(self.values.isEmpty)
    XCTAssertEqual(self.provider.pages.count, 0)
  }
}

@MainActor
private final class ControlledRecommendationsProvider: RecommendationsProvider {
  let categories = AccountRequestGate<KsApi.Category>()
  let pages = AccountRequestGate<[Project]>()
  var parameters: [DiscoveryParams] = []
  func category(id: String) async throws -> KsApi.Category { try await self.categories.request() }
  func projects(parameters: DiscoveryParams) async throws -> [Project] {
    self.parameters.append(parameters)
    return try await self.pages.request()
  }
}
