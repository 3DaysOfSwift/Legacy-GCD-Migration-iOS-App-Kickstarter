import Apollo
@testable import KsApi
@testable import KsApiTestHelpers
import XCTest

final class Category_FetchCategoryQueryDataTests: XCTestCase {
  func testNativeCategoryMappingMatchesExistingEnvelope() throws {
    let data = FetchCategoryQueryTemplate.valid.data
    let native = try XCTUnwrap(CategoryEnvelope.envelope(from: data))
    let existing = try XCTUnwrap(MockGraphQLClient.shared.client.data(from: CategoryEnvelope.envelopeProducer(from: data)))
    XCTAssertEqual(native.node, existing.node)
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
    let producer = CategoryEnvelope.envelopeProducer(from: FetchCategoryQueryTemplate.valid.data)
    guard let envelope = MockGraphQLClient.shared.client.data(from: producer)?.node else {
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
