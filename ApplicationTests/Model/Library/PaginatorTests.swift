@testable import Kickstarter_iOS
import XCTest

private struct ConcreteError: Error {}

final class PaginatorTests: XCTestCase {
  func testPaginatorResults_mapValues_unloaded_remainsUnloaded() {
    let results: PaginationResult<Int, Int, ConcreteError> = .unloaded

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(mapped, .unloaded)
  }

  func testPaginatorResults_mapValues_someLoaded_transformsValues() {
    let results: PaginationResult<Int, Int, ConcreteError> =
      .someLoaded(values: [1, 2, 3], cursor: 42, total: 6, page: 1)

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(
      mapped,
      .someLoaded(values: [2, 4, 6], cursor: 42, total: 6, page: 1),
      "Should transform values while preserving cursor, total and page"
    )
  }

  func testPaginatorResults_mapValues_allLoaded_transformsValues() {
    let results: PaginationResult<Int, Int, ConcreteError> =
      .allLoaded(values: [1, 2, 3], page: 2)

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(
      mapped,
      .allLoaded(values: [2, 4, 6], page: 2),
      "Should transform values while preserving page"
    )
  }

  func testPaginatorResults_mapValues_empty_remainsEmpty() {
    let results: PaginationResult<Int, Int, ConcreteError> = .empty

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(mapped, .empty)
  }

  func testPaginatorResults_mapValues_error_remainsError() {
    let error = ConcreteError()
    let results: PaginationResult<Int, Int, ConcreteError> = .error(error)

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(mapped, .error(error))
  }

  func testPaginatorResults_mapValues_loading_transformsUnderlyingValues() {
    let underlying: PaginationResult<Int, Int, ConcreteError> =
      .someLoaded(values: [1, 2, 3], cursor: 42, total: 6, page: 1)
    let results: PaginationResult<Int, Int, ConcreteError> =
      .loading(previous: underlying)

    let mapped = results.mapValues { values in
      values.map { $0 * 2 }
    }

    XCTAssertEqual(
      mapped,
      .loading(previous: .someLoaded(values: [2, 4, 6], cursor: 42, total: 6, page: 1)),
      "Should transform values in the underlying state while preserving loading status"
    )
  }
}
