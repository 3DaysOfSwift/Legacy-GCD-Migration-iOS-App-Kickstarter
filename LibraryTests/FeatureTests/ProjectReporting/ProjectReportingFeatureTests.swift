import GraphAPI
@testable import KsApi
@testable import Library
import XCTest

@MainActor
final class ProjectReportingFeatureTests: XCTestCase {
  private var provider: ControlledReportingProvider!
  private var session: SessionFeature!
  private var feature: ProjectReportingFeature!

  override func setUp() async throws {
    try await super.setUp()
    self.provider = ControlledReportingProvider()
    self.session = SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) })
    let provider = self.provider!
    self.feature = ProjectReportingFeature(sessionFeature: self.session, makeProvider: { provider })
  }

  override func tearDown() async throws {
    self.provider.optionsGate.releaseAll()
    self.provider.emailGate.releaseAll()
    self.provider.submitGate.releaseAll()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  private func draft(_ text: String = "Report") -> ProjectReportingFeature.Draft {
    .init(projectID: "123", kind: .guidelinesViolation, details: text)
  }

  func testDuplicatePendingSubmissionsShareAndDifferentDraftsStayOrdered() async throws {
    let context = self.feature.context
    let first = try self.feature.submit(self.draft(), context: context)
    let duplicate = try self.feature.submit(self.draft(), context: context)
    let second = try self.feature.submit(self.draft("Changed"), context: context)
    await self.provider.submitGate.waitFor(1)
    XCTAssertEqual(self.provider.drafts, [self.draft()])
    try self.provider.submitGate.finish(0, .success(()))
    try await first.value
    try await duplicate.value
    await self.provider.submitGate.waitFor(2)
    XCTAssertEqual(self.provider.drafts, [self.draft(), self.draft("Changed")])
    try self.provider.submitGate.finish(1, .success(()))
    try await second.value
  }

  func testFailureAllowsExplicitRetryWithoutAutomaticResubmission() async throws {
    let first = try self.feature.submit(self.draft(), context: self.feature.context)
    await self.provider.submitGate.waitFor(1)
    try self.provider.submitGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { try await first.value; XCTFail("Expected failure") } catch {}
    await self.feature.waitForOperations()
    XCTAssertEqual(self.provider.submitGate.count, 1)
    let retry = try self.feature.submit(self.draft(), context: self.feature.context)
    await self.provider.submitGate.waitFor(2)
    try self.provider.submitGate.finish(1, .success(()))
    try await retry.value
  }

  func testSessionReplacementSuppressesCompletionAndQueuedWrite() async throws {
    let context = self.feature.context
    let first = try self.feature.submit(self.draft(), context: context)
    let second = try self.feature.submit(self.draft("Second"), context: context)
    await self.provider.submitGate.waitFor(1)
    self.session.sessionChanged()
    try self.provider.submitGate.finish(0, .success(()))
    for task in [first, second] {
      do { try await task.value; XCTFail("Obsolete session") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
    XCTAssertEqual(self.provider.submitGate.count, 1)
    XCTAssertThrowsError(try self.feature.submit(self.draft(), context: context))
  }

  func testEmptyInputIsRejectedBeforeRequest() throws {
    XCTAssertThrowsError(try self.feature.submit(self.draft(""), context: self.feature.context))
    XCTAssertEqual(self.provider.submitGate.count, 0)
  }

  func testCancelledOptionsReadCannotPublishLateResponse() async throws {
    let vm = ReportProjectInfoViewModel(feature: self.feature)
    let task = vm.viewDidLoad()
    await self.provider.optionsGate.waitFor(1)
    vm.stop()
    try self.provider.optionsGate.finish(0, .success([.init(id: "report", title: "Report", subtitle: "Details")]))
    await task.value
    XCTAssertTrue(vm.listItems.isEmpty)
    XCTAssertFalse(vm.isLoading)
  }

  func testRepeatedAppearanceSharesOptionsRequestAndCanReloadAfterCompletion() async throws {
    let vm = ReportProjectInfoViewModel(feature: self.feature)
    let first = vm.viewDidLoad()
    let second = vm.viewDidLoad()
    await self.provider.optionsGate.waitFor(1)
    try self.provider.optionsGate.finish(0, .success([]))
    await first.value
    await second.value
    XCTAssertEqual(self.provider.optionsGate.count, 1)
    let reload = vm.viewDidLoad()
    await self.provider.optionsGate.waitFor(2)
    try self.provider.optionsGate.finish(1, .success([]))
    await reload.value
  }

  func testOldSessionReadFailuresBecomeCancellation() async throws {
    let context = self.feature.context
    let options = Task { try await self.feature.options(context: context) }
    let email = Task { try await self.feature.email(context: context) }
    await self.provider.optionsGate.waitFor(1)
    await self.provider.emailGate.waitFor(1)
    self.session.sessionChanged()
    try self.provider.optionsGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try self.provider.emailGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    do { _ = try await options.value; XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError) }
    do { _ = try await email.value; XCTFail("Expected cancellation") }
    catch { XCTAssertTrue(error is CancellationError) }
  }

  func testEmailFromPreviousSessionIsSuppressed() async throws {
    let vm = ReportProjectFormViewModel(feature: self.feature)
    let task = vm.viewDidLoad()
    await self.provider.emailGate.waitFor(1)
    self.session.sessionChanged()
    try self.provider.emailGate.finish(0, .success("old@example.com"))
    await task.value
    XCTAssertNil(vm.retrievedEmail)
  }

  func testDismissedFormDoesNotCancelAdmittedReportOrDisplaySuccess() async throws {
    let vm = self.form()
    let task = try XCTUnwrap(vm.didTapSave())
    await self.provider.submitGate.waitFor(1)
    vm.stop()
    try self.provider.submitGate.finish(0, .success(()))
    await task.value
    await self.feature.waitForOperations()
    XCTAssertFalse(vm.submitSuccess)
    XCTAssertNil(vm.bannerMessage)
    XCTAssertEqual(self.provider.submitGate.count, 1)
  }

  func testFormSuccessAndDuplicateTap() async throws {
    let vm = self.form()
    let first = try XCTUnwrap(vm.didTapSave())
    let second = try XCTUnwrap(vm.didTapSave())
    XCTAssertTrue(vm.saveButtonLoading)
    XCTAssertFalse(vm.saveButtonEnabled)
    await self.provider.submitGate.waitFor(1)
    try self.provider.submitGate.finish(0, .success(()))
    await first.value
    await second.value
    XCTAssertTrue(vm.submitSuccess)
    XCTAssertFalse(vm.saveButtonLoading)
    XCTAssertFalse(vm.saveButtonEnabled)
    XCTAssertNotNil(vm.bannerMessage)
    XCTAssertNil(vm.didTapSave())
  }

  func testFormFailureRestoresRetryAndMissingContextDoesNotCrash() async throws {
    let vm = self.form()
    vm.projectID = nil
    XCTAssertNil(vm.didTapSave())
    XCTAssertNotNil(vm.bannerMessage)
    XCTAssertEqual(self.provider.submitGate.count, 0)
    vm.projectID = "123"
    let task = try XCTUnwrap(vm.didTapSave())
    await self.provider.submitGate.waitFor(1)
    try self.provider.submitGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await task.value
    XCTAssertFalse(vm.submitSuccess)
    XCTAssertFalse(vm.saveButtonLoading)
    XCTAssertTrue(vm.saveButtonEnabled)
  }

  private func form() -> ReportProjectFormViewModel {
    let vm = ReportProjectFormViewModel(feature: self.feature)
    vm.projectID = "123"
    vm.projectFlaggingKind = .guidelinesViolation
    vm.detailsText = "Report"
    return vm
  }
}

@MainActor
private final class ControlledReportingProvider: ProjectReportingProvider {
  let optionsGate = AccountRequestGate<[ReportProjectInfoListItem]>()
  let emailGate = AccountRequestGate<String?>()
  let submitGate = AccountRequestGate<Void>()
  private(set) var drafts: [ProjectReportingFeature.Draft] = []
  func options() async throws -> [ReportProjectInfoListItem] { try await self.optionsGate.request() }
  func email() async throws -> String? { try await self.emailGate.request() }
  func submit(_ draft: ProjectReportingFeature.Draft) async throws {
    self.drafts.append(draft)
    try await self.submitGate.request()
  }
}
