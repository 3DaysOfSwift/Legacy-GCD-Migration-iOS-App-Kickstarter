@testable import Library
import UIKit
import XCTest

@MainActor
final class DeferredRefreshControlTests: XCTestCase {
  func testEndBeforeDelayedStartRejectsLateCompletion() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let control = DeferredRefreshControl(delay: { try await gate.request() })
    let request = control.beginRefreshingAfterLayout()
    await gate.waitFor(1)
    control.endRefreshing()
    try gate.finish(0, .success(()))
    await request.value
    XCTAssertFalse(control.isRefreshing)
  }

  func testRepeatedStartSharesAndReplacementCanRefresh() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let control = DeferredRefreshControl(delay: { try await gate.request() })
    let old = control.beginRefreshingAfterLayout()
    let shared = control.beginRefreshingAfterLayout()
    await gate.waitFor(1)
    control.endRefreshing()
    let current = control.beginRefreshingAfterLayout()
    await gate.waitFor(2)
    try gate.finish(0, .success(())); await old.value; await shared.value
    XCTAssertFalse(control.isRefreshing)
    try gate.finish(1, .success(())); await current.value
    XCTAssertTrue(control.isRefreshing)
    XCTAssertEqual(gate.count, 2)
    control.endRefreshing()
  }

  func testRemovalAndReleaseCancelPendingStart() async throws {
    let gate = AccountRequestGate<Void>()
    defer { gate.releaseAll() }
    let scroll = UIScrollView()
    var control: DeferredRefreshControl? = DeferredRefreshControl(delay: { try await gate.request() })
    scroll.addSubview(try XCTUnwrap(control))
    let removed = try XCTUnwrap(control).beginRefreshingAfterLayout()
    await gate.waitFor(1)
    control?.removeFromSuperview()
    try gate.finish(0, .success(())); await removed.value
    XCTAssertEqual(control?.isRefreshing, false)
    let released = try XCTUnwrap(control).beginRefreshingAfterLayout()
    await gate.waitFor(2)
    weak var weakControl = control
    control = nil
    XCTAssertNil(weakControl)
    try gate.finish(1, .success(())); await released.value
    XCTAssertTrue(released.isCancelled)
  }
}
