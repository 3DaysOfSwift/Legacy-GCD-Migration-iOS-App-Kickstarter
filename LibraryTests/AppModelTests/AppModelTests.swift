import GraphAPI
@testable import KsApi
@testable import Library
import ReactiveSwift
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
  func testGraphsRetainTheirInjectedFeaturesWithoutSharingState() {
    let firstProvider = NoRequestSearchProvider()
    let secondProvider = NoRequestSearchProvider()
    let firstFeature = SearchFeature(provider: firstProvider)
    let secondFeature = SearchFeature(provider: secondProvider)
    let firstDetails =
      ProjectDetailsFeature(makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let secondDetails =
      ProjectDetailsFeature(makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let firstSession = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let secondSession = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let first = AppModel(
      sessionFeature: firstSession,
      settingsFeature: SettingsFeature(sessionFeature: firstSession, makeProvider: {
        AsyncAccountPreferencesProvider(service: MockService())
      }),
      activityFeature: ActivityFeature(
        sessionFeature: firstSession,
        makeProvider: { AsyncActivityProvider(service: MockService()) }
      ),
      profileFeature: ProfileFeature(
        sessionFeature: firstSession,
        makeProvider: { AsyncProfileProvider(service: MockService()) }
      ),
      searchFeature: firstFeature,
      discoveryFeature: DiscoveryFeature(provider: NoRequestDiscoveryProvider()),
      projectDetailsFeature: firstDetails,
      rewardsFeature: RewardsFeature(makeProvider: { AsyncRewardsProvider(service: MockService()) }),
      discussionFeature: DiscussionFeature(makeProvider: { AsyncDiscussionProvider(service: MockService()) }),
      projectMediaFeature: ProjectMediaFeature(makeProvider: {
        AsyncProjectMediaProvider(service: MockService())
      })
    )
    let second = AppModel(
      sessionFeature: secondSession,
      settingsFeature: SettingsFeature(sessionFeature: secondSession, makeProvider: {
        AsyncAccountPreferencesProvider(service: MockService())
      }),
      activityFeature: ActivityFeature(
        sessionFeature: secondSession,
        makeProvider: { AsyncActivityProvider(service: MockService()) }
      ),
      profileFeature: ProfileFeature(
        sessionFeature: secondSession,
        makeProvider: { AsyncProfileProvider(service: MockService()) }
      ),
      searchFeature: secondFeature,
      discoveryFeature: DiscoveryFeature(provider: NoRequestDiscoveryProvider()),
      projectDetailsFeature: secondDetails,
      rewardsFeature: RewardsFeature(makeProvider: { AsyncRewardsProvider(service: MockService()) }),
      discussionFeature: DiscussionFeature(makeProvider: { AsyncDiscussionProvider(service: MockService()) }),
      projectMediaFeature: ProjectMediaFeature(makeProvider: {
        AsyncProjectMediaProvider(service: MockService())
      })
    )

    XCTAssertTrue(first.activityFeature.sessionFeature === first.sessionFeature)
    XCTAssertTrue(first.profileFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.sessionFeature === second.sessionFeature)
    XCTAssertFalse(first.settingsFeature === second.settingsFeature)
    XCTAssertFalse(first.activityFeature === second.activityFeature)
    XCTAssertFalse(first.profileFeature === second.profileFeature)
    XCTAssertTrue(first.searchFeature === firstFeature)
    XCTAssertTrue(second.searchFeature === secondFeature)
    XCTAssertFalse(first.searchFeature === second.searchFeature)
    XCTAssertFalse(first.discoveryFeature === second.discoveryFeature)
    XCTAssertTrue(first.projectDetailsFeature === firstDetails)
    XCTAssertTrue(second.projectDetailsFeature === secondDetails)
    XCTAssertFalse(first.projectDetailsFeature === second.projectDetailsFeature)
    XCTAssertFalse(first.rewardsFeature === second.rewardsFeature)
    XCTAssertFalse(first.discussionFeature === second.discussionFeature)
    XCTAssertFalse(first.projectMediaFeature === second.projectMediaFeature)
    XCTAssertTrue(first.discoveryFeature.snapshot(for: .magic).projects.isEmpty)
    XCTAssertEqual(firstProvider.requestCount, 0)
    XCTAssertEqual(secondProvider.requestCount, 0)
    XCTAssertNil(first.searchFeature.parameters)
    XCTAssertNil(second.searchFeature.parameters)
    first.sessionChanged()
    XCTAssertEqual(first.sessionFeature.generation, 1)
    XCTAssertEqual(second.sessionFeature.generation, 0)
  }
}

@MainActor
private final class NoRequestSearchProvider: SearchProjectsProvider {
  private(set) var requestCount = 0

  func fetchPage(
    parameters _: DiscoveryParams, cursor _: String?
  ) async throws -> GraphAPI.SearchQuery.Data {
    self.requestCount += 1
    throw CancellationError()
  }
}

@MainActor
private struct NoRequestDiscoveryProvider: DiscoveryProvider {
  func page(parameters _: DiscoveryParams, cursor _: String?) async throws -> DiscoveryEnvelope {
    XCTFail("Composition must not perform requests")
    throw CancellationError()
  }

  func activitySample() async throws -> ActivityEnvelope? {
    XCTFail("Composition must not perform requests")
    throw CancellationError()
  }
}
