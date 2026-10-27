import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import ReactiveSwift
import XCTest

private typealias User = KsApi.User

@MainActor
final class ProfileFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testPreferenceSaveInvalidatesHeaderAlreadyWaitingInPresentationDelay() async throws {
    let provider = ControlledHeaderProvider()
    let delay = AccountRequestGate<Void>()
    defer { provider.users.releaseAll(); provider.graphs.releaseAll(); delay.releaseAll() }
    var commits = 0
    let session = SessionFeature(
      makeProvider: { provider },
      currentUser: { .template },
      updateUser: { _ in commits += 1 }
    )
    let feature = ProfileFeature(
      sessionFeature: session,
      makeProvider: { ControlledProfileProvider() },
      sleep: { _ in try await delay.request() }
    )
    var combined = 0
    feature.combinedUserValues.observeValues { _ in combined += 1 }
    let request = feature.requestHeader()
    await provider.users.waitFor(1)
    await provider.graphs.waitFor(1)
    try provider.users.finish(0, .success(.template))
    try provider.graphs.finish(0, .success(.template))
    await delay.waitFor(2)
    session.invalidateReads()
    try delay.finish(0, .success(()))
    try delay.finish(1, .success(()))
    await request.value
    XCTAssertEqual(commits, 0)
    XCTAssertEqual(combined, 0)
  }

  private func projects(_ count: Int) -> [ProjectCardProperties] {
    let mock = GraphAPI.ProjectCardFragment.mockProjectsConnectionQuery(numberOfProjects: count)
    let data = GraphAPI.FetchMyBackedProjectsQuery.Data.from(mock)
    return data.projects?.nodes?.compactMap { $0?.fragments.projectCardFragment }
      .compactMap(ProjectCardProperties.init) ?? []
  }

  func testIndependentTabsShareDuplicatesAndPreservePageOnFailure() async throws {
    let provider = ControlledProfileProvider()
    defer { provider.pages.releaseAll() }
    let session = SessionFeature(
      makeProvider: { AsyncSessionProvider(service: MockService()) },
      currentUser: { .template }
    )
    let feature = ProfileFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    let backed = feature.requestPage(type: .backed), duplicate = feature.requestPage(type: .backed)
    await provider.pages.waitFor(1)
    let saved = feature.requestPage(type: .saved)
    await provider.pages.waitFor(2)
    try provider.pages.finish(1, .success(.init(projects: self.projects(1), cursor: nil)))
    await saved?.value
    XCTAssertEqual(feature.snapshot(for: .saved).projects.count, 1)
    XCTAssertTrue(feature.snapshot(for: .backed).isLoading)
    try provider.pages.finish(0, .success(.init(projects: self.projects(2), cursor: "next")))
    await backed?.value; await duplicate?.value
    let next = feature.requestPage(type: .backed, next: true)
    await provider.pages.waitFor(3)
    try provider.pages.finish(2, .failure(ErrorEnvelope.couldNotParseJSON))
    await next?.value
    XCTAssertEqual(feature.snapshot(for: .backed).projects.count, 2)
    XCTAssertNotNil(feature.snapshot(for: .backed).error)
    let retry = feature.requestPage(type: .backed, next: true)
    await provider.pages.waitFor(4)
    try provider.pages.finish(3, .success(.init(projects: self.projects(1), cursor: nil)))
    await retry?.value
    XCTAssertEqual(feature.snapshot(for: .backed).projects.count, 3)
    XCTAssertNil(feature.snapshot(for: .backed).error)
    XCTAssertEqual(provider.requests.map(\.1), [nil, nil, "next", "next"])
    XCTAssertNil(feature.requestPage(type: .backed, next: true))
  }

  func testRefreshSupersedesPageAndSessionChangeRejectsLateCompletion() async throws {
    let provider = ControlledProfileProvider()
    defer { provider.pages.releaseAll() }
    let session = SessionFeature(
      makeProvider: { AsyncSessionProvider(service: MockService()) },
      currentUser: { .template }
    )
    let feature = ProfileFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    let first = feature.requestPage(type: .backed)
    await provider.pages.waitFor(1)
    try provider.pages.finish(0, .success(.init(projects: self.projects(1), cursor: "next")))
    await first?.value
    let next = feature.requestPage(type: .backed, next: true)
    await provider.pages.waitFor(2)
    let refresh = feature.requestPage(type: .backed)
    await provider.pages.waitFor(3)
    try provider.pages.finish(2, .success(.init(projects: self.projects(2), cursor: nil)))
    await refresh?.value
    try provider.pages.finish(1, .success(.init(projects: self.projects(3), cursor: nil)))
    await next?.value
    XCTAssertEqual(feature.snapshot(for: .backed).projects.count, 2)
    let obsolete = feature.requestPage(type: .backed)
    await provider.pages.waitFor(4)
    session.sessionChanged()
    let replacement = feature.requestPage(type: .backed)
    await provider.pages.waitFor(5)
    try provider.pages.finish(3, .success(.init(projects: self.projects(3), cursor: nil)))
    await obsolete?.value
    XCTAssertTrue(feature.snapshot(for: .backed).projects.isEmpty)
    try provider.pages.finish(4, .success(.init(projects: [], cursor: nil)))
    await replacement?.value
    XCTAssertTrue(feature.snapshot(for: .backed).projects.isEmpty)
  }

  func testHeaderFetchesConcurrentlyAndCombinesRegardlessOfCompletionOrder() async throws {
    let provider = ControlledHeaderProvider()
    defer { provider.users.releaseAll(); provider.graphs.releaseAll() }
    let session = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let feature = ProfileFeature(
      sessionFeature: session,
      makeProvider: { ControlledProfileProvider() },
      sleep: { _ in }
    )
    var combined: [User] = []
    var displayed: [User] = []
    feature.combinedUserValues.observeValues { combined.append($0) }
    feature.userValues.observeValues { displayed.append($0) }
    let first = feature.requestHeader(), duplicate = feature.requestHeader()
    await provider.users.waitFor(1); await provider.graphs.waitFor(1)
    var graph = User.template
    graph.stats.starredProjectsCount = 73
    try provider.graphs.finish(0, .success(graph))
    try provider.users.finish(0, .success(.template))
    await first.value; await duplicate.value
    XCTAssertEqual(displayed.count, 2, "Cached prefix then refreshed header")
    XCTAssertEqual(combined.count, 1)
    XCTAssertEqual(combined.first?.stats.starredProjectsCount, 73)
    XCTAssertEqual(provider.users.count, 1)
    XCTAssertEqual(provider.graphs.count, 1)
  }

  func testHeaderFailureDoesNotBlockIndependentDisplayOrPublishPartialSession() async throws {
    let provider = ControlledHeaderProvider()
    defer { provider.users.releaseAll(); provider.graphs.releaseAll() }
    let session = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let feature = ProfileFeature(
      sessionFeature: session,
      makeProvider: { ControlledProfileProvider() },
      sleep: { _ in }
    )
    var graphValues = 0, combined = 0
    feature.graphUserValues.observeValues { _ in graphValues += 1 }
    feature.combinedUserValues.observeValues { _ in combined += 1 }
    let request = feature.requestHeader()
    await provider.users.waitFor(1); await provider.graphs.waitFor(1)
    try provider.users.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try provider.graphs.finish(0, .success(.template))
    await request.value
    XCTAssertEqual(graphValues, 1)
    XCTAssertEqual(combined, 0)
    XCTAssertNotNil(feature.userError)
    XCTAssertNil(feature.graphUserError)
  }

  func testResetRejectsLateFailuresAndClearsStoredCollections() async throws {
    let provider = ControlledProfileProvider()
    defer { provider.pages.releaseAll() }
    let session = SessionFeature(
      makeProvider: { AsyncSessionProvider(service: MockService()) },
      currentUser: { .template }
    )
    let feature = ProfileFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    let first = feature.requestPage(type: .backed)
    await provider.pages.waitFor(1)
    try provider.pages.finish(0, .success(.init(projects: self.projects(2), cursor: "next")))
    await first?.value
    let next = feature.requestPage(type: .backed, next: true)
    await provider.pages.waitFor(2)
    feature.reset()
    try provider.pages.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await next?.value
    XCTAssertTrue(feature.snapshot(for: .backed).projects.isEmpty)
    XCTAssertNil(feature.snapshot(for: .backed).error)
    XCTAssertFalse(feature.snapshot(for: .backed).isLoading)
  }

  func testLoggedOutDoesNotFetchPrivateCollectionsOrHeader() async {
    let provider = ControlledProfileProvider()
    let header = ControlledHeaderProvider()
    let session = SessionFeature(makeProvider: { header }, currentUser: { nil })
    let feature = ProfileFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    await feature.refreshHeader()
    await feature.refresh(type: .backed)
    await feature.refresh(type: .saved)
    XCTAssertEqual(provider.pages.count, 0)
    XCTAssertEqual(header.users.count, 0)
    XCTAssertEqual(header.graphs.count, 0)
  }

  func testSaveInvalidatesInFlightHeaderWithoutChangingAccountGeneration() async throws {
    let provider = ControlledHeaderProvider()
    defer { provider.users.releaseAll(); provider.graphs.releaseAll() }
    let session = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let feature = ProfileFeature(
      sessionFeature: session, makeProvider: { ControlledProfileProvider() }, sleep: { _ in }
    )
    var combined: [User] = []
    feature.combinedUserValues.observeValues { combined.append($0) }
    let old = feature.requestHeader()
    await provider.users.waitFor(1)
    await provider.graphs.waitFor(1)
    let fresh = feature.requestHeader(replacing: true)
    await provider.users.waitFor(2)
    await provider.graphs.waitFor(2)
    var newUser = User.template
    newUser.stats.starredProjectsCount = 88
    try provider.users.finish(1, .success(newUser))
    try provider.graphs.finish(1, .success(newUser))
    await fresh.value
    try provider.users.finish(0, .success(.template))
    try provider.graphs.finish(0, .success(.template))
    await old.value
    XCTAssertEqual(session.generation, 0)
    XCTAssertEqual(combined.count, 1)
    XCTAssertEqual(combined.first?.stats.starredProjectsCount, 88)
  }
}

@MainActor
private final class ControlledProfileProvider: ProfileProvider {
  let pages = AccountRequestGate<ProfileFeature.Page>()
  var requests: [(ProfileProjectsType, String?)] = []
  func page(type: ProfileProjectsType, cursor: String?) async throws -> ProfileFeature.Page {
    self.requests.append((type, cursor))
    return try await self.pages.request()
  }
}

@MainActor
private final class ControlledHeaderProvider: SessionProvider {
  let users = AccountRequestGate<User>()
  let graphs = AccountRequestGate<User>()
  func user() async throws -> User { try await self.users.request() }
  func graphUser() async throws -> User { try await self.graphs.request() }
  func clearActivityIndicator() async throws
    -> Int { XCTFail("Unexpected mutation"); throw CancellationError() }
}
