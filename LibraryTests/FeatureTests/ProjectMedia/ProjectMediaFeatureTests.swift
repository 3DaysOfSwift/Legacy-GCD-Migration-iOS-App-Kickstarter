import Foundation
import ReactiveSwift
@testable import KsApi
@testable import Library
@testable import LibraryTestHelpers
import XCTest

@MainActor
final class ProjectMediaFeatureTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  func testDuplicateEventSharesButStartAndCompletionRemainIndependent() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID()
    var received: [Bool] = []
    let observation = feature.completions.observeValues { received.append($0.1) }
    defer { observation?.dispose() }
    let start = feature.requestReport(route: route, project: Project.template, completed: false)
    let duplicate = feature.requestReport(route: route, project: Project.template, completed: false)
    await provider.waitForRequests(1)
    let completed = feature.requestReport(route: route, project: Project.template, completed: true)
    await provider.waitForRequests(2)
    XCTAssertEqual(provider.events, [false, true])
    XCTAssertFalse(start.isCancelled)
    try provider.finish(1)
    await completed.value
    try provider.finish(0)
    await start.value
    await duplicate.value
    XCTAssertEqual(received, [true, false])
  }

  func testReleaseCancelsOnlyItsRouteAndDoesNotPublishLateSuccess() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    let route = UUID(), other = UUID()
    var received: [UUID] = []
    let observation = feature.completions.observeValues { received.append($0.0) }
    defer { observation?.dispose() }
    let first = feature.requestReport(route: route, project: Project.template, completed: false)
    await provider.waitForRequests(1)
    let second = feature.requestReport(route: other, project: Project.template, completed: false)
    await provider.waitForRequests(2)
    feature.release(route: route)
    XCTAssertTrue(first.isCancelled)
    XCTAssertFalse(second.isCancelled)
    try provider.finish(0)
    try provider.finish(1)
    await first.value
    await second.value
    XCTAssertEqual(received, [other])
  }

  func testAccountChangeSuppressesCompletionAndCancelledCallerDoesNotStart() async throws {
    let provider = ControlledMediaProvider()
    defer { provider.releaseAll() }
    let feature = ProjectMediaFeature(makeProvider: { provider })
    var received = 0
    let observation = feature.completions.observeValues { _ in received += 1 }
    defer { observation?.dispose() }
    let pending = feature.requestReport(route: UUID(), project: Project.template, completed: true)
    await provider.waitForRequests(1)
    AppEnvironment.pushEnvironment(currentUser: .template)
    defer { AppEnvironment.popEnvironment() }
    try provider.finish(0)
    await pending.value
    let cancelled = Task { await feature.report(route: UUID(), project: Project.template, completed: false) }
    cancelled.cancel()
    await cancelled.value
    XCTAssertEqual(provider.events, [true])
    XCTAssertEqual(received, 0)
  }

  func testFailedCounterDoesNotPublishSuccessOrRetry() async {
    let feature = ProjectMediaFeature(makeProvider: {
      AsyncProjectMediaProvider(service: MockService(incrementVideoStartError: .couldNotParseJSON))
    })
    var successes = 0
    let observation = feature.completions.observeValues { _ in successes += 1 }
    defer { observation?.dispose() }
    await feature.report(route: UUID(), project: Project.template, completed: false)
    XCTAssertEqual(successes, 0)
  }
}

@MainActor
private final class ControlledMediaProvider: ProjectMediaProvider {
  var events: [Bool] = []
  private var pending: [CheckedContinuation<VoidEnvelope, Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []
  func report(project _: any HasProjectWebURL, completed: Bool) async throws -> VoidEnvelope {
    self.events.append(completed)
    return try await withCheckedThrowingContinuation { continuation in
      self.pending.append(continuation)
      for (count, expectation) in self.waits where count == self.events.count { expectation.fulfill() }
    }
  }

  func waitForRequests(_ count: Int) async {
    if self.events.count >= count { return }
    let expectation = XCTestExpectation(description: "Media event admission")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int) throws {
    guard self.pending.indices.contains(index) else { XCTFail("Missing event"); return }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(returning: VoidEnvelope())
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}
