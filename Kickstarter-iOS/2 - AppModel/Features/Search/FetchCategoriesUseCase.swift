import Foundation
import KsApi

/// Owns Discovery's category request. Equivalent loads share work; release cancels it.
@MainActor
public final class FetchCategoriesUseCase {
  var onCategories: (([KsApi.Category]) -> Void)?
  var onLoading: ((Bool) -> Void)?
  private var request: Task<Void, Never>?

  private let fetch: (@MainActor () async throws -> [KsApi.Category])?

  public init(fetch: (@MainActor () async throws -> [KsApi.Category])? = nil) {
    self.fetch = fetch
  }

  deinit { self.request?.cancel() }

  public func load() async {
    await self.start().value
  }

  @discardableResult
  public func start() -> Task<Void, Never> {
    if let request = self.request { return request }
    let environment: Environment = AppEnvironment.current
    let cache = environment.cache
    if let cached = cache[KSCache.ksr_discoveryFiltersCategories] as? [KsApi.Category] {
      self.onCategories?(cached)
      if !cached.isEmpty { return Task {} }
    }
    let service = environment.apiService
    let fetch = self.fetch
    let delay = environment.apiDelayInterval.searchDelaySeconds
    self.onLoading?(true)
    let task = Task { @MainActor [weak self] in
      defer {
        self?.request = nil
        self?.onLoading?(false)
      }
      do {
        try Task.checkCancellation()
        let result: Result<[KsApi.Category], Error>
        do {
          if let fetch { result = .success(try await fetch()) }
          else { result = .success(try await service.fetchSearchCategories().rootCategories) }
        }
        catch { result = .failure(error) }
        try Task.checkCancellation()
        if delay.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
        else if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        guard let self, AppEnvironment.current.cache === cache else { return }
        if case let .success(categories) = result {
          cache[KSCache.ksr_discoveryFiltersCategories] = categories
          self.onCategories?(categories)
        }
      } catch {
        // Preserve the existing silent-error UI; a later load can retry.
      }
    }
    self.request = task
    return task
  }
}
