@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import XCTest

@MainActor
final class ActivityFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private func session() -> SessionFeature {
    SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }, currentUser: { .template })
  }

  private func page(_ ids: [Int], cursor: String = "next") -> ActivityEnvelope {
    ActivityEnvelope(
      activities: ids.map { Activity.template |> Activity.lens.id .~ $0 },
      urls: .init(api: .init(moreActivities: cursor))
    )
  }

  func testHistorySharingPaginationSortingEmptyAndRetry() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = ActivityFeature(sessionFeature: self.session(), makeProvider: { provider }, sleep: { _ in })
    let first = feature.requestPage(), duplicate = feature.requestPage()
    await provider.pages.waitFor(1)
    try provider.pages.finish(0, .success(self.page([1, 3])))
    await first?.value; await duplicate?.value
    XCTAssertEqual(feature.activities.map(\.id), [3, 1])
    let next = feature.requestPage(next: true)
    await provider.pages.waitFor(2)
    try provider.pages.finish(1, .success(self.page([2, 3])))
    await next?.value
    XCTAssertEqual(feature.activities.map(\.id), [3, 2, 1])
    XCTAssertEqual(provider.cursors, [nil, "next"])
    let failed = feature.requestPage()
    await provider.pages.waitFor(3)
    try provider.pages.finish(2, .failure(ErrorEnvelope.couldNotParseJSON))
    await failed?.value
    XCTAssertNotNil(feature.error)
    XCTAssertEqual(feature.activities.count, 3)
    let empty = feature.requestPage()
    await provider.pages.waitFor(4)
    try provider.pages.finish(3, .success(self.page([])))
    await empty?.value
    XCTAssertTrue(feature.activities.isEmpty)
    XCTAssertNil(feature.error)
    XCTAssertNil(feature.requestPage(next: true))
  }

  func testResetRejectsLatePagesAndSurveys() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let session = self.session()
    let feature = ActivityFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    let page = feature.requestPage(), survey = feature.requestSurveys()
    await provider.pages.waitFor(1); await provider.surveysGate.waitFor(1)
    session.sessionChanged()
    feature.reset()
    try provider.pages.finish(0, .success(self.page([1])))
    try provider.surveysGate.finish(0, .success([.template]))
    await page?.value; await survey?.value
    XCTAssertTrue(feature.activities.isEmpty)
    XCTAssertTrue(feature.surveys.isEmpty)
    XCTAssertFalse(feature.isLoading)
  }

  func testSurveyFailurePreservesDataAndIndependentPageCanComplete() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = ActivityFeature(sessionFeature: self.session(), makeProvider: { provider }, sleep: { _ in })
    let survey = feature.requestSurveys(), duplicate = feature.requestSurveys()
    let page = feature.requestPage()
    await provider.surveysGate.waitFor(1); await provider.pages.waitFor(1)
    try provider.surveysGate.finish(0, .success([.template]))
    try provider.pages.finish(0, .success(self.page([1])))
    await survey?.value; await duplicate?.value; await page?.value
    let failed = feature.requestSurveys()
    await provider.surveysGate.waitFor(2)
    try provider.surveysGate.finish(1, .failure(ErrorEnvelope.couldNotParseJSON))
    await failed?.value
    XCTAssertEqual(feature.surveys.count, 1)
    XCTAssertNotNil(feature.surveyError)
    XCTAssertEqual(feature.activities.count, 1)
  }

  func testLoggedOutRequestsDoNotReachProvider() async {
    let provider = ControlledActivityProvider()
    let session = SessionFeature(
      makeProvider: { AsyncSessionProvider(service: MockService()) },
      currentUser: { nil }
    )
    let feature = ActivityFeature(sessionFeature: session, makeProvider: { provider }, sleep: { _ in })
    await feature.refresh()
    XCTAssertNil(feature.requestSurveys())
    XCTAssertEqual(provider.pages.count, 0)
    XCTAssertEqual(provider.surveysGate.count, 0)
  }

  func testResetRejectsLateErrorsWithoutChangingSession() async throws {
    let provider = ControlledActivityProvider()
    defer { provider.releaseAll() }
    let feature = ActivityFeature(sessionFeature: self.session(), makeProvider: { provider }, sleep: { _ in })
    let page = feature.requestPage(), survey = feature.requestSurveys()
    await provider.pages.waitFor(1)
    await provider.surveysGate.waitFor(1)
    feature.reset()
    try provider.pages.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    try provider.surveysGate.finish(0, .failure(ErrorEnvelope.couldNotParseJSON))
    await page?.value
    await survey?.value
    XCTAssertNil(feature.error)
    XCTAssertNil(feature.surveyError)
    XCTAssertFalse(feature.isLoading)
  }
}

@MainActor
private final class ControlledActivityProvider: ActivityProvider {
  let pages = AccountRequestGate<ActivityEnvelope>()
  let surveysGate = AccountRequestGate<[SurveyResponse]>()
  var cursors: [String?] = []
  func page(cursor: String?) async throws -> ActivityEnvelope { self.cursors
    .append(cursor); return try await self.pages.request()
  }

  func surveys() async throws -> [SurveyResponse] { try await self.surveysGate.request() }
  func releaseAll() { self.pages.releaseAll(); self.surveysGate.releaseAll() }
}
