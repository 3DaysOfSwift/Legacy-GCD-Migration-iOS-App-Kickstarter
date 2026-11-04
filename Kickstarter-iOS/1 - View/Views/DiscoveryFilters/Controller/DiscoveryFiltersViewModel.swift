import KsApi
import Prelude

@MainActor
public final class DiscoveryFiltersViewModel {
  var onAnimateIn: (() -> Void)?
  var onLoading: ((Bool) -> Void)?
  var onCategoryRows: (([ExpandableRow], Int?, Int?) -> Void)?
  var onFavoriteRows: (([SelectableRow], Int?) -> Void)?
  var onTopRows: (([SelectableRow], Int?) -> Void)?
  var onSelectedRow: ((SelectableRow) -> Void)?
  private let categoriesUseCase = FetchCategoriesUseCase()
  private var configuredRow: SelectableRow?
  private var initialRow: SelectableRow?
  private var initialTopFilters: [DiscoveryParams]?
  private var initialRows: [ExpandableRow]?
  private var latestCategories: [KsApi.Category]?
  private var lastTappedRow: ExpandableRow?
  private var currentTopRows: [SelectableRow]?
  private var currentFavoriteRows: [SelectableRow]?
  private var categoryId: Int?
  private var selectedRowId: Int?
  private var loaded = false
  private(set) var shouldAnimateSelectableCell = false

  public init() {
    self.categoriesUseCase.onCategories = { [weak self] in self?.receivedCategories($0) }
    self.categoriesUseCase.onLoading = { [weak self] in self?.onLoading?($0) }
  }

  func configureWith(selectedRow: SelectableRow) {
    self.configuredRow = selectedRow
    self.categoryId = selectedRow.params.category?.rootId
    self.selectedRowId = self.categoryId
    self.prepareInitialRowIfReady()
    if let rows = self.currentTopRows { self.onTopRows?(rows, self.categoryId) }
    if let rows = self.currentFavoriteRows { self.onFavoriteRows?(rows, self.categoryId) }
  }
  func viewDidLoad() {
    if !self.loaded {
      self.loaded = true
      self.initialTopFilters = topFilters(forUser: AppEnvironment.current.currentUser)
      self.prepareInitialRowIfReady()
      if let rows = self.currentTopRows { self.onTopRows?(rows, self.categoryId) }
    }
    self.categoriesUseCase.start()
  }
  private func prepareInitialRowIfReady() {
    guard self.initialRow == nil, let row = self.configuredRow, let filters = self.initialTopFilters else { return }
    self.initialRow = row
    self.currentTopRows = filters.map { SelectableRow(isSelected: $0 == row.params, params: $0) }
    if let categories = self.latestCategories { self.receivedCategories(categories) }
  }
  private func receivedCategories(_ categories: [KsApi.Category]) {
    self.latestCategories = categories
    guard let row = self.initialRow else { return }
    if let favorites = favorites(selectedRow: row, categories: categories) {
      self.currentFavoriteRows = favorites
      self.onFavoriteRows?(favorites, self.categoryId)
    }
    let rows = expandableRows(selectedRow: row, categories: categories)
    self.initialRows = rows
    self.onCategoryRows?(rows, self.categoryId, self.selectedRowId)
    if let tapped = self.lastTappedRow {
      self.onCategoryRows?(toggleExpansion(row: tapped, in: rows), self.categoryId, self.selectedRowId)
    }
  }
  func tapped(expandableRow: ExpandableRow) {
    self.lastTappedRow = expandableRow
    self.selectedRowId = expandableRow.params.category?.rootId
    if let rows = self.initialRows {
      self.onCategoryRows?(toggleExpansion(row: expandableRow, in: rows), self.categoryId, self.selectedRowId)
    }
    self.shouldAnimateSelectableCell = true
    Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      self?.shouldAnimateSelectableCell = false
    }
  }
  func tapped(selectableRow: SelectableRow) {
    self.onSelectedRow?(selectableRow)
    AppEnvironment.current.ksrAnalytics.trackDiscoveryModalSelectedFilter(
      params: selectableRow.params, typeContext: typeContext(from: selectableRow.params), locationContext: .discoverOverlay
    )
  }
  func loadCategories() async { await self.categoriesUseCase.load() }
  func viewDidAppear() { self.onAnimateIn?() }
}

/**
 Converts an array of categories into a grouped array of expandable rows,
 then finds the expandable row that contains the given selectable row, and expands it.

 - parameter selectedRow: An optional selected row to search for.

 - parameter categories: A full array of categories.

 - returns: An array of expandable rows with one row expanded.
 */

