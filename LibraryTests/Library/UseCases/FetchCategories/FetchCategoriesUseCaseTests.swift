@testable import KsApi
@testable import KsApiTestHelpers
import Library
@testable import LibraryTestHelpers
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
final class FetchCategoriesUseCaseTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }

  private var useCase: FetchCategoriesUseCase!
  private let categories = TestObserver<[KsApi.Category], Never>()
  private let loadingIndicatorIsVisible = TestObserver<Bool, Never>()

  override func setUp() async throws {
    try await super.setUp()

    self.useCase = FetchCategoriesUseCase()
    self.useCase.dataOutputs.categories.observe(self.categories.observer)
    self.useCase.uiOutputs.loadingIndicatorIsVisible.observe(self.loadingIndicatorIsVisible.observer)
  }

  override func tearDown() async throws {
    try await super.tearDown()

    AppEnvironment.current.cache.removeAllObjects()
  }

  func testEquivalentLoadsShareOneRequest() async {
    var calls = 0
    let loader = FetchCategoriesUseCase(fetch: { calls += 1; return [.art] })
    let first = loader.start()
    let second = loader.start()
    await first.value
    await second.value
    XCTAssertEqual(calls, 1)
  }

  func testReleaseCancelsBeforeRequestStarts() async {
    var calls = 0
    var loader: FetchCategoriesUseCase? = FetchCategoriesUseCase(fetch: { calls += 1; return [.art] })
    let pending = loader?.start()
    loader = nil
    await pending?.value
    XCTAssertEqual(calls, 0)
  }

  func testReplacementCacheRejectsObsoleteResponse() async {
    let loader = FetchCategoriesUseCase(fetch: { [.art] })
    let observed = TestObserver<[KsApi.Category], Never>()
    loader.categories.observe(observed.observer)
    let pending = loader.start()
    await withEnvironment(cache: KSCache()) {
      await pending.value
      observed.assertDidNotEmitValue()
      XCTAssertNil(AppEnvironment.current.cache[KSCache.ksr_discoveryFiltersCategories])
    }
  }

  func test_emptyCache_fetchesCategories_AndShowsLoadingIndicator() async {
    self.categories.assertDidNotEmitValue()
    self.loadingIndicatorIsVisible.assertDidNotEmitValue()

    let response = RootCategoriesEnvelope(rootCategories: [
      .art,
      .filmAndVideo,
      .illustration,
      .documentary
    ])

    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(response))) {
      self.useCase.start()

      self.loadingIndicatorIsVisible.assertLastValue(true, "Loading should start when categories are loading")
      self.categories.assertDidNotEmitValue()

      await self.useCase.load()

      XCTAssertEqual(self.categories.lastValue?.count, 4, "Categories in root category response should load")
      self.loadingIndicatorIsVisible.assertLastValue(false, "Loading should stop when categories are loaded")
    }
  }

  func test_cachedCategories_returnsCachedCategories() async {
    self.categories.assertDidNotEmitValue()
    self.loadingIndicatorIsVisible.assertDidNotEmitValue()

    let cachedCategories = [
      Category.art,
      Category.filmAndVideo,
      Category.games
    ]

    AppEnvironment.current.cache[KSCache.ksr_discoveryFiltersCategories] = cachedCategories

    self.useCase.start()

    self.loadingIndicatorIsVisible.assertDidNotEmitValue()
    self.categories.assertDidEmitValue()
    XCTAssertEqual(self.categories.lastValue?.count, 3, "Categories should load directly from cache")
  }

  func test_fetchError_loadsCategories_WhenInitialSignalSentAgain() async {
    self.categories.assertDidNotEmitValue()
    self.loadingIndicatorIsVisible.assertDidNotEmitValue()

    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .failure(
      ErrorEnvelope
        .couldNotParseErrorEnvelopeJSON
    ))) {
      self.useCase.start()

      self.loadingIndicatorIsVisible.assertLastValue(true, "Loading should start when categories are loading")
      self.categories.assertDidNotEmitValue()

      await self.useCase.load()

      self.categories.assertDidNotEmitValue()
      self.loadingIndicatorIsVisible.assertLastValue(false)
    }

    let response = RootCategoriesEnvelope(rootCategories: [
      .art,
      .filmAndVideo,
      .illustration,
      .documentary
    ])

    await withEnvironment(apiService: MockService(fetchGraphCategoriesResult: .success(response))) {
      self.useCase.start()

      self.loadingIndicatorIsVisible.assertLastValue(true, "Loading should start when categories are loading")
      self.categories.assertDidNotEmitValue()

      await self.useCase.load()

      self.categories.assertDidEmitValue()
      self.loadingIndicatorIsVisible.assertLastValue(false)
    }
  }
}
