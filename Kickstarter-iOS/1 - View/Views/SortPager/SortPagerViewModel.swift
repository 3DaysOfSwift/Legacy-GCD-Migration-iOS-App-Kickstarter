import KsApi
import Observation

@MainActor
@Observable
public final class SortPagerViewModel {
  public private(set) var indicatorViewIsHidden = false
  public var createSortButtons: (([DiscoveryParams.Sort]) -> Void)?
  public var notifyDelegateOfSelectedSort: ((DiscoveryParams.Sort) -> Void)?
  public var pinSelectedIndicatorToPage: ((Int, Bool) -> Void)?
  public var setSelectedButton: ((Int) -> Void)?
  public var updateSortStyle: ((Int?, [DiscoveryParams.Sort], Bool) -> Void)?

  private var sorts: [DiscoveryParams.Sort]?
  private var appeared = false
  private var didAppear = false
  private var didInitializeSorts = false
  private var selectedSort: DiscoveryParams.Sort?
  private var selectedButton: Int?
  private var lastAnimatedPage: Int?
  private var revealTask: Task<Void, Never>?
  private let sleep: () async throws -> Void

  public init(sleep: @escaping () async throws -> Void = {
    try await Task.sleep(for: .milliseconds(100))
  }) {
    self.sleep = sleep
  }

  public func configureWith(sorts: [DiscoveryParams.Sort]) {
    self.sorts = sorts
    if self.appeared { self.applySorts(sorts) }
  }

  public func viewWillAppear() {
    if !self.appeared {
      self.indicatorViewIsHidden = true
      self.appeared = true
      if let sorts = self.sorts { self.applySorts(sorts) }
    } else if let sorts = self.sorts {
      self.applySorts(sorts)
    }
  }

  private func applySorts(_ sorts: [DiscoveryParams.Sort]) {
    if !self.didInitializeSorts {
      self.didInitializeSorts = true
      self.createSortButtons?(sorts)
      self.updateSortStyle?(nil, sorts, false)
      self.setSelectedIndexIfNeeded(0)
    }
    if let selectedSort = self.selectedSort {
      self.select(sort: selectedSort)
    }
  }

  public func select(sort: DiscoveryParams.Sort) {
    self.selectedSort = sort
    guard self.appeared, let sorts = self.sorts else { return }
    let index = sorts.firstIndex(of: sort) ?? 0
    self.setSelectedIndexIfNeeded(index)
    if self.lastAnimatedPage != index {
      self.lastAnimatedPage = index
      self.pinSelectedIndicatorToPage?(index, true)
    }
  }

  public func sortButtonTapped(index: Int) {
    self.setSelectedIndexIfNeeded(index)
    guard self.appeared, let sorts = self.sorts, sorts.indices.contains(index) else { return }
    self.notifyDelegateOfSelectedSort?(sorts[index])
  }

  public func updateStyle(categoryId: Int?) {
    guard self.appeared, let sorts = self.sorts else { return }
    self.updateSortStyle?(categoryId, sorts, true)
  }

  public func viewDidAppear() {
    guard !self.didAppear else { return }
    self.didAppear = true
    if self.appeared, self.sorts != nil { self.pinSelectedIndicatorToPage?(0, false) }
    self.revealIndicatorAfterDelay()
  }

  public func willRotateToInterfaceOrientation() {
    self.revealTask?.cancel()
    self.indicatorViewIsHidden = true
  }

  public func didRotateFromInterfaceOrientation() {
    if self.appeared, let sorts = self.sorts {
      let index = self.selectedSort.flatMap { sorts.firstIndex(of: $0) } ?? 0
      self.pinSelectedIndicatorToPage?(index, false)
    }
    self.revealIndicatorAfterDelay()
  }

  private func setSelectedIndexIfNeeded(_ index: Int) {
    guard self.selectedButton != index else { return }
    self.selectedButton = index
    self.setSelectedButton?(index)
  }

  private func revealIndicatorAfterDelay() {
    self.revealTask?.cancel()
    self.revealTask = Task { [weak self, sleep] in
      do {
        try await sleep()
        try Task.checkCancellation()
        self?.indicatorViewIsHidden = false
      } catch { }
    }
  }

}
