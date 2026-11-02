import Foundation
import KsApi
import ReactiveSwift

@MainActor
public protocol FetchCategoriesUseCaseType {
  var uiOutputs: FetchCategoriesUseCaseUIOutputs { get }
  var dataOutputs: FetchCategoriesUseCaseDataOutputs { get }
}

@MainActor
public protocol FetchCategoriesUseCaseUIOutputs {
  var loadingIndicatorIsVisible: Signal<Bool, Never> { get }
}

@MainActor
public protocol FetchCategoriesUseCaseDataOutputs {
  var categories: Signal<[KsApi.Category], Never> { get }
}

/// Owns Discovery's category request. Equivalent loads share work; release cancels it.
@MainActor
public final class FetchCategoriesUseCase: FetchCategoriesUseCaseType, FetchCategoriesUseCaseUIOutputs,
  FetchCategoriesUseCaseDataOutputs {
  public var uiOutputs: FetchCategoriesUseCaseUIOutputs { self }
  public var dataOutputs: FetchCategoriesUseCaseDataOutputs { self }
  private let categoryPipe = Signal<[KsApi.Category], Never>.pipe()
  private let loadingPipe = Signal<Bool, Never>.pipe()
  public var categories: Signal<[KsApi.Category], Never> { self.categoryPipe.output }
  public var loadingIndicatorIsVisible: Signal<Bool, Never> { self.loadingPipe.output }
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
      self.categoryPipe.input.send(value: cached)
      if !cached.isEmpty { return Task {} }
    }
    let service = environment.apiService
    let fetch = self.fetch
    let delay = environment.apiDelayInterval.searchDelaySeconds
    self.loadingPipe.input.send(value: true)
    let task = Task { @MainActor [weak self] in
      defer {
        self?.request = nil
        self?.loadingPipe.input.send(value: false)
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
          self.categoryPipe.input.send(value: categories)
        }
      } catch {
        // Preserve the existing silent-error UI; a later load can retry.
      }
    }
    self.request = task
    return task
  }
}
