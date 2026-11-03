import KsApi
import ReactiveSwift

/// Search's synchronous selection policy, owned by SearchFeature.
/// Ordinary main-actor state is authoritative. Pipes only adapt changes to the
/// legacy UIKit presentation/analytics edge; they do not own domain values.
@MainActor
internal final class SearchFilterSelection {
  internal static let defaultSortOption = DiscoveryParams.Sort.magic
  internal static let defaultStateOption = DiscoveryParams.State.all

  internal private(set) var selectedSortValue: DiscoveryParams.Sort = SearchFilterSelection.defaultSortOption {
    didSet { self.selectedSortPipe.input.send(value: self.selectedSortValue) }
  }
  private let selectedSortPipe = Signal<DiscoveryParams.Sort, Never>.pipe()
  internal var selectedSort: Signal<DiscoveryParams.Sort, Never> { self.selectedSortPipe.output }

  internal private(set) var selectedCategoryValue: SearchFiltersCategory = .none {
    didSet { self.selectedCategoryPipe.input.send(value: self.selectedCategoryValue) }
  }
  private let selectedCategoryPipe = Signal<SearchFiltersCategory, Never>.pipe()
  internal var selectedCategory: Signal<SearchFiltersCategory, Never> { self.selectedCategoryPipe.output }

  internal private(set) var selectedStateValue: DiscoveryParams.State = SearchFilterSelection.defaultStateOption {
    didSet { self.selectedStatePipe.input.send(value: self.selectedStateValue) }
  }
  private let selectedStatePipe = Signal<DiscoveryParams.State, Never>.pipe()
  internal var selectedState: Signal<DiscoveryParams.State, Never> { self.selectedStatePipe.output }

  internal private(set) var selectedPercentRaisedBucketValue: DiscoveryParams.PercentRaisedBucket? = nil {
    didSet { self.selectedPercentRaisedBucketPipe.input.send(value: self.selectedPercentRaisedBucketValue) }
  }
  private let selectedPercentRaisedBucketPipe = Signal<DiscoveryParams.PercentRaisedBucket?, Never>.pipe()
  internal var selectedPercentRaisedBucket: Signal<DiscoveryParams.PercentRaisedBucket?, Never> {
    self.selectedPercentRaisedBucketPipe.output
  }

  internal private(set) var selectedLocationValue: Location? = nil {
    didSet { self.selectedLocationPipe.input.send(value: self.selectedLocationValue) }
  }
  private let selectedLocationPipe = Signal<Location?, Never>.pipe()
  internal var selectedLocation: Signal<Location?, Never> { self.selectedLocationPipe.output }

  internal private(set) var selectedAmountRaisedBucketValue: DiscoveryParams.AmountRaisedBucket? = nil {
    didSet { self.selectedAmountRaisedBucketPipe.input.send(value: self.selectedAmountRaisedBucketValue) }
  }
  private let selectedAmountRaisedBucketPipe = Signal<DiscoveryParams.AmountRaisedBucket?, Never>.pipe()
  internal var selectedAmountRaisedBucket: Signal<DiscoveryParams.AmountRaisedBucket?, Never> {
    self.selectedAmountRaisedBucketPipe.output
  }

  internal private(set) var selectedGoalBucketValue: DiscoveryParams.GoalBucket? = nil {
    didSet { self.selectedGoalBucketPipe.input.send(value: self.selectedGoalBucketValue) }
  }
  private let selectedGoalBucketPipe = Signal<DiscoveryParams.GoalBucket?, Never>.pipe()
  internal var selectedGoalBucket: Signal<DiscoveryParams.GoalBucket?, Never> {
    self.selectedGoalBucketPipe.output
  }

  internal private(set) var recommendedValue = false {
    didSet { self.recommendedPipe.input.send(value: self.recommendedValue) }
  }
  private let recommendedPipe = Signal<Bool, Never>.pipe()

  internal private(set) var savedProjectsValue = false {
    didSet { self.savedProjectsPipe.input.send(value: self.savedProjectsValue) }
  }
  private let savedProjectsPipe = Signal<Bool, Never>.pipe()

  internal private(set) var projectsWeLoveValue = false {
    didSet { self.projectsWeLovePipe.input.send(value: self.projectsWeLoveValue) }
  }
  private let projectsWeLovePipe = Signal<Bool, Never>.pipe()

