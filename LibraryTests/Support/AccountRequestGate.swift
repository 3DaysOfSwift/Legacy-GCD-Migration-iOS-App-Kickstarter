import Foundation
import XCTest

/// Controlled suspension with bounded admission waits. Tests explicitly release
/// all continuations on exit, including assertion/setup failures.
@MainActor
final class AccountRequestGate<Value> {
  private(set) var count = 0
  private var pending: [CheckedContinuation<Value, Error>?] = []
  private var waits: [(Int, XCTestExpectation)] = []

  func request() async throws -> Value {
    self.count += 1
    return try await withCheckedThrowingContinuation { continuation in
      self.pending.append(continuation)
      for (count, expectation) in self.waits where count == self.count { expectation.fulfill() }
    }
  }

  func waitFor(_ count: Int) async {
    if self.count >= count { return }
    let expectation = XCTestExpectation(description: "Account request admission")
    self.waits.append((count, expectation))
    let result = await XCTWaiter().fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(result, .completed)
  }

  func finish(_ index: Int, _ result: Result<Value, Error>) throws {
    guard self.pending.indices.contains(index) else { XCTFail("Missing request"); return }
    let continuation = try XCTUnwrap(self.pending[index])
    self.pending[index] = nil
    continuation.resume(with: result)
  }

  func releaseAll() {
    for continuation in self.pending { continuation?.resume(throwing: CancellationError()) }
    self.pending.removeAll()
  }
}
