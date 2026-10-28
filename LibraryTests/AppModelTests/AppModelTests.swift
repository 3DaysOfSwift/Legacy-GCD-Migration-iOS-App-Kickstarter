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
    let firstSession = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let secondSession = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let firstDetails =
      ProjectDetailsFeature(sessionFeature: firstSession, makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let secondDetails =
      ProjectDetailsFeature(sessionFeature: secondSession, makeProvider: { AsyncProjectDetailsProvider(service: MockService()) })
    let firstSettings = SettingsFeature(sessionFeature: firstSession, makeProvider: {
        AsyncAccountPreferencesProvider(service: MockService())
      })
    let first = AppModel(
      creatorDraftsFeature: CreatorDraftsFeature(sessionFeature: firstSession, makeProvider: {
        XCTFail("Composition must not load creator drafts")
        return AsyncCreatorDraftsProvider(service: MockService())
      }),
      recommendationsFeature: RecommendationsFeature(settingsFeature: firstSettings, makeProvider: {
        XCTFail("Composition must not perform recommendation requests")
        return AsyncRecommendationsProvider(service: MockService())
      }),
      projectReportingFeature: ProjectReportingFeature(sessionFeature: firstSession, makeProvider: { AsyncProjectReportingProvider(service: MockService()) }),
      friendsFeature: FriendsFeature(sessionFeature: firstSession, makeProvider: { AsyncFriendsProvider(service: MockService()) }),
      pledgedProjectsFeature: PledgedProjectsFeature(sessionFeature: firstSession, makeProvider: { AsyncPledgedProjectsProvider(service: MockService()) }),
      pledgeFeature: PledgeFeature(sessionFeature: firstSession, makeProvider: { AsyncPledgeProvider(service: MockService()) }),
      paymentsFeature: PaymentsFeature(sessionFeature: firstSession, makeProvider: { AsyncPaymentsProvider(service: MockService()) }),
      messagingFeature: MessagingFeature(sessionFeature: firstSession, makeProvider: { AsyncMessagingProvider(service: MockService()) }),
      sessionFeature: firstSession,
      authenticationFeature: AuthenticationFeature(sessionFeature: firstSession, makeProvider: {
        AsyncAuthenticationProvider(service: MockService())
      }),
      settingsFeature: firstSettings,
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
      rewardsFeature: RewardsFeature(sessionFeature: firstSession, makeProvider: { AsyncRewardsProvider(service: MockService()) }),
      discussionFeature: DiscussionFeature(makeProvider: { AsyncDiscussionProvider(service: MockService()) }),
      projectMediaFeature: ProjectMediaFeature(sessionFeature: firstSession, makeProvider: {
        AsyncProjectMediaProvider(service: MockService())
      })
    )
    let secondSettings = SettingsFeature(sessionFeature: secondSession, makeProvider: {
        AsyncAccountPreferencesProvider(service: MockService())
      })
    let second = AppModel(
      creatorDraftsFeature: CreatorDraftsFeature(sessionFeature: secondSession, makeProvider: {
        XCTFail("Composition must not load creator drafts")
        return AsyncCreatorDraftsProvider(service: MockService())
      }),
      recommendationsFeature: RecommendationsFeature(settingsFeature: secondSettings, makeProvider: {
        XCTFail("Composition must not perform recommendation requests")
        return AsyncRecommendationsProvider(service: MockService())
      }),
      projectReportingFeature: ProjectReportingFeature(sessionFeature: secondSession, makeProvider: { AsyncProjectReportingProvider(service: MockService()) }),
      friendsFeature: FriendsFeature(sessionFeature: secondSession, makeProvider: { AsyncFriendsProvider(service: MockService()) }),
      pledgedProjectsFeature: PledgedProjectsFeature(sessionFeature: secondSession, makeProvider: { AsyncPledgedProjectsProvider(service: MockService()) }),
      pledgeFeature: PledgeFeature(sessionFeature: secondSession, makeProvider: { AsyncPledgeProvider(service: MockService()) }),
      paymentsFeature: PaymentsFeature(sessionFeature: secondSession, makeProvider: { AsyncPaymentsProvider(service: MockService()) }),
      messagingFeature: MessagingFeature(sessionFeature: secondSession, makeProvider: { AsyncMessagingProvider(service: MockService()) }),
      sessionFeature: secondSession,
      authenticationFeature: AuthenticationFeature(sessionFeature: secondSession, makeProvider: {
        AsyncAuthenticationProvider(service: MockService())
      }),
      settingsFeature: secondSettings,
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
      rewardsFeature: RewardsFeature(sessionFeature: secondSession, makeProvider: { AsyncRewardsProvider(service: MockService()) }),
      discussionFeature: DiscussionFeature(makeProvider: { AsyncDiscussionProvider(service: MockService()) }),
      projectMediaFeature: ProjectMediaFeature(sessionFeature: secondSession, makeProvider: {
        AsyncProjectMediaProvider(service: MockService())
      })
    )

    XCTAssertTrue(first.creatorDraftsFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.creatorDraftsFeature === second.creatorDraftsFeature)
    XCTAssertTrue(first.recommendationsFeature.settingsFeature === first.settingsFeature)
    XCTAssertTrue(first.recommendationsFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.recommendationsFeature === second.recommendationsFeature)
    XCTAssertTrue(first.projectReportingFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.projectReportingFeature === second.projectReportingFeature)
    XCTAssertTrue(first.friendsFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.friendsFeature === second.friendsFeature)
    XCTAssertFalse(first.pledgedProjectsFeature === second.pledgedProjectsFeature)
    XCTAssertTrue(first.pledgeFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.pledgeFeature === second.pledgeFeature)
    XCTAssertTrue(first.paymentsFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.paymentsFeature === second.paymentsFeature)
    XCTAssertTrue(first.messagingFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.messagingFeature === second.messagingFeature)
    XCTAssertTrue(first.activityFeature.sessionFeature === first.sessionFeature)
    XCTAssertTrue(first.profileFeature.sessionFeature === first.sessionFeature)
    XCTAssertFalse(first.sessionFeature === second.sessionFeature)
    XCTAssertFalse(first.authenticationFeature === second.authenticationFeature)
    XCTAssertFalse(first.settingsFeature === second.settingsFeature)
    XCTAssertFalse(first.activityFeature === second.activityFeature)
    XCTAssertFalse(first.profileFeature === second.profileFeature)
    XCTAssertTrue(first.searchFeature === firstFeature)
    XCTAssertTrue(second.searchFeature === secondFeature)
    XCTAssertFalse(first.searchFeature === second.searchFeature)
    XCTAssertFalse(first.discoveryFeature === second.discoveryFeature)
    XCTAssertTrue(first.projectDetailsFeature.sessionFeature === first.sessionFeature)
    XCTAssertTrue(first.projectDetailsFeature === firstDetails)
    XCTAssertTrue(second.projectDetailsFeature === secondDetails)
    XCTAssertFalse(first.projectDetailsFeature === second.projectDetailsFeature)
    XCTAssertFalse(first.rewardsFeature === second.rewardsFeature)
    XCTAssertFalse(first.discussionFeature === second.discussionFeature)
    XCTAssertFalse(first.projectMediaFeature === second.projectMediaFeature)
    XCTAssertTrue(first.projectMediaFeature.sessionFeature === first.sessionFeature)
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