private func expandableRows(
  selectedRow: SelectableRow,
  categories: [KsApi.Category]
) -> [ExpandableRow] {
  let expandableRows = categories.filter { (category: KsApi.Category) in category.isRoot }
    .sorted { (lhs: KsApi.Category, _) in lhs.isRoot }
    .map { (rootCategory: KsApi.Category) in
      ExpandableRow(
        isExpanded: false,
        params: .defaults |> DiscoveryParams.lens.category .~ rootCategory,
        selectableRows: ([rootCategory] + (rootCategory.subcategories?.nodes ?? []))
          .sorted()
          .compactMap { (node: KsApi.Category) in
            SelectableRow(
              isSelected: node == selectedRow.params.category,
              params: .defaults
                |> DiscoveryParams.lens.category .~ node
            )
          }
      )
    }
    .sorted { (lhs: ExpandableRow, rhs: ExpandableRow) in
      guard let lhsCategory = lhs.params.category, let rhsCategory = rhs.params.category else {
        return lhs.params.category == nil
      }
      return lhsCategory < rhsCategory
    }

  return expandableRows.map { expandableRow in
    expandableRow
      |> ExpandableRow.lens.isExpanded .~
      expandableRow.selectableRows.lazy.map { $0.params }.contains(selectedRow.params)
      |> ExpandableRow.lens.selectableRows .~
      expandableRow.selectableRows.sorted { lhs, rhs in
        guard let lhsName = lhs.params.category?.name, let rhsName = rhs.params.category?.name,
              lhs.params.category?.isRoot == rhs.params.category?.isRoot else {
          return (lhs.params.category?.isRoot ?? false) && !(rhs.params.category?.isRoot ?? false)
        }
        return lhsName < rhsName
      }
  }
}

/**
 Toggles the expansion of the row provided.

 - parameter rowToToggle:    The row to toggle expansion.
 - parameter expandableRows: A full array of expandable rows.

 - returns: A new array of expandable rows with the provided row's expansion toggled.
 */
private func toggleExpansion(
  row rowToToggle: ExpandableRow,
  in expandableRows: [ExpandableRow]
) -> [ExpandableRow] {
  return expandableRows
    .map { expandableRow in

      expandableRow
        |> ExpandableRow.lens.isExpanded .~ (
          expandableRow.params == rowToToggle.params &&
            !rowToToggle.isExpanded
        )
    }
}

private func topFilters(forUser user: User?) -> [DiscoveryParams] {
  var filters: [DiscoveryParams] = []

  filters.append(.defaults |> DiscoveryParams.lens.includePOTD .~ true)
  filters.append(.defaults |> DiscoveryParams.lens.staffPicks .~ true)

  guard user != nil else {
    return filters
  }

  filters.append(.defaults |> DiscoveryParams.lens.starred .~ true)

  if user?.optedOutOfRecommendations != true {
    filters.append(
      .defaults
        |> DiscoveryParams.lens.recommended .~ true
        |> DiscoveryParams.lens.backed .~ false
    )
  }

  filters.append(.defaults |> DiscoveryParams.lens.social .~ true)

  return filters
}

@MainActor
private func favorites(selectedRow: SelectableRow, categories: [KsApi.Category])
  -> [SelectableRow]? {
  let subcategories = categories
    .filter { $0.isRoot }
    .flatMap { category in [category] + (category.subcategories?.nodes ?? []) }

  let faves: [SelectableRow] = subcategories
    .compactMap { subcategory in
      guard let id = subcategory.intID else {
        return nil
      }
      if AppEnvironment.current.ubiquitousStore.favoriteCategoryIds.contains(id) ||
        AppEnvironment.current.userDefaults.favoriteCategoryIds.contains(id) {
        return SelectableRow(
          isSelected: subcategory == selectedRow.params.category,
          params: .defaults |> DiscoveryParams.lens.category .~ subcategory
        )
      } else {
        return nil
      }
    }
  return faves.isEmpty ? nil : faves
}

private func typeContext(
  from discoveryParams: DiscoveryParams
) -> KSRAnalytics.TypeContext {
  if discoveryParams.staffPicks == true {
    return .pwl
  } else if discoveryParams.starred == true {
    return .watched
  } else if discoveryParams.social == true {
    return .social
  } else if let category = discoveryParams.category {
    return category.parent == nil ? .categoryName : .subcategoryName
  } else if discoveryParams.recommended == true {
    return .recommended
  } else {
    return .allProjects
  }
}
