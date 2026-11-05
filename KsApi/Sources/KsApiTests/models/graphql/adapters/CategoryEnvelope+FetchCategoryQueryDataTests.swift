import Apollo
import GraphAPI
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class Category_FetchCategoryQueryDataTests: XCTestCase {
  func testNativeCategoryMappingReturnsNilForMissingCategory() throws {
    let data = try testGraphObject(jsonString: "{}") as GraphAPI.FetchCategoryQuery.Data
    XCTAssertNil(CategoryEnvelope.envelope(from: data))
  }

  @MainActor func testAsyncCategoryMockReturnsConfiguredValueAndPropagatesFailure() async throws {
    let service = MockService(fetchGraphCategoryResult: .success(CategoryEnvelope(node: .art)))
    let category = try await service.recommendationCategory(id: "art")
    XCTAssertEqual(category, .art)
    do {
      _ = try await MockService(fetchGraphCategoryResult: .failure(.couldNotParseJSON)).recommendationCategory(id: "art")
      XCTFail("Expected category error")
    } catch { XCTAssertTrue(error is ErrorEnvelope) }
  }

  func testFetchCategoryQueryData_Success() {
    guard let envelope = CategoryEnvelope.envelope(from: FetchCategoryQueryTemplate.valid.data)?.node else {
      XCTFail()

      return
    }

    XCTAssertEqual(envelope.analyticsName, "Comics")
    XCTAssertEqual(envelope.id, "Q2F0ZWdvcnktMw==")
    XCTAssertEqual(envelope.name, "Comics")
    XCTAssertEqual(envelope.totalProjectCount, 306)
    XCTAssertEqual(envelope.subcategories?.totalCount, 5)

    guard let firstSubcategory = envelope.subcategories?.nodes.first else {
      XCTFail("first subcategory should exist.")

      return
    }

    XCTAssertEqual(firstSubcategory.parentId, "Q2F0ZWdvcnktMw==")
    XCTAssertEqual(firstSubcategory.totalProjectCount, 23)
    XCTAssertEqual(firstSubcategory.id, "Q2F0ZWdvcnktMjQ5")
    XCTAssertEqual(firstSubcategory.name, "Anthologies")
    XCTAssertEqual(firstSubcategory.analyticsName, "Anthologies")
    XCTAssertEqual(firstSubcategory._parent?.id, "Q2F0ZWdvcnktMw==")
    XCTAssertEqual(firstSubcategory._parent?.name, "Comics")
    XCTAssertEqual(firstSubcategory._parent?.analyticsName, "Comics")
  }
}
