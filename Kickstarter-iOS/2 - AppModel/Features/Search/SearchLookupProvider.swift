import KsApi

/// Replaceable I/O boundary; SearchFeature owns lookup state and overlap policy.
@MainActor
public protocol SearchLookupProvider {
  var cachedCategories: [KsApi.Category]? { get }
  func cache(categories: [KsApi.Category])
  func fetchCategories() async throws -> [KsApi.Category]
  func fetchDefaultLocations() async throws -> [Location]
  func fetchLocations(query: String) async throws -> [Location]
}

/// Uses the existing shared category cache and cancellation-aware API methods.
/// Does not introduce a second cache or start work during construction.
@MainActor
public final class AsyncSearchLookupProvider: SearchLookupProvider {
  public init() {}

  public var cachedCategories: [KsApi.Category]? {
    AppEnvironment.current.cache[KSCache.ksr_discoveryFiltersCategories] as? [KsApi.Category]
  }

  public func cache(categories: [KsApi.Category]) {
    AppEnvironment.current.cache[KSCache.ksr_discoveryFiltersCategories] = categories
  }

  public func fetchCategories() async throws -> [KsApi.Category] {
    try await AppEnvironment.current.apiService.fetchSearchCategories().rootCategories
  }

  public func fetchDefaultLocations() async throws -> [Location] {
    try await AppEnvironment.current.apiService.fetchSearchDefaultLocations()
  }

  public func fetchLocations(query: String) async throws -> [Location] {
    try await AppEnvironment.current.apiService.fetchSearchLocations(term: query)
  }
}
