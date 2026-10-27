import Foundation
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
final class ProjectDetailsFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testCreatorMessageAuthorizationUsesCurrentSession() {
    let feature = self.feature(ControlledProjectDetailsProvider())
    XCTAssertTrue(feature.creatorMessageRequiresAuthentication)
    XCTAssertNil(feature.creatorMessageSubject(projectID: 42, projectName: "Creator project"))
    withEnvironment(currentUser: User.template) {
      XCTAssertFalse(feature.creatorMessageRequiresAuthentication)
      XCTAssertEqual(
        feature.creatorMessageSubject(projectID: 42, projectName: "Creator project"),
        .project(id: 42, name: "Creator project")
      )
    }
    XCTAssertNil(feature.creatorMessageSubject(projectID: 42, projectName: "Creator project"))
  }

  func testCreatorRequestPreparationAndMessageClassification() throws {
    let feature = self.feature(ControlledProjectDetailsProvider())
    let request = try XCTUnwrap(feature.creatorBiographyRequest(
      projectURL: "https://www.kickstarter.com/projects/creator/project"
    ))
    XCTAssertEqual(request.url?.path, "/projects/creator/project/creator_bio")
    XCTAssertTrue(AppEnvironment.current.apiService.isPrepared(request: request))
    XCTAssertFalse(feature.isCreatorMessage(request: request))
    let messageURL = try XCTUnwrap(URL(string: "https://www.kickstarter.com/projects/a/b/messages/new"))
    XCTAssertTrue(feature.isCreatorMessage(request: URLRequest(url: messageURL)))
  }

  func testRelatedSharingAndReplacementRejectsLateFailure() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseRelated = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let first = feature.requestRelated(route: route, projectID: "1")
    let shared = feature.requestRelated(route: route, projectID: "1")
    await provider.waitFor("related:1")
    XCTAssertEqual(provider.calls, ["related:1"])
    let second = feature.requestRelated(route: route, projectID: "2")
    await provider.waitFor("related:2")
    try provider.finishRelated(1, error: nil)
    await second.value
    try provider.finishRelated(0, error: .graphError("obsolete"))
    await first.value
    await shared.value
    XCTAssertTrue(first.isCancelled)
    XCTAssertNil(feature.relatedSnapshot(for: route).error)
    XCTAssertFalse(feature.relatedSnapshot(for: route).isLoading)
  }

  func testRelatedFailureAndEmptySuccessAreDistinctAndRetryable() async {
    let provider = ControlledProjectDetailsProvider()
    let feature = self.feature(provider)
    let route = UUID()
    provider.failAt = "related:1"
    await feature.loadRelated(route: route, projectID: "1")
    XCTAssertNotNil(feature.relatedSnapshot(for: route).error)
    XCTAssertFalse(feature.relatedSnapshot(for: route).isLoading)
    provider.failAt = nil
    await feature.loadRelated(route: route, projectID: "1")
    XCTAssertNil(feature.relatedSnapshot(for: route).error)
    XCTAssertTrue(feature.relatedSnapshot(for: route).projects.isEmpty)
  }

  func testRelatedRoutesReleaseIndependently() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseRelated = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let firstRoute = UUID(), secondRoute = UUID()
    let first = feature.requestRelated(route: firstRoute, projectID: "1")
    let second = feature.requestRelated(route: secondRoute, projectID: "1")
    await provider.waitFor("related:1", count: 2)
    feature.releaseRelated(route: firstRoute)
    try provider.finishRelated(0, error: .graphError("released"))
    try provider.finishRelated(1, error: .graphError("current"))
    await first.value
    await second.value
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
    XCTAssertNil(feature.relatedSnapshot(for: firstRoute).error)
    XCTAssertNotNil(feature.relatedSnapshot(for: secondRoute).error)
  }

  func testRelatedAccountChangeDoesNotShareOrPublishOldRequest() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseRelated = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let anonymous = feature.requestRelated(route: route, projectID: "1")
    await provider.waitFor("related:1")
    AppEnvironment.pushEnvironment(currentUser: User.template)
    defer { AppEnvironment.popEnvironment() }
    do {
      let signedIn = feature.requestRelated(route: route, projectID: "1")
      await provider.waitFor("related:1", count: 2)
      try provider.finishRelated(0, error: .graphError("anonymous"))
      await anonymous.value
      XCTAssertTrue(feature.relatedSnapshot(for: route).isLoading)
      XCTAssertNil(feature.relatedSnapshot(for: route).error)
      try provider.finishRelated(1, error: nil)
      await signedIn.value
      XCTAssertFalse(feature.relatedSnapshot(for: route).isLoading)
    }
  }

  private func feature(
    _ provider: ControlledProjectDetailsProvider,
    fast: Bool = false
  ) -> ProjectDetailsFeature {
    ProjectDetailsFeature(
      makeProvider: { provider },
      useFastLoading: { fast },
      includeRichText: { true },
      sleep: { _ in try Task.checkCancellation() }
    )
  }

  func testStandardLoadOrdersBackingBeforeRewardsAndPreservesProjectFields() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.backingID = 42
    let feature = self.feature(provider)
    let route = UUID()
    await feature.load(route: route, param: .id(1))
    XCTAssertEqual(provider.calls, ["project", "backing", "rewards"])
    let project = try XCTUnwrap(feature.snapshot(for: route).project)
    XCTAssertEqual(project.name, Project.template.name)
    XCTAssertEqual(project.personalization.backing, Backing.template)
    XCTAssertEqual(project.personalization.isBacking, true)
    XCTAssertEqual(project.rewards, [Reward.noReward, Reward.template])
    XCTAssertFalse(feature.snapshot(for: route).isLoading)
    XCTAssertNil(feature.snapshot(for: route).error)
    XCTAssertEqual(provider.richTextValues, [true])
  }

  func testUnbackedProjectSkipsBackingAndKeepsNoRewardFirst() async throws {
    let provider = ControlledProjectDetailsProvider()
    let feature = self.feature(provider)
    let route = UUID()
    await feature.load(route: route, param: .slug("example"))
    XCTAssertEqual(provider.calls, ["project", "rewards"])
    XCTAssertEqual(feature.snapshot(for: route).project?.rewards, [Reward.noReward, Reward.template])
  }

  func testEnrollmentMustCompleteBeforeAnyRead() async throws {
    await withEnvironment(currentUser: User.template) {
      let provider = ControlledProjectDetailsProvider()
      provider.pauseEnrollment = true
      defer { provider.releaseAll() }
      let feature = self.feature(provider)
      let route = UUID()
      let task = feature.requestLoad(route: route, param: .id(1), secretRewardToken: "local-test-token")
      await provider.waitFor("enroll")
      XCTAssertEqual(provider.calls, ["enroll"])
      provider.finishEnrollment()
      await task.value
      XCTAssertEqual(provider.calls, ["enroll", "project", "rewards"])
      XCTAssertNotNil(feature.snapshot(for: route).project)
    }
  }

  func testEnrollmentFailureStopsReadsAndIsRetryable() async {
    await withEnvironment(currentUser: User.template) {
      let provider = ControlledProjectDetailsProvider()
      provider.failAt = "enroll"
      let feature = self.feature(provider)
      let route = UUID()
      await feature.load(route: route, param: .id(1), secretRewardToken: "local-test-token")
      XCTAssertEqual(provider.calls, ["enroll"])
      XCTAssertNotNil(feature.snapshot(for: route).error)
      provider.failAt = nil
      await feature.load(route: route, param: .id(1), secretRewardToken: "local-test-token")
      XCTAssertEqual(provider.calls, ["enroll", "enroll", "project", "rewards"])
      XCTAssertNil(feature.snapshot(for: route).error)
    }
  }

  func testAnonymousOrEmptyTokenDoesNotEnroll() async {
    let provider = ControlledProjectDetailsProvider()
    let feature = self.feature(provider)
    await feature.load(route: UUID(), param: .id(1), secretRewardToken: "local-test-token")
    await withEnvironment(currentUser: User.template) {
      await feature.load(route: UUID(), param: .id(1), secretRewardToken: "")
    }
    XCTAssertFalse(provider.calls.contains("enroll"))
  }

  func testBackingAndRewardsFailuresNeverPublishPartialProjectAndRetryRetainsCache() async {
    for failure in ["project", "backing", "rewards"] {
      let provider = ControlledProjectDetailsProvider()
      provider.backingID = 42
      let feature = self.feature(provider)
      let route = UUID()
      provider.failAt = failure
      await feature.load(route: route, param: .id(1))
      XCTAssertNil(feature.snapshot(for: route).project)
      XCTAssertNotNil(feature.snapshot(for: route).error)
      XCTAssertEqual(provider.calls.last, failure)
      provider.failAt = nil
      await feature.load(route: route, param: .id(1))
      let cached = feature.snapshot(for: route).project
      XCTAssertNotNil(cached)
      provider.failAt = failure
      await feature.load(route: route, param: .id(1))
      XCTAssertEqual(feature.snapshot(for: route).project, cached)
      XCTAssertNotNil(feature.snapshot(for: route).error)
      XCTAssertFalse(feature.snapshot(for: route).isLoading)
    }
  }

  func testEquivalentRequestsShareAndChangedRequestRejectsLateCompletion() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseProjects = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let first = feature.requestLoad(route: route, param: .id(1))
    await provider.waitFor("project")
    let shared = feature.requestLoad(route: route, param: .id(1))
    XCTAssertEqual(provider.projects.count, 1)
    let replacement = feature.requestLoad(route: route, param: .id(2))
    await provider.waitFor("project", count: 2)
    try provider.finishProject(1, id: 2)
    await replacement.value
    try provider.finishProject(0, id: 1)
    await first.value
    await shared.value
    XCTAssertEqual(feature.snapshot(for: route).project?.id, 2)
    XCTAssertEqual(provider.calls.filter { $0 == "rewards" }.count, 1)
  }

  func testCancelOneRouteDoesNotCancelAnotherAndReleaseRemovesState() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseProjects = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let firstRoute = UUID()
    let secondRoute = UUID()
    let first = feature.requestLoad(route: firstRoute, param: .id(1))
    await provider.waitFor("project")
    let second = feature.requestLoad(route: secondRoute, param: .id(2))
    await provider.waitFor("project", count: 2)
    feature.cancel(route: firstRoute)
    try provider.finishProject(0, id: 1)
    try provider.finishProject(1, id: 2)
    await first.value
    await second.value
    XCTAssertNil(feature.snapshot(for: firstRoute).project)
    XCTAssertNil(feature.snapshot(for: firstRoute).error)
    XCTAssertEqual(feature.snapshot(for: secondRoute).project?.id, 2)
    feature.release(route: secondRoute)
    XCTAssertNil(feature.snapshot(for: secondRoute).project)
  }

  func testAccountChangeRejectsResultBeforeBackingOrRewards() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseProjects = true
    provider.backingID = 42
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let task = feature.requestLoad(route: route, param: .id(1))
    await provider.waitFor("project")
    await withEnvironment(currentUser: User.template) {
      do { try provider.finishProject(0, id: 1) }
      catch { XCTFail("Could not complete fixture: \(error)") }
      await task.value
      XCTAssertNil(feature.snapshot(for: route).project)
      XCTAssertEqual(provider.calls, ["project"])
      XCTAssertNil(feature.snapshot(for: route).error)
    }
  }

  func testFastPathStartsBothDependenciesAndWaitsForBoth() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseBase = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider, fast: true)
    let route = UUID()
    let task = feature.requestLoad(route: route, param: .id(1))
    await provider.waitFor("base")
    await provider.waitFor("extras")
    XCTAssertNil(feature.snapshot(for: route).project)
    provider.finishBase()
    await task.value
    XCTAssertEqual(Set(provider.calls), Set(["base", "extras"]))
    XCTAssertEqual(feature.snapshot(for: route).project?.extendedProjectProperties?.risks, "risk")
    XCTAssertEqual(feature.snapshot(for: route).project?.extendedProjectProperties?.minimumPledgeAmount, 1)
    XCTAssertEqual(feature.snapshot(for: route).project?.flagging, true)
  }

  func testFastDependencyFailuresPublishNoPartialProject() async {
    for failure in ["base", "extras"] {
      let provider = ControlledProjectDetailsProvider()
      provider.failAt = failure
      let feature = self.feature(provider, fast: true)
      let route = UUID()
      await feature.load(route: route, param: .id(1))
      XCTAssertNil(feature.snapshot(for: route).project)
      XCTAssertNotNil(feature.snapshot(for: route).error)
      XCTAssertFalse(feature.snapshot(for: route).isLoading)
    }
  }

  func testForceRefreshAfterMutationReplacesEquivalentRead() async throws {
    let provider = ControlledProjectDetailsProvider()
    provider.pauseProjects = true
    defer { provider.releaseAll() }
    let feature = self.feature(provider)
    let route = UUID()
    let first = feature.requestLoad(route: route, param: .id(1))
    await provider.waitFor("project")
    let refreshed = feature.requestLoad(route: route, param: .id(1), force: true)
    await provider.waitFor("project", count: 2)
    try provider.finishProject(1, id: 10)
    await refreshed.value
    try provider.finishProject(0, id: 9)
    await first.value
    XCTAssertEqual(feature.snapshot(for: route).project?.id, 10)
  }
}

