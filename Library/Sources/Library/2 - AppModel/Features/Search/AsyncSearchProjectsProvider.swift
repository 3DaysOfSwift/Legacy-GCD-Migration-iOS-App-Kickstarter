import GraphAPI
import KsApi
import ReactiveSwift

/// Async transport with a temporary reactive edge for the unchanged paging and
/// analytics pipeline. Subscription disposal owns and cancels its request Task.
/// No second request is made by observing the returned producer.
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

  public func fetch(
    parameters: DiscoveryParams,
    cursor: String?,
    debounce: Bool
  ) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> {
    let request = SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> { observer, lifetime in
      let task = Task { @MainActor in
        do {
          let data = try await self.fetchPage(parameters: parameters, cursor: cursor)
          try Task.checkCancellation()
          observer.send(value: data)
          observer.sendCompleted()
        } catch is CancellationError {
          observer.sendInterrupted()
        } catch let error as ErrorEnvelope {
          observer.send(error: error)
        } catch {
          observer.send(error: .couldNotParseJSON)
        }
      }
      lifetime.observeEnded { task.cancel() }
    }
    guard cursor == nil else { return request }
    // Legacy debounce delays results, not request admission. Preserve that
    // observable contract during the transport conversion.
    return request.ksr_debounce(
      debounce ? AppEnvironment.current.debounceInterval : .seconds(0),
      on: AppEnvironment.current.scheduler
    )
  }
}
