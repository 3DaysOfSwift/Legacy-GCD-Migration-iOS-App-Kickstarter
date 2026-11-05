import KsApi
import Foundation

/// Search's synchronous selection policy, owned by SearchFeature.
/// Main-actor state and explicit change notifications own the selection policy.
@MainActor
internal final class SearchFilterSelection {
  internal static let defaultSortOption = DiscoveryParams.Sort.magic
  internal static let defaultStateOption = DiscoveryParams.State.all

  internal enum Change {
    case sort(DiscoveryParams.Sort), category(SearchFiltersCategory), state(DiscoveryParams.State)
    case percent(DiscoveryParams.PercentRaisedBucket?), location(Location?)
    case amount(DiscoveryParams.AmountRaisedBucket?), goal(DiscoveryParams.GoalBucket?)
    case toggles(SearchFilterToggles)
  }
  private var observers: [(id: UUID, callback: (Change) -> Void)] = []
  internal func observe(_ observer: @escaping (Change) -> Void) -> MainActorObservation {
    let id = UUID()
    self.observers.append((id, observer))
    return MainActorObservation { [weak self] in self?.observers.removeAll { $0.id == id } }
  }
  private func emit(_ change: Change) {
    for observer in self.observers { observer.callback(change) }
  }
  private var togglesSeen = Set<Int>()
  private func emitToggle(_ index: Int) {
    self.togglesSeen.insert(index)
    if self.togglesSeen.count == 4 { self.emit(.toggles(self.toggles)) }
  }
  internal private(set) var selectedSortValue: DiscoveryParams.Sort = defaultSortOption { didSet { self.emit(.sort(self.selectedSortValue)) } }
  internal private(set) var selectedCategoryValue: SearchFiltersCategory = .none { didSet { self.emit(.category(self.selectedCategoryValue)) } }
  internal private(set) var selectedStateValue: DiscoveryParams.State = defaultStateOption { didSet { self.emit(.state(self.selectedStateValue)) } }
  internal private(set) var selectedPercentRaisedBucketValue: DiscoveryParams.PercentRaisedBucket? { didSet { self.emit(.percent(self.selectedPercentRaisedBucketValue)) } }
  internal private(set) var selectedLocationValue: Location? { didSet { self.emit(.location(self.selectedLocationValue)) } }
  internal private(set) var selectedAmountRaisedBucketValue: DiscoveryParams.AmountRaisedBucket? { didSet { self.emit(.amount(self.selectedAmountRaisedBucketValue)) } }
  internal private(set) var selectedGoalBucketValue: DiscoveryParams.GoalBucket? { didSet { self.emit(.goal(self.selectedGoalBucketValue)) } }
  internal private(set) var recommendedValue = false { didSet { self.emitToggle(0) } }
  internal private(set) var savedProjectsValue = false { didSet { self.emitToggle(1) } }
  internal private(set) var projectsWeLoveValue = false { didSet { self.emitToggle(2) } }
  internal private(set) var followingValue = false { didSet { self.emitToggle(3) } }

  internal var toggles: SearchFilterToggles {
    SearchFilterToggles(recommended: self.recommendedValue, savedProjects: self.savedProjectsValue,
                        projectsWeLove: self.projectsWeLoveValue, following: self.followingValue)
  }

  internal func publishInitialSelection() {
    self.emit(.sort(self.selectedSortValue))
    self.emit(.category(self.selectedCategoryValue))
    self.emit(.state(self.selectedStateValue))
    self.emit(.percent(self.selectedPercentRaisedBucketValue))
    self.emit(.location(self.selectedLocationValue))
    self.emit(.amount(self.selectedAmountRaisedBucketValue))
    self.emit(.goal(self.selectedGoalBucketValue))
    self.emitToggle(0); self.emitToggle(1); self.emitToggle(2); self.emitToggle(3)
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