@MainActor
private final class ControlledProjectDetailsProvider: ProjectDetailsProvider {
  var pauseRelated = false
  private var related: [CheckedContinuation<[ProjectCardProperties], Error>?] = []

  func relatedProjects(projectID: String) async throws -> [ProjectCardProperties] {
    try self.record("related:\(projectID)")
    if self.pauseRelated {
      return try await withCheckedThrowingContinuation { self.related.append($0) }
    }
    return []
  }

  func finishRelated(_ index: Int, error: ErrorEnvelope?) throws {
    guard self.related.indices.contains(index) else { XCTFail("Missing related request"); return }
    let continuation = try XCTUnwrap(self.related[index])
    self.related[index] = nil
    if let error { continuation.resume(throwing: error) }
    else { continuation.resume(returning: []) }
  }

  var calls: [String] = []
  var richTextValues: [Bool] = []
  var backingID: Int?
  var failAt: String?
  var pauseEnrollment = false
  var pauseProjects = false
  var pauseBase = false
  var projects: [CheckedContinuation<Project.ProjectPamphletData, Error>?] = []
  private var enrollment: CheckedContinuation<Void, Error>?
  private var baseContinuation: CheckedContinuation<Project, Error>?
  private var waits: [(String, Int, XCTestExpectation)] = []
  let extra = ProjectPageExtraProperties(extendedProjectProperties: ExtendedProjectProperties(
    environmentalCommitments: [], faqs: [], aiDisclosure: nil, risks: "risk",
    story: ProjectStoryElements(htmlViewElements: []), minimumPledgeAmount: 1, projectNotice: nil
  ), video: nil, flagging: true)

