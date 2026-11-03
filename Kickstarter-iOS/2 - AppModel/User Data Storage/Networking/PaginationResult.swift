import Foundation

/// Value projection for existing paginated screens. Features own all requests and cancellation.
public enum PaginationResult<Value: Equatable, Cursor: Equatable, SomeError: Error>: Equatable {
  public static func == (
    lhs: Self,
    rhs: Self
  ) -> Bool {
    switch (lhs, rhs) {
    case (.unloaded, .unloaded):
      return true
    case let (
      .someLoaded(lhsValues, lhsCursor, lhsTotal, lhsPage),
      .someLoaded(rhsValues, rhsCursor, rhsTotal, rhsPage)
    ):
      return lhsValues == rhsValues && lhsCursor == rhsCursor && lhsTotal == rhsTotal && lhsPage == rhsPage
    case let (.allLoaded(lhsValues, lhsPage), .allLoaded(rhsValues, rhsPage)):
      return lhsValues == rhsValues && lhsPage == rhsPage
    case (.empty, .empty):
      return true
    case let (.error(lhsError), .error(rhsError)):
      return lhsError.localizedDescription == rhsError.localizedDescription
    case let (.loading(lhsPrevious), .loading(rhsPrevious)):
      return lhsPrevious == rhsPrevious
    case (.unloaded, _),
         (.someLoaded, _),
         (.allLoaded, _),
         (.empty, _),
         (.error, _),
         (.loading, _):
      return false
    }
  }

  case unloaded
  case someLoaded(values: [Value], cursor: Cursor, total: Int?, page: Int?)
  case allLoaded(values: [Value], page: Int?)
  case empty
  case error(SomeError)
  indirect case loading(previous: PaginationResult)

  public var values: [Value] {
    switch self {
    case let .loading(previous):
      previous.values
    case let .someLoaded(values, _, _, _):
      values
    case let .allLoaded(values, _):
      values
    case .unloaded, .empty, .error:
      []
    }
  }

  public var cursor: Cursor? {
    guard case let .someLoaded(_, cursor, _, _) = self else {
      return nil
    }
    return cursor
  }

  public var isLoading: Bool {
    guard case .loading = self else { return false }
    return true
  }

  public var error: SomeError? {
    guard case let .error(error) = self else { return nil }
    return error
  }

  public var canLoadMore: Bool {
    switch self {
    case .someLoaded, .loading(previous: .someLoaded):
      true
    default:
      false
    }
  }

  public var hasLoaded: Bool {
    switch self {
    case .someLoaded, .allLoaded, .empty:
      true
    case .unloaded, .loading, .error:
      false
    }
  }

  public var total: Int? {
    switch self {
    case let .allLoaded(values, _):
      values.count
    case let .loading(previous):
      previous.total
    case let .someLoaded(_, _, total, _):
      total
    case .empty:
      0
    case .unloaded, .error:
      nil
    }
  }

  public var page: Int? {
    switch self {
    case let .allLoaded(_, page):
      page
    case let .loading(previous):
      previous.page
    case let .someLoaded(_, _, _, page):
      page
    case .empty, .unloaded, .error:
      nil
    }
  }

  /**
   Transforms the values array within the current PaginationResult state while preserving the case and other properties.

   - Parameter transform: A closure that takes an array of Values and returns a transformed array of Values
   - Returns: A new PaginationResult instance with the transformed values (if the case has values)
   */
  public func mapValues(_ transform: ([Value]) -> [Value]) -> PaginationResult {
    switch self {
    case .unloaded:
      return .unloaded
    case let .someLoaded(values, cursor, total, page):
      return .someLoaded(values: transform(values), cursor: cursor, total: total, page: page)
    case let .allLoaded(values, page):
      return .allLoaded(values: transform(values), page: page)
    case .empty:
      return .empty
    case let .error(error):
      return .error(error)
    case let .loading(previous):
      return .loading(previous: previous.mapValues(transform))
    }
  }
}
