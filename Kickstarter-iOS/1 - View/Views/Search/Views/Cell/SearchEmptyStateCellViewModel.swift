import KsApi
import Observation

public struct SearchEmptyStateSearchData {
  public let query: String?
  public let hasFilters: Bool

  public init(query: String?, hasFilters: Bool) {
    self.query = query
    self.hasFilters = hasFilters
  }
}

@MainActor @Observable
public final class SearchEmptyStateCellViewModel {
  public init() {}

  public private(set) var titleText = ""
  public private(set) var subtitleText = ""
  public private(set) var hideClearFiltersButton = true

  public func configureWith(data: SearchEmptyStateSearchData) {
    if let query = data.query, !query.isEmpty {
      self.titleText = Strings.No_results_for(query: query)
    } else {
      self.titleText = Strings.No_results()
    }

    if data.hasFilters && data.query?.isEmpty == false {
      self.subtitleText = Strings.Try_rephrasing_your_search_or_adjusting_the_filters()
    } else if data.hasFilters {
      self.subtitleText = Strings.Try_adjusting_the_filters()
    } else {
      self.subtitleText = Strings.Try_rephrasing_your_search()
    }
    self.hideClearFiltersButton = !data.hasFilters
  }
}
