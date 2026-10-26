import KsApi
import ReactiveSwift
import UIKit

@MainActor
public protocol SearchFiltersUseCaseType {
  var inputs: SearchFiltersUseCaseInputs { get }
  var uiOutputs: SearchFiltersUseCaseUIOutputs { get }
  var dataOutputs: SearchFiltersUseCaseDataOutputs { get }
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
public protocol SearchFiltersUseCaseUIOutputs {
  /// Sends a model object which can be used to display all filter options, and a type describing which filters to display.
  var showFilters: Signal<SearchFilterModalType, Never> { get }

  /// An @ObservableObject model which SwiftUI can use to display the search filters modals and header.
  /// Owned and automatically updated by this `SearchFiltersUseCase`.
  var searchFilters: SearchFilters { get }
}

@MainActor
public protocol SearchFiltersUseCaseDataOutputs {
  /// The currently selected sort option. Defaults to `.popular`. Default value only sent after `initialSignal` occurs.
  var selectedSort: Signal<DiscoveryParams.Sort, Never> { get }
  /// The currently selected category. Defaults to nil. Default value only sent after `initialSignal` occurs.
  var selectedCategory: Signal<SearchFiltersCategory, Never> { get }
  /// The currently selected project state. Defaults to `.all`. Default value only sent after `initialSignal` occurs.
  var selectedState: Signal<DiscoveryParams.State, Never> { get }
  /// The currently selected percent raised bucket. Defaults to `nil`. Default value only sent after `initialSignal` occurs.
  var selectedPercentRaisedBucket: Signal<DiscoveryParams.PercentRaisedBucket?, Never> { get }
  /// The currently selected filter location. Defaults to `nil`. Default value only sent after `initialSignal` occurs.
  var selectedLocation: Signal<Location?, Never> { get }
  /// The currently selected amount raised bucket. Defaults to `nil`. Default value only sent after `initialSignal` occurs.
  var selectedAmountRaisedBucket: Signal<DiscoveryParams.AmountRaisedBucket?, Never> { get }
  /// The currently selected goal bucket. Defaults to `nil`. Default value only sent after `initialSignal` occurs.
  var selectedGoalBucket: Signal<DiscoveryParams.GoalBucket?, Never> { get }
  /// The currently selected 'Show Only' toggles. All toggles default to `false`. Default value only sent after `initialSignal` occurs.
  var selectedToggles: Signal<SearchFilterToggles, Never> { get }
}

@MainActor
public final class SearchFiltersUseCase: SearchFiltersUseCaseType, SearchFiltersUseCaseInputs,
  SearchFiltersUseCaseUIOutputs, SearchFiltersUseCaseDataOutputs {
  /// @param initialSignal - An initial signal pulse. Must be sent once for default values of `selectedSort` and `selectedCategory` to emit.
  /// @param categories - A list of possible filter categories. Must be sent for `showCategoryFilters` and `selectedSortOption` to work.

  public init(
    searchFeature: SearchFeature,
    categories: Signal<[KsApi.Category], Never>,
    defaultLocations: Signal<[KsApi.Location], Never>,
    suggestedLocations: Signal<[KsApi.Location], Never>
  ) {
    self.searchFeature = searchFeature
    let selection = searchFeature.filterSelection
    self.categoriesProperty <~ categories
    self.defaultLocationsProperty <~ defaultLocations
    self.suggestedLocationsProperty <~ suggestedLocations

    self.selectedSort = selection.selectedSort
    self.selectedCategory = selection.selectedCategory
    self.selectedState = selection.selectedState
    self.selectedPercentRaisedBucket = selection.selectedPercentRaisedBucket
    self.selectedLocation = selection.selectedLocation
    self.selectedAmountRaisedBucket = selection.selectedAmountRaisedBucket
    self.selectedGoalBucket = selection.selectedGoalBucket
    self.selectedToggles = selection.selectedToggles

    self.searchFilters = SearchFilters(
      sort: SearchFilters.SortOptions(
        sortOptions: self.sortOptions,
        selectedSort: selection.selectedSortValue
      ),
      category: SearchFilters.CategoryOptions(
        categories: self.categoriesProperty.value,
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
        defaultLocations: self.defaultLocationsProperty.value,
        suggestedLocations: self.suggestedLocationsProperty.value
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

    let tappedTogglePill = self.tappedFilterTypeSignal.filter { $0.isToggle }
    let tappedModalPill = self.tappedFilterTypeSignal.filter { !$0.isToggle }

    self.showFilters = tappedModalPill
      .map { pill in
        let modalType = filterModal(toShowForPill: pill)
        return modalType
      }

    tappedTogglePill
      .observeValues { [weak self] pill in
        self?.toggleFilter(ofType: pill)
      }

    Signal.combineLatest(
      self.dataOutputs.selectedSort,
      self.dataOutputs.selectedCategory,
      self.dataOutputs.selectedState,
      self.dataOutputs.selectedPercentRaisedBucket,
      self.dataOutputs.selectedLocation,
      self.dataOutputs.selectedAmountRaisedBucket,
      self.dataOutputs.selectedGoalBucket,
      self.dataOutputs.selectedToggles
    )
    .observeForUI()
    .observeValues { [
      weak searchFilters
    ] sort, category, state, percentRaisedBucket, location, amountRaisedBucket, goalBucket, toggles in
      searchFilters?.update(
        withSort: sort,
        category: category,
        projectState: state,
        percentRaisedBucket: percentRaisedBucket,
        location: location,
        amountRaisedBucket: amountRaisedBucket,
        goalBucket: goalBucket,
        toggles: toggles
      )
    }

    self.categoriesProperty
      .signal
      .observeForUI()
      .observeValues { [weak searchFilters] categories in
        searchFilters?.update(withCategories: categories)
      }

    self.defaultLocationsProperty
      .signal
      .observeForUI()
      .observeValues { [weak searchFilters] locations in
        searchFilters?.update(withDefaultSearchLocations: locations)
      }

    self.suggestedLocationsProperty
      .signal
      .observeForUI()
      .observeValues { [weak searchFilters] locations in
        searchFilters?.update(withSuggestedLocations: locations)
      }
  }

  fileprivate let (tappedFilterTypeSignal, tappedFilterTypeObserver) = Signal<
    SearchFilterPill.FilterType,
    Never
  >
  .pipe()
  public func tappedButton(forFilterType type: SearchFilterPill.FilterType) {
    self.tappedFilterTypeObserver.send(value: type)
  }

  private let searchFeature: SearchFeature
  private let categoriesProperty = MutableProperty<[KsApi.Category]>([])
  private let defaultLocationsProperty = MutableProperty<[KsApi.Location]>([])
  private let suggestedLocationsProperty = MutableProperty<[KsApi.Location]>([])

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

  public let showFilters: Signal<SearchFilterModalType, Never>

  public let selectedSort: Signal<DiscoveryParams.Sort, Never>
  public let selectedCategory: Signal<SearchFiltersCategory, Never>
  public let selectedState: Signal<DiscoveryParams.State, Never>
  public let selectedPercentRaisedBucket: Signal<DiscoveryParams.PercentRaisedBucket?, Never>
  public let selectedLocation: Signal<Location?, Never>
  public let selectedAmountRaisedBucket: Signal<DiscoveryParams.AmountRaisedBucket?, Never>
  public let selectedGoalBucket: Signal<DiscoveryParams.GoalBucket?, Never>
  public let selectedToggles: Signal<SearchFilterToggles, Never>

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
  public var dataOutputs: SearchFiltersUseCaseDataOutputs { return self }
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
