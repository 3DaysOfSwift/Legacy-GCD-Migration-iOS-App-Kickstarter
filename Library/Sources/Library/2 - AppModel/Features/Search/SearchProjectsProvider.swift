import GraphAPI
import KsApi
import ReactiveSwift

/// Temporary compatibility edge for the legacy pagination/analytics graph.
/// The live AsyncSearchProjectsProvider performs cancellation-aware async work.
@MainActor
public protocol SearchProjectsProvider {
  func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope>
}

/// Historical adapter retained for the synchronous baseline regression suites.
/// AppModel uses AsyncSearchProjectsProvider; async integration tests exercise it.
@MainActor
public final class LegacySearchProjectsProvider: SearchProjectsProvider {
  public init() {}

  public func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> {
    let query = GraphAPI.SearchQuery.from(discoveryParams: parameters, withCursor: cursor)
    let request = AppEnvironment.current.apiService.fetch(query: query)
    guard cursor == nil else { return request }
    return request.ksr_debounce(
      debounce ? AppEnvironment.current.debounceInterval : .seconds(0),
      on: AppEnvironment.current.scheduler
    )
  }
}
