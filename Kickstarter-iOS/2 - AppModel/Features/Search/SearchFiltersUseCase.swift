import KsApi
import UIKit

@MainActor
public protocol SearchFiltersUseCaseType {
  var inputs: SearchFiltersUseCaseInputs { get }
  var uiOutputs: SearchFiltersUseCaseUIOutputs { get }
}

@MainActor
public protocol SearchFiltersUseCaseInputs {
  /// Call this when the user taps on a button to show one of the sort options.
  func tappedButton(forFilterType: SearchFilterPill.FilterType)
  /// Call this when the clears their query and the sort options should reset.
  func clearedQueryText()
  /// Call this when the user updates a sort or filter option
  func selectedFilter(_ event: SearchFilterEvent)
  /// Call this when the user taps reset on a filter modal
  func resetFilters(for: SearchFilterModalType)
}

@MainActor
public protocol SearchFiltersUseCaseUIOutputs: AnyObject {
  /// Sends a model object which can be used to display all filter options, and a type describing which filters to display.
  var onShowFilters: ((SearchFilterModalType) -> Void)? { get set }

  /// An @ObservableObject model which SwiftUI can use to display the search filters modals and header.
  /// Owned and automatically updated by this `SearchFiltersUseCase`.
  var searchFilters: SearchFilters { get }
}

@MainActor
public final class SearchFiltersUseCase: SearchFiltersUseCaseType, SearchFiltersUseCaseInputs,
  SearchFiltersUseCaseUIOutputs {
  /// Adapts Feature selection and lookup outputs for the existing filter UI.
  /// Initial selection publication remains an explicit Feature command.
  public init(searchFeature: SearchFeature) {
    self.searchFeature = searchFeature
    let selection = searchFeature.filterSelection

    self.searchFilters = SearchFilters(
      sort: SearchFilters.SortOptions(
        sortOptions: self.sortOptions,
        selectedSort: selection.selectedSortValue
      ),
      category: SearchFilters.CategoryOptions(
        categories: [],
        selectedCategory: selection.selectedCategoryValue
      ),
      projectState: SearchFilters.ProjectStateOptions(
        stateOptions: self.stateOptions,
        selectedProjectState: selection.selectedStateValue
      ),
      percentRaised: SearchFilters.PercentRaisedOptions(
        buckets: DiscoveryParams.PercentRaisedBucket.allCases
      ),
      location: SearchFilters.LocationOptions(
        defaultLocations: [],
        suggestedLocations: []
      ),
      amountRaised: SearchFilters.AmountRaisedOptions(
        buckets: DiscoveryParams.AmountRaisedBucket.allCases
      ),
      goal: SearchFilters.GoalOptions(
        buckets: DiscoveryParams.GoalBucket.allCases
      ),
      showOnly: SearchFilters.ShowOnlyOptions(
        recommended: selection.recommendedValue,
        savedProjects: selection.savedProjectsValue,
        projectsWeLove: selection.projectsWeLoveValue,
        following: selection.followingValue
      )
    )


    self.lookupObservation = searchFeature.observeLookups { [weak self] update in
      switch update {
      case let .categories(values): self?.searchFilters.update(withCategories: values)
      case let .defaults(values): self?.searchFilters.update(withDefaultSearchLocations: values)
      case let .suggestions(values): self?.searchFilters.update(withSuggestedLocations: values)
      }
    }
    self.selectionObservation = selection.observe { [weak self, weak selection] change in
      guard let self, let selection else { return }
      self.selectionFieldsSeen.insert(change.field)
      guard self.selectionFieldsSeen.count == 8 else { return }
      self.searchFilters.update(
        withSort: selection.selectedSortValue,
        category: selection.selectedCategoryValue,
        projectState: selection.selectedStateValue,
        percentRaisedBucket: selection.selectedPercentRaisedBucketValue,
        location: selection.selectedLocationValue,
        amountRaisedBucket: selection.selectedAmountRaisedBucketValue,
        goalBucket: selection.selectedGoalBucketValue,
        toggles: selection.toggles
      )
    }
  }



  public func tappedButton(forFilterType type: SearchFilterPill.FilterType) {
    if type.isToggle {
      self.toggleFilter(ofType: type)
    } else {
      self.onShowFilters?(filterModal(toShowForPill: type))
    }
  }

  private let searchFeature: SearchFeature
  private var lookupObservation: MainActorObservation?
  private var selectionObservation: MainActorObservation?
  private var selectionFieldsSeen = Set<Int>()

  nonisolated internal static let defaultSortOption = DiscoveryParams.Sort.magic

  fileprivate let sortOptions = [
    DiscoveryParams.Sort.magic, // aka Recommended
    DiscoveryParams.Sort.popular,
    DiscoveryParams.Sort.newest,
    DiscoveryParams.Sort.endingSoon,
    DiscoveryParams.Sort.most_funded,
    DiscoveryParams.Sort.most_backed
  ]

  nonisolated internal static let defaultStateOption = DiscoveryParams.State.all

  fileprivate let stateOptions = [
    DiscoveryParams.State.all,
    DiscoveryParams.State.live,
    DiscoveryParams.State.late_pledge,
    DiscoveryParams.State.upcoming,
    DiscoveryParams.State.successful
  ]

  public var onShowFilters: ((SearchFilterModalType) -> Void)?

  public private(set) var searchFilters: SearchFilters

  public func clearedQueryText() { self.searchFeature.updateQuery("") }

  public func resetFilters(for modal: SearchFilterModalType) {
    self.searchFeature.resetFilters(modal.resetScope)
  }

  public func selectedFilter(_ event: SearchFilterEvent) {
    self.searchFeature.selectFilter(event)
  }

  internal func toggleFilter(ofType type: SearchFilterPill.FilterType) {
    switch type {
    case .projectsWeLove: self.searchFeature.toggleFilter(.projectsWeLove)
    case .saved: self.searchFeature.toggleFilter(.savedProjects)
    case .following: self.searchFeature.toggleFilter(.following)
    case .recommended: self.searchFeature.toggleFilter(.recommended)
    default: break // Modal pills never reach this path.
    }
  }

  public var inputs: SearchFiltersUseCaseInputs { return self }
  public var uiOutputs: SearchFiltersUseCaseUIOutputs { return self }
}

private func filterModal(toShowForPill pill: SearchFilterPill.FilterType) -> SearchFilterModalType {
  let modalType: SearchFilterModalType
  switch pill {
  case .allFilters:
    modalType = .allFilters
  case .category:
    modalType = .category
  case .sort:
    modalType = .sort
  case .projectState:
    modalType = .allFilters
  case .percentRaised:
    modalType = .percentRaised
  case .location:
    modalType = .location
  case .amountRaised:
    modalType = .amountRaised
  case .goal:
    modalType = .goal
  case .projectsWeLove:
    modalType = .allFilters
  case .saved:
    modalType = .allFilters
  case .following:
    modalType = .allFilters
  case .recommended:
    modalType = .allFilters
  }
  return modalType
}

public enum SearchFilterModalType: Hashable, CaseIterable {
  case allFilters
  case category
  case sort
  case percentRaised
  case location
  case amountRaised
  case goal
}

extension SearchFilterModalType {
  var resetScope: SearchFilterReset {
    switch self {
    case .allFilters: return .allFilters
    case .category: return .category
    case .sort: return .sort
    case .percentRaised: return .percentRaised
    case .location: return .location
    case .amountRaised: return .amountRaised
    case .goal: return .goal
    }
  }
}
