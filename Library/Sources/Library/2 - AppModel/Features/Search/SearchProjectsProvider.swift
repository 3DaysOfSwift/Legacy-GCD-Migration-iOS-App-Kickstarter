import GraphAPI
import KsApi

/// Search's transport boundary. Pagination and delivery timing belong to its Feature.
@MainActor
public protocol SearchProjectsProvider {
  func fetchPage(parameters: DiscoveryParams, cursor: String?) async throws -> GraphAPI.SearchQuery.Data
}