  private func record(_ call: String) throws {
    self.calls.append(call)
    for (name, count, expectation) in self.waits
      where name == call && self.calls.filter({ $0 == name }).count == count {
      expectation.fulfill()
    }
    if self.failAt == call { throw ErrorEnvelope.graphError("fixture failure") }
  }

  func waitFor(_ name: String, count: Int = 1) async {
    if self.calls.filter({ $0 == name }).count >= count { return }
    let expectation = XCTestExpectation(description: "\(name) admitted \(count)")
    self.waits.append((name, count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func enroll(token _: String, param _: Param) async throws {
    try self.record("enroll")
    if self.pauseEnrollment { try await withCheckedThrowingContinuation { self.enrollment = $0 } }
  }

  func project(param _: Param, richText: Bool) async throws -> Project.ProjectPamphletData {
    self.richTextValues.append(richText)
    try self.record("project")
    if self.pauseProjects { return try await withCheckedThrowingContinuation { self.projects.append($0) } }
    var project = Project.template
    project.rewardData.rewards = [Reward.noReward]
    return Project.ProjectPamphletData(project: project, backingId: self.backingID)
  }

  func backing(id _: Int) async throws -> ProjectAndBackingEnvelope {
    try self.record("backing")
    return ProjectAndBackingEnvelope(project: Project.template, backing: Backing.template)
  }

  func rewards(projectID _: Int) async throws -> [Reward] {
    try self.record("rewards")
    return [Reward.template]
  }

  func base(param _: Param) async throws -> Project {
    try self.record("base")
    if self.pauseBase { return try await withCheckedThrowingContinuation { self.baseContinuation = $0 } }
    return Project.template
  }

  func extras(param _: Param, richText _: Bool) async throws -> ProjectPageExtraProperties {
    try self.record("extras")
    return self.extra
  }

  func finishEnrollment() { self.enrollment?.resume(); self.enrollment = nil }
  func finishBase() { self.baseContinuation?.resume(returning: Project.template); self.baseContinuation = nil
  }

  func finishProject(_ index: Int, id: Int) throws {
    guard self.projects.indices.contains(index) else { XCTFail("Missing request"); return }
    let continuation = try XCTUnwrap(self.projects[index])
    self.projects[index] = nil
    var project = Project.template
    project.id = id
    project.rewardData.rewards = [Reward.noReward]
    continuation.resume(returning: Project.ProjectPamphletData(project: project, backingId: self.backingID))
  }

  func releaseAll() {
    for continuation in self.related { continuation?.resume(throwing: CancellationError()) }
    self.related.removeAll()
    self.enrollment?.resume(throwing: CancellationError()); self.enrollment = nil
    self.baseContinuation?.resume(throwing: CancellationError()); self.baseContinuation = nil
    for continuation in self.projects { continuation?.resume(throwing: CancellationError()) }
    self.projects.removeAll()
  }
}
