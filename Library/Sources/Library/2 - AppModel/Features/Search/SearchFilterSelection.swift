import KsApi
import ReactiveSwift

/// Search's selection policy. Owned by SearchFeature; presentation only reads it.
/// Keep the legacy per-field reset emissions until request/analytics equivalence
/// has been verified independently of this ownership change.
@MainActor
internal final class SearchFilterSelection {
  internal static let defaultSortOption = DiscoveryParams.Sort.magic
  internal static let defaultStateOption = DiscoveryParams.State.all
  private let (initialSignal, initialObserver) = Signal<Void, Never>.pipe()
  internal var selectedSortValue: DiscoveryParams.Sort { self.selectedSortProperty.value }
  internal var selectedCategoryValue: SearchFiltersCategory { self.selectedCategoryProperty.value }
  internal var selectedStateValue: DiscoveryParams.State { self.selectedStateProperty.value }
  internal var recommendedValue: Bool { self.recommendedProperty.value }
  internal var savedProjectsValue: Bool { self.savedProjectsProperty.value }
  internal var projectsWeLoveValue: Bool { self.projectsWeLoveProperty.value }
  internal var followingValue: Bool { self.followingProperty.value }

  internal init() {
    self.selectedSort = self.selectedSortProperty.signal(takeInitialValueWhen: self.initialSignal)
    self.selectedCategory = self.selectedCategoryProperty.signal(takeInitialValueWhen: self.initialSignal)
    self.selectedState = self.selectedStateProperty.signal(takeInitialValueWhen: self.initialSignal)
    self.selectedPercentRaisedBucket = self.selectedPercentRaisedBucketProperty
      .signal(takeInitialValueWhen: self.initialSignal)
    self.selectedLocation = self.selectedLocationProperty.signal(takeInitialValueWhen: self.initialSignal)
    self.selectedAmountRaisedBucket = self.selectedAmountRaisedBucketProperty
      .signal(takeInitialValueWhen: self.initialSignal)
    self.selectedGoalBucket = self.selectedGoalBucketProperty
      .signal(takeInitialValueWhen: self.initialSignal)

    self.selectedToggles = Signal.combineLatest(
      self.recommendedProperty.signal(takeInitialValueWhen: self.initialSignal),
      self.savedProjectsProperty.signal(takeInitialValueWhen: self.initialSignal),
      self.projectsWeLoveProperty.signal(takeInitialValueWhen: self.initialSignal),
      self.followingProperty.signal(takeInitialValueWhen: self.initialSignal)
    )
    .map { recommended, saved, pwl, following in
      SearchFilterToggles(
        recommended: recommended,
        savedProjects: saved,
        projectsWeLove: pwl,
        following: following
      )
    }

  }

  internal func publishInitialSelection() { self.initialObserver.send(value: ()) }

  private let selectedSortProperty = MutableProperty<DiscoveryParams.Sort>(
    SearchFilterSelection
      .defaultSortOption
  )
  private let selectedCategoryProperty = MutableProperty<SearchFiltersCategory>(.none)
  private let selectedStateProperty = MutableProperty<DiscoveryParams.State>(
    SearchFilterSelection
      .defaultStateOption
  )
  private let selectedPercentRaisedBucketProperty =
    MutableProperty<DiscoveryParams.PercentRaisedBucket?>(nil)
  private let selectedLocationProperty = MutableProperty<Location?>(nil)
  private let selectedAmountRaisedBucketProperty =
    MutableProperty<DiscoveryParams.AmountRaisedBucket?>(nil)
  private let selectedGoalBucketProperty = MutableProperty<DiscoveryParams.GoalBucket?>(nil)

  private let recommendedProperty = MutableProperty<Bool>(false)
  private let savedProjectsProperty = MutableProperty<Bool>(false)
  private let projectsWeLoveProperty = MutableProperty<Bool>(false)
  private let followingProperty = MutableProperty<Bool>(false)

