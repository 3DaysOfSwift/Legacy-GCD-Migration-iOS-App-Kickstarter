import Foundation
@testable import Library
import XCTest

@MainActor
final class MainActorNotificationObservationTests: XCTestCase {
  private let name = Notification.Name("MainActorNotificationObservationTests.event")

  func testMainActorDeliveryPreservesSynchronousOrderingAndPayload() {
    let center = NotificationCenter()
    var values: [Int] = []
    let observer = MainActorNotificationObservation(center: center, name: self.name) {
      if let value = $0.userInfo?["value"] as? Int { values.append(value) }
    }
    center.post(name: self.name, object: nil, userInfo: ["value": 1])
    center.post(name: self.name, object: nil, userInfo: ["value": 2])
    XCTAssertEqual(values, [1, 2])
    withExtendedLifetime(observer) {}
  }

  func testHandlerCanCancelItsOwnRegistration() {
    let center = NotificationCenter()
    var calls = 0
    var observer: MainActorNotificationObservation?
    observer = .init(center: center, name: self.name) { _ in
      calls += 1
      observer?.cancel()
    }
    center.post(name: self.name, object: nil)
    center.post(name: self.name, object: nil)
    XCTAssertEqual(calls, 1)
    observer = nil
  }

  func testReleaseByAnotherActorRemovesRegistration() async {
    let center = NotificationCenter()
    var calls = 0
    var observer: MainActorNotificationObservation? = .init(center: center, name: self.name) { _ in
      calls += 1
    }
    weak var released = observer
    let owner = ObservationOwner(observer)
    observer = nil
    await owner.release()
    XCTAssertNil(released)
    center.post(name: self.name, object: nil)
    XCTAssertEqual(calls, 0)
  }

  func testCancelAndReleaseRemoveRegistration() {
    let center = NotificationCenter()
    var calls = 0
    var observer: MainActorNotificationObservation? = .init(center: center, name: self.name) { _ in
      calls += 1
    }
    weak var released = observer
    center.post(name: self.name, object: nil)
    XCTAssertEqual(calls, 1)
    observer?.cancel()
    observer?.cancel()
    center.post(name: self.name, object: nil)
    XCTAssertEqual(calls, 1)
    observer = nil
    XCTAssertNil(released)

    var other: MainActorNotificationObservation? = .init(center: center, name: self.name) { _ in
      calls += 1
    }
    weak var releasedOther = other
    other = nil
    XCTAssertNil(releasedOther)
    center.post(name: self.name, object: nil)
    XCTAssertEqual(calls, 1)
  }
}

private actor ObservationOwner {
  private var observation: MainActorNotificationObservation?
  init(_ observation: MainActorNotificationObservation?) { self.observation = observation }
  func release() { self.observation = nil }
}
