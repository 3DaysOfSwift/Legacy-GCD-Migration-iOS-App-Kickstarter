@testable import Kickstarter_Framework
import Observation
import XCTest

@MainActor
final class VideoFeedObservationTests: XCTestCase {
  func testRepeatedBindingDoesNotMultiplyIndependentObservers() async {
    let state = FeedObservationState()
    var received: [VideoFeedObservation.Output] = []
    var notification = expectation(description: "first change")
    let observer = VideoFeedObservation(read: { state.read($0) }, changed: { received.append($0); notification.fulfill() })
    observer.start(); observer.start()
    state.items += 1
    await fulfillment(of: [notification], timeout: 2)
    notification = expectation(description: "other output")
    state.error += 1
    await fulfillment(of: [notification], timeout: 2)
    notification = expectation(description: "rearmed first output")
    state.items += 1
    await fulfillment(of: [notification], timeout: 2)
    observer.stop()
    XCTAssertEqual(received, [.items, .error, .items])
  }

  func testAcknowledgementAndNextFailureAreBothObserved() async {
    let state = FeedObservationState()
    var cleared = expectation(description: "acknowledgement")
    var failures = 0
    var ready = expectation(description: "first failure")
    let observer = VideoFeedObservation(read: { state.read($0) }, changed: { output in
      guard output == .saveError else { return }
      if state.saveError > 0 {
        failures += 1
        state.saveError = 0
        ready.fulfill()
      } else { cleared.fulfill() }
    })
    observer.start()
    state.saveError = 1
    await fulfillment(of: [ready, cleared], timeout: 2)
    ready = expectation(description: "next failure")
    cleared = expectation(description: "next acknowledgement")
    state.saveError = 2
    await fulfillment(of: [ready, cleared], timeout: 2)
    observer.stop()
    XCTAssertEqual(failures, 2)
  }

  func testStopRejectsQueuedEventsAndRestartHasOneSubscription() async {
    let state = FeedObservationState()
    var values: [Int] = []
    let delivered = expectation(description: "current event")
    let observer = VideoFeedObservation(read: { state.read($0) }, changed: { _ in values.append(state.items); delivered.fulfill() })
    observer.start()
    let old = observer.task
    state.items = 1
    observer.stop()
    observer.start()
    state.items = 2
    await old?.value
    await fulfillment(of: [delivered], timeout: 2)
    observer.stop()
    XCTAssertEqual(values, [2])
  }

  func testObservationDoesNotRetainOwnerWhileWaiting() async {
    let state = FeedObservationState()
    var observer: VideoFeedObservation? = VideoFeedObservation(read: { state.read($0) }, changed: { _ in XCTFail("Released observer delivered") })
    observer?.start()
    let task = observer?.task
    weak var released = observer
    observer = nil
    XCTAssertNil(released)
    state.items += 1
    await task?.value
  }

  func testDeferredActivationReplacementAndCancellationRejectLateTurns() async throws {
    let gate = FeedTurnGate()
    let activation = VideoFeedDeferredActivation(nextTurn: { await gate.wait() })
    var values: [String] = []
    activation.schedule { values.append("old") }
    let old = activation.task
    await gate.started(1, test: self)
    activation.schedule { values.append("new") }
    let current = activation.task
    await gate.started(2, test: self)
    gate.finish(0)
    await old?.value
    XCTAssertTrue(values.isEmpty)
    gate.finish(1)
    await current?.value
    XCTAssertEqual(values, ["new"])
    activation.schedule { XCTFail("Cancelled activation ran") }
    let cancelled = activation.task
    await gate.started(3, test: self)
    activation.cancel()
    gate.finish(2)
    await cancelled?.value
  }

  func testDeferredActivationDoesNotRetainReleasedOwner() async {
    let gate = FeedTurnGate()
    var activation: VideoFeedDeferredActivation? = VideoFeedDeferredActivation(nextTurn: { await gate.wait() })
    activation?.schedule { XCTFail("Released activation ran") }
    let task = activation?.task
    await gate.started(1, test: self)
    weak var released = activation
    activation = nil
    XCTAssertNil(released)
    gate.finish(0)
    await task?.value
  }
}

@Observable @MainActor
private final class FeedObservationState {
  var items = 0
  var fetchedItems = 0
  var error = 0
  var login = 0
  var saveError = 0
  func read(_ output: VideoFeedObservation.Output) {
    switch output {
    case .items: _ = self.items
    case .fetchedItems: _ = self.fetchedItems
    case .error: _ = self.error
    case .login: _ = self.login
    case .saveError: _ = self.saveError
    }
  }
}

@MainActor
private final class FeedTurnGate {
  private var continuations: [CheckedContinuation<Void, Never>?] = []
  private var arrival: XCTestExpectation?
  func wait() async {
    await withCheckedContinuation { continuation in
      self.continuations.append(continuation)
      self.arrival?.fulfill()
      self.arrival = nil
    }
  }
  func started(_ count: Int, test: XCTestCase) async {
    guard self.continuations.count < count else { return }
    let arrival = XCTestExpectation(description: "deferred turn admitted")
    self.arrival = arrival
    await test.fulfillment(of: [arrival], timeout: 2)
  }
  func finish(_ index: Int) {
    guard self.continuations.indices.contains(index) else { XCTFail("Missing turn"); return }
    self.continuations[index]?.resume()
    self.continuations[index] = nil
  }
}
