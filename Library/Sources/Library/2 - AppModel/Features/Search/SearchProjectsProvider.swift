import GraphAPI
import KsApi
import ReactiveSwift

/// Transport seam for Search's architecture pass. The following execution pass
/// will replace this reactive contract with a cancellation-aware async operation.
@MainActor
public protocol SearchProjectsProvider {
  func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope>
}

/// Keeps the existing API selection and test scheduler semantics during extraction.
/// Resolve the environment at request time so account/demo changes are respected.
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
