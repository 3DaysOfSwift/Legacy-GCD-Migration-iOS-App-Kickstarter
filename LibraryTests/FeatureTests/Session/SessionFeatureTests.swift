@testable import KsApi
@testable import Library
import XCTest

@MainActor
final class SessionFeatureTests: XCTestCase {
  func testSharedBadgeCommandCommitsOnceAndKeepsLatestPreferences() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var user: User? = .template
    var commits = 0
    let feature = SessionFeature(
      makeProvider: { provider }, currentUser: { user },
      updateUser: { user = $0; commits += 1 }
    )
    let first = feature.request(.clearActivity)
    let duplicate = feature.request(.clearActivity)
    await provider.badges.waitFor(1)
    user?.chosenCurrency = "GBP"
    let readRevision = feature.readGeneration
    try provider.badges.finish(0, .success(0))
    _ = try await first.value
    _ = try await duplicate.value
    XCTAssertEqual(provider.badges.count, 1)
    XCTAssertEqual(commits, 1)
    XCTAssertEqual(user?.chosenCurrency, "GBP")
    XCTAssertEqual(user?.unseenActivityCount, 0)
    XCTAssertGreaterThan(feature.readGeneration, readRevision)
  }

  func testFailedBadgeCommandPreservesUserAndCanRetry() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var user: User? = .template
    user?.unseenActivityCount = 7
    var commits = 0
    let feature = SessionFeature(
      makeProvider: { provider }, currentUser: { user },
      updateUser: { user = $0; commits += 1 }
    )
    let failed = feature.request(.clearActivity)
    await provider.badges.waitFor(1)
    try provider.badges.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await failed.value; XCTFail("Expected failure") }
    catch { XCTAssertTrue(error is ErrorEnvelope) }
    XCTAssertEqual(user?.unseenActivityCount, 7)
    XCTAssertEqual(commits, 0)
    let retry = feature.request(.clearActivity)
    await provider.badges.waitFor(2)
    try provider.badges.finish(1, .success(0))
    _ = try await retry.value
    XCTAssertEqual(user?.unseenActivityCount, 0)
    XCTAssertEqual(commits, 1)
  }

  func testCompletedBadgeCommandInvalidatesOlderWholeUserRefresh() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var user: User? = .template
    let feature = SessionFeature(
      makeProvider: { provider }, currentUser: { user }, updateUser: { user = $0 }
    )
    let read = feature.request()
    await provider.users.waitFor(1)
    let write = feature.request(.clearActivity)
    await provider.badges.waitFor(1)
    try provider.badges.finish(0, .success(0))
    _ = try await write.value
    var obsolete = User.template
    obsolete.unseenActivityCount = 9
    try provider.users.finish(0, .success(obsolete))
    do { _ = try await read.value; XCTFail("Old badge count escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(user?.unseenActivityCount, 0)
  }

  func testBadgeCommitDoesNotCancelIndependentAccountSetup() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var user: User? = .template
    var setupCommits = 0
    let feature = SessionFeature(
      makeProvider: { provider }, currentUser: { user },
      updateUser: { user = $0 }, updateSetup: { _ in setupCommits += 1 }
    )
    let setup = Task { try await feature.refreshSetup() }
    await provider.setups.waitFor(1)
    let badge = feature.request(.clearActivity)
    await provider.badges.waitFor(1)
    try provider.badges.finish(0, .success(0))
    _ = try await badge.value
    let metadata = GraphUserSetup(
      email: "fixture@example.invalid", enabledFeatures: [], ppoHasAction: true, backingActionCount: 2
    )
    try provider.setups.finish(0, .success(metadata))
    let result = try await setup.value
    XCTAssertEqual(result, metadata)
    XCTAssertEqual(setupCommits, 1)
    XCTAssertEqual(user?.unseenActivityCount, 0)
  }

  func testEquivalentSetupReadsShareAndCommitOnce() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var commits: [GraphUserSetup] = []
    let feature = SessionFeature(
      makeProvider: { provider },
      currentUser: { .template },
      updateSetup: { commits.append($0) }
    )
    let first = Task { try await feature.refreshSetup() }
    let second = Task { try await feature.refreshSetup() }
    await provider.setups.waitFor(1)
    let setup = GraphUserSetup(
      email: "fixture@example.invalid",
      enabledFeatures: [],
      ppoHasAction: true,
      backingActionCount: 3
    )
    try provider.setups.finish(0, .success(setup))
    _ = try await first.value
    _ = try await second.value
    XCTAssertEqual(provider.setups.count, 1)
    XCTAssertEqual(commits, [setup])
  }

  func testObsoleteSetupSuccessAndFailureCannotPublishAndCurrentRetryCan() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var commits = 0
    let feature = SessionFeature(
      makeProvider: { provider },
      currentUser: { .template },
      updateSetup: { _ in commits += 1 }
    )
    let setup = GraphUserSetup(
      email: "fixture@example.invalid",
      enabledFeatures: [],
      ppoHasAction: false,
      backingActionCount: 0
    )
    for (index, result) in [
      Result<GraphUserSetup, Error>.success(setup),
      .failure(ErrorEnvelope.couldNotParseJSON)
    ].enumerated() {
      let pending = Task { try await feature.refreshSetup() }
      await provider.setups.waitFor(index + 1)
      feature.sessionChanged()
      try provider.setups.finish(index, result)
      do { _ = try await pending.value; XCTFail("Obsolete setup escaped") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
    XCTAssertEqual(commits, 0)
    let retry = Task { try await feature.refreshSetup() }
    await provider.setups.waitFor(3)
    try provider.setups.finish(2, .success(setup))
    _ = try await retry.value
    XCTAssertEqual(commits, 1)
  }

  func testAccountWriteInvalidationRejectsInFlightSetupWithoutChangingSession() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var commits = 0
    let feature = SessionFeature(
      makeProvider: { provider },
      currentUser: { .template },
      updateSetup: { _ in commits += 1 }
    )
    let generation = feature.generation
    let pending = Task { try await feature.refreshSetup() }
    await provider.setups.waitFor(1)
    feature.invalidateReads()
    let setup = GraphUserSetup(
      email: "old@example.invalid",
      enabledFeatures: [],
      ppoHasAction: false,
      backingActionCount: 0
    )
    try provider.setups.finish(0, .success(setup))
    do { _ = try await pending.value; XCTFail("Stale setup committed") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(commits, 0)
    XCTAssertEqual(feature.generation, generation)
  }

  func testObsoleteUnauthorizedResponseCannotForceLogoutOfNewSession() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    let feature = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let old = feature.request()
    await provider.users.waitFor(1)
    feature.sessionChanged()
    let unauthorized = ErrorEnvelope(
      errorMessages: ["Expired fixture"],
      ksrCode: .AccessTokenInvalid,
      httpCode: 401,
      exception: nil
    )
    try provider.users.finish(0, .failure(unauthorized))
    do { _ = try await old.value; XCTFail("Old error escaped") }
    catch { XCTAssertTrue(error is CancellationError) }
    let current = feature.request()
    await provider.users.waitFor(2)
    try provider.users.finish(1, .failure(unauthorized))
    do { _ = try await current.value; XCTFail("Current error was swallowed") }
    catch { XCTAssertEqual((error as? ErrorEnvelope)?.ksrCode, .AccessTokenInvalid) }
  }

  func testLegacyTokenRestoreRequiresExplicitPermissionAndCurrentGeneration() {
    var user: User?
    let feature = SessionFeature(
      makeProvider: { ControlledSessionProvider() },
      currentUser: { user },
      updateUser: { user = $0 }
    )
    let generation = feature.generation
    feature.commitRefreshedUser(.template, userID: nil, generation: generation, allowSessionRestore: false)
    XCTAssertNil(user)
    feature.sessionChanged()
    feature.commitRefreshedUser(.template, userID: nil, generation: generation, allowSessionRestore: true)
    XCTAssertNil(user)
    feature.commitRefreshedUser(
      .template,
      userID: nil,
      generation: feature.generation,
      allowSessionRestore: true
    )
    XCTAssertEqual(user?.id, User.template.id)
  }

  func testEquivalentReadsShareAndFailureAllowsRetry() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    let feature = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let first = feature.request()
    let duplicate = feature.request()
    await provider.users.waitFor(1)
    try provider.users.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    for task in [first, duplicate] {
      do { _ = try await task.value; XCTFail("Expected error") } catch {}
    }
    XCTAssertEqual(provider.users.count, 1)
    let retry = feature.request()
    await provider.users.waitFor(2)
    try provider.users.finish(1, .success(.template))
    let user = try await retry.value
    XCTAssertEqual(user.id, User.template.id)
  }

  func testSessionRoundTripRejectsOldReadEvenWithSameUserID() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    let feature = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let old = feature.request()
    await provider.users.waitFor(1)
    feature.sessionChanged()
    let new = feature.request()
    await provider.users.waitFor(2)
    try provider.users.finish(0, .success(.template))
    do { _ = try await old.value; XCTFail("Obsolete read published") } catch is CancellationError {} catch {
      XCTFail("\(error)")
    }
    try provider.users.finish(1, .success(.template))
    _ = try await new.value
  }

  func testBadgeWriteContinuesButCannotUpdateNewAccount() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    var user: User? = .template
    let feature = SessionFeature(makeProvider: { provider }, currentUser: { user })
    let first = feature.request(.clearActivity)
    let duplicate = feature.request(.clearActivity)
    await provider.badges.waitFor(1)
    user = nil
    feature.sessionChanged()
    try provider.badges.finish(0, .success(0))
    for task in [first, duplicate] {
      do { _ = try await task.value; XCTFail("Obsolete badge result") } catch is CancellationError {} catch {
        XCTFail("\(error)")
      }
    }
    let denied = feature.request(.clearActivity)
    do { _ = try await denied.value; XCTFail("Logged-out mutation") } catch {}
    XCTAssertEqual(provider.badges.count, 1)
  }

  func testIndependentReadKindsAndCancelledWaiterDoNotCancelSharedWork() async throws {
    let provider = ControlledSessionProvider()
    defer { provider.releaseAll() }
    let feature = SessionFeature(makeProvider: { provider }, currentUser: { .template })
    let shared = feature.request()
    let joined = XCTestExpectation(description: "Waiter enters shared read")
    let waiter = Task {
      joined.fulfill()
      return try await feature.refresh()
    }
    let graph = feature.request(.graphUser)
    await provider.users.waitFor(1)
    await provider.graphs.waitFor(1)
    await fulfillment(of: [joined], timeout: 2)
    waiter.cancel()
    try provider.users.finish(0, .success(.template))
    try provider.graphs.finish(0, .success(.template))
    _ = try await shared.value
    _ = try await graph.value
    do { _ = try await waiter.value; XCTFail("Cancelled waiter succeeded")
    } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(provider.users.count, 1)
  }
}

@MainActor
private final class ControlledSessionProvider: SessionProvider {
  let setups = AccountRequestGate<GraphUserSetup>()
  func setup() async throws -> GraphUserSetup { try await self.setups.request() }
  let users = AccountRequestGate<User>()
  let graphs = AccountRequestGate<User>()
  let badges = AccountRequestGate<Int>()
  func user() async throws -> User { try await self.users.request() }
  func graphUser() async throws -> User { try await self.graphs.request() }
  func clearActivityIndicator() async throws -> Int { try await self.badges.request() }
  func releaseAll() {
    self.users.releaseAll(); self.graphs.releaseAll(); self.badges.releaseAll(); self.setups.releaseAll()
  }
}
