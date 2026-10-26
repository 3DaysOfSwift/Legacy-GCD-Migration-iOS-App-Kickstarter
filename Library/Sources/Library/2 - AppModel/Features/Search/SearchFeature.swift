import Foundation
import GraphAPI
import KsApi
import Prelude
import ReactiveSwift

public typealias SearchResult = GraphAPI.SearchQuery.Data.Projects.Node

/// Owns the current project request, result collection, count and pagination.
///
/// This first architecture checkpoint intentionally retains the legacy reactive
/// paging policy: a replacement query or page disposes the prior subscription.
/// It does not yet promise cancellation of the underlying Apollo request.
/// Filter selection/presentation extraction and awaitable execution are next.
@MainActor
public final class SearchFeature {
  public private(set) var projects: [SearchResult] = []
  public private(set) var totalCount = 0
  public private(set) var isLoading = false
  public private(set) var searchError: ErrorEnvelope?
  public private(set) var parameters: DiscoveryParams?

  // Compatibility events consumed by the existing UIKit ViewModel. The Feature
  // is the sole owner of request execution; observers never start another fetch.
  public let results: Signal<[SearchResult], Never>
  public let paginatedResults: Signal<[SearchResult], Never>
  public let resultCount: Signal<Int, Never>
  public let loading: Signal<Bool, Never>
  public let pageCount: Signal<Int, Never>

  private let (requestSignal, requestObserver) = Signal<DiscoveryParams, Never>.pipe()
  private let (nextPageSignal, nextPageObserver) = Signal<Void, Never>.pipe()
  private let subscriptions = CompositeDisposable()

  public init(provider: any SearchProjectsProvider) {
    let stats = MutableProperty(0)
    let options = MutableProperty<DiscoveryParams?>(nil)
    options <~ self.requestSignal

    var firstRequest = true
    let requestFirstPage: (DiscoveryParams)
      -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> = { parameters in
        SignalProducer<Void, ErrorEnvelope>(value: ()).switchMap {
          let request = provider.fetch(
            parameters: parameters,
            cursor: nil,
            debounce: !firstRequest
          )
          firstRequest = false
          return request.observe(on: UIScheduler())
        }
      }

    let (paginatedResults, loading, pageCount, errors) = paginate(
      requestFirstPageWith: self.requestSignal,
      requestNextPageWhen: self.nextPageSignal,
      clearOnNewRequest: false,
      skipRepeats: false,
      valuesFromEnvelope: { data -> [SearchResult] in
        stats.value = data.projects?.totalCount ?? 0
        return data.projects?.nodes?.compact() ?? []
      },
      cursorFromEnvelope: { data in
        guard let pageInfo = data.projects?.pageInfo else { return nil }
        return pageInfo.hasNextPage ? pageInfo.endCursor : nil
      },
      requestFromParams: requestFirstPage,
      requestFromCursor: { (cursor: String?) -> SignalProducer<GraphAPI.SearchQuery.Data, ErrorEnvelope> in
        guard let parameters = options.value, let cursor else { return .empty }
        return provider.fetch(parameters: parameters, cursor: cursor, debounce: false)
          .observe(on: UIScheduler())
      }
    )

    self.resultCount = stats.signal
    self.paginatedResults = paginatedResults
    self.loading = loading
    self.pageCount = pageCount
    self.results = Signal.merge(self.requestSignal.mapConst([]), paginatedResults).skipRepeats(==)

    // Reactive callbacks are a temporary compatibility boundary. UIScheduler
    // delivers synchronously on main when already there, preserving legacy
    // event ordering. Actor assertions make this boundary explicit.
    self.subscriptions += self.results.observe(on: UIScheduler()).observeValues { [weak self] projects in
      MainActor.assumeIsolated { self?.projects = projects }
    }
    self.subscriptions += self.resultCount.observe(on: UIScheduler()).observeValues { [weak self] count in
      MainActor.assumeIsolated { self?.totalCount = count }
    }
    self.subscriptions += loading.observe(on: UIScheduler()).observeValues { [weak self] loading in
      MainActor.assumeIsolated {
        self?.isLoading = loading
        if loading { self?.searchError = nil }
      }
    }
    self.subscriptions += errors.observe(on: UIScheduler()).observeValues { [weak self] error in
      MainActor.assumeIsolated { self?.searchError = error }
    }
  }

  /// Query replacement is intentionally latest-request-wins (BEH-S03).
  public func search(parameters: DiscoveryParams) {
    self.parameters = parameters
    self.searchError = nil
    self.requestObserver.send(value: parameters)
  }

  /// The paging pipeline decides whether a next cursor exists.
  public func loadNextPage() {
    self.nextPageObserver.send(value: ())
  }

  deinit {
    self.subscriptions.dispose()
  }
}
