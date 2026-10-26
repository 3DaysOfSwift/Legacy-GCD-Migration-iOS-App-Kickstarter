import GraphAPI
import KsApi

/// Maps Search parameters to the cancellation-aware API operation.
@MainActor
public final class AsyncSearchProjectsProvider: SearchProjectsProvider {
  private let requestPage: @MainActor (DiscoveryParams, String?) async throws -> GraphAPI.SearchQuery.Data

  public init() {
    self.requestPage = { parameters, cursor in
      let query = GraphAPI.SearchQuery.from(discoveryParams: parameters, withCursor: cursor)
      return try await AppEnvironment.current.apiService.fetchSearchPage(query: query)
    }
  }

  internal init(
    requestPage: @escaping @MainActor (DiscoveryParams, String?) async throws -> GraphAPI.SearchQuery.Data
  ) {
    self.requestPage = requestPage
  }

  public func fetchPage(
    parameters: DiscoveryParams,
    cursor: String?
  ) async throws -> GraphAPI.SearchQuery.Data {
    try Task.checkCancellation()
    let page = try await self.requestPage(parameters, cursor)
    try Task.checkCancellation()
    return page
  }

}