  internal private(set) var followingValue = false {
    didSet { self.followingPipe.input.send(value: self.followingValue) }
  }
  private let followingPipe = Signal<Bool, Never>.pipe()

  internal var toggles: SearchFilterToggles {
    SearchFilterToggles(
      recommended: self.recommendedValue,
      savedProjects: self.savedProjectsValue,
      projectsWeLove: self.projectsWeLoveValue,
      following: self.followingValue
    )
  }

  internal let selectedToggles: Signal<SearchFilterToggles, Never>

  internal init() {
    // Preserve the adapter's initial barrier and individual toggle emissions.
    // Native query construction reads ordinary state without this subscription.
    self.selectedToggles = Signal.combineLatest(
      self.recommendedPipe.output,
      self.savedProjectsPipe.output,
      self.projectsWeLovePipe.output,
      self.followingPipe.output
    ).map { recommended, saved, projectsWeLove, following in
      SearchFilterToggles(
        recommended: recommended, savedProjects: saved,
        projectsWeLove: projectsWeLove, following: following
      )
    }
  }

  internal func publishInitialSelection() {
    self.selectedSortPipe.input.send(value: self.selectedSortValue)
    self.selectedCategoryPipe.input.send(value: self.selectedCategoryValue)
    self.selectedStatePipe.input.send(value: self.selectedStateValue)
    self.selectedPercentRaisedBucketPipe.input.send(value: self.selectedPercentRaisedBucketValue)
    self.selectedLocationPipe.input.send(value: self.selectedLocationValue)
    self.selectedAmountRaisedBucketPipe.input.send(value: self.selectedAmountRaisedBucketValue)
    self.selectedGoalBucketPipe.input.send(value: self.selectedGoalBucketValue)
    self.recommendedPipe.input.send(value: self.recommendedValue)
    self.savedProjectsPipe.input.send(value: self.savedProjectsValue)
    self.projectsWeLovePipe.input.send(value: self.projectsWeLoveValue)
    self.followingPipe.input.send(value: self.followingValue)
  }

  internal func clearedQueryText() {
    self.resetFilters(for: .allFilters)
    self.resetFilters(for: .sort)
  }

  internal func resetFilters(for modal: SearchFilterReset) {
    switch modal {
    case .allFilters:
      // Sort isn't a filter, so it's not included here.
      self.selectedCategoryValue = .none
      self.selectedStateValue = SearchFilterSelection.defaultStateOption
      self.selectedPercentRaisedBucketValue = nil
      self.selectedLocationValue = nil
      self.selectedAmountRaisedBucketValue = nil
      self.selectedGoalBucketValue = nil
      self.followingValue = false
      self.recommendedValue = false
      self.projectsWeLoveValue = false
      self.savedProjectsValue = false
    case .category:
      self.selectedCategoryValue = .none
    case .sort:
      self.selectedSortValue = SearchFilterSelection.defaultSortOption
    case .percentRaised:
      self.selectedPercentRaisedBucketValue = nil
    case .location:
      self.selectedLocationValue = nil
    case .amountRaised:
      self.selectedAmountRaisedBucketValue = nil
    case .goal:
      self.selectedGoalBucketValue = nil
    }
  }

  internal func selectedFilter(_ event: SearchFilterEvent) {
    switch event {
    case let .sort(sort):
      self.selectedSortValue = sort
    case let .category(selectedCategory):
      self.selectedCategoryValue = selectedCategory
    case let .projectState(state):
      self.selectedStateValue = state
    case let .percentRaised(bucket):
      self.selectedPercentRaisedBucketValue = bucket
    case let .amountRaised(bucket):
      self.selectedAmountRaisedBucketValue = bucket
    case let .goal(bucket):
      self.selectedGoalBucketValue = bucket
    case let .location(location):
      self.selectedLocationValue = location
    case let .recommended(showRecommended):
      self.recommendedValue = showRecommended
    case let .savedProjects(showSavedProjects):
      self.savedProjectsValue = showSavedProjects
    case let .projectsWeLove(showProjectsWeLove):
      self.projectsWeLoveValue = showProjectsWeLove
    case let .following(showFollowing):
      self.followingValue = showFollowing
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