  internal let selectedSort: Signal<DiscoveryParams.Sort, Never>
  internal let selectedCategory: Signal<SearchFiltersCategory, Never>
  internal let selectedState: Signal<DiscoveryParams.State, Never>
  internal let selectedPercentRaisedBucket: Signal<DiscoveryParams.PercentRaisedBucket?, Never>
  internal let selectedLocation: Signal<Location?, Never>
  internal let selectedAmountRaisedBucket: Signal<DiscoveryParams.AmountRaisedBucket?, Never>
  internal let selectedGoalBucket: Signal<DiscoveryParams.GoalBucket?, Never>
  internal let selectedToggles: Signal<SearchFilterToggles, Never>

  internal func clearedQueryText() {
    self.resetFilters(for: .allFilters)
    self.resetFilters(for: .sort)
  }

  internal func resetFilters(for modal: SearchFilterReset) {
    switch modal {
    case .allFilters:
      // Sort isn't a filter, so it's not included here.
      self.selectedCategoryProperty.value = .none
      self.selectedStateProperty.value = SearchFilterSelection.defaultStateOption
      self.selectedPercentRaisedBucketProperty.value = nil
      self.selectedLocationProperty.value = nil
      self.selectedAmountRaisedBucketProperty.value = nil
      self.selectedGoalBucketProperty.value = nil
      self.followingProperty.value = false
      self.recommendedProperty.value = false
      self.projectsWeLoveProperty.value = false
      self.savedProjectsProperty.value = false
    case .category:
      self.selectedCategoryProperty.value = .none
    case .sort:
      self.selectedSortProperty.value = SearchFilterSelection.defaultSortOption
    case .percentRaised:
      self.selectedPercentRaisedBucketProperty.value = nil
    case .location:
      self.selectedLocationProperty.value = nil
    case .amountRaised:
      self.selectedAmountRaisedBucketProperty.value = nil
    case .goal:
      self.selectedGoalBucketProperty.value = nil
    }
  }

  internal func selectedFilter(_ event: SearchFilterEvent) {
    switch event {
    case let .sort(sort):
      self.selectedSortProperty.value = sort
    case let .category(selectedCategory):
      self.selectedCategoryProperty.value = selectedCategory
    case let .projectState(state):
      self.selectedStateProperty.value = state
    case let .percentRaised(bucket):
      self.selectedPercentRaisedBucketProperty.value = bucket
    case let .amountRaised(bucket):
      self.selectedAmountRaisedBucketProperty.value = bucket
    case let .goal(bucket):
      self.selectedGoalBucketProperty.value = bucket
    case let .location(location):
      self.selectedLocationProperty.value = location
    case let .recommended(showRecommended):
      self.recommendedProperty.value = showRecommended
    case let .savedProjects(showSavedProjects):
      self.savedProjectsProperty.value = showSavedProjects
    case let .projectsWeLove(showProjectsWeLove):
      self.projectsWeLoveProperty.value = showProjectsWeLove
    case let .following(showFollowing):
      self.followingProperty.value = showFollowing
    }
  }

}

public enum SearchFilterReset {
  case allFilters, category, sort, percentRaised, location, amountRaised, goal
}

public enum SearchFilterEvent {
  case sort(DiscoveryParams.Sort)
  case category(SearchFiltersCategory)
  case projectState(DiscoveryParams.State)
  case percentRaised(DiscoveryParams.PercentRaisedBucket)
  case amountRaised(DiscoveryParams.AmountRaisedBucket)
  case goal(DiscoveryParams.GoalBucket)
  case location(Location?)
  case recommended(Bool)
  case savedProjects(Bool)
  case projectsWeLove(Bool)
  case following(Bool)
}

public struct SearchFilterToggles {
  public var recommended: Bool
  public var savedProjects: Bool
  public var projectsWeLove: Bool
  public var following: Bool
}
