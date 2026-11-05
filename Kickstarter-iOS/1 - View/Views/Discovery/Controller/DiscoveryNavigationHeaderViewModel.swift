import KsApi
import UIKit

@MainActor
final class DiscoveryNavigationHeaderViewModel {
  enum Event {
    case animateArrowToDown(Bool), arrowOpacityAnimated(CGFloat, Bool)
    case debugContainerViewIsHidden(Bool), debugImageViewIsDimmed(Bool)
    case dividerIsHidden(Bool), dismissDiscoveryFilters, exploreLabelIsHidden(Bool)
    case favoriteButtonAccessibilityLabel(String), favoriteViewIsDimmed(Bool), favoriteViewIsHidden(Bool)
    case notifyDelegateFilterSelectedParams(DiscoveryParams), primaryLabelFont(Bool)
    case primaryLabelOpacityAnimated(CGFloat, Bool), primaryLabelText(String)
    case secondaryLabelIsHidden(Bool), secondaryLabelText(String)
    case showDiscoveryFilters(SelectableRow), showFavoriteOnboardingAlert(String)
    case titleButtonAccessibilityHint(String), titleButtonAccessibilityLabel(String)
    case updateFavoriteButton(Bool, Bool)
  }

  var onEvent: ((Event) -> Void)?
  private let scheduleDismissal: @MainActor (@escaping @MainActor () -> Void) -> Void
  private var dismissalGeneration = 0
  private var currentParams: DiscoveryParams?
  private var configuredParams: DiscoveryParams?
  private var currentRow: SelectableRow?
  private var filtersHidden = true
  private var hasPublishedParams = false
  private var didAnimateArrowOpacity = false
  private var lastSecondaryHidden: Bool?
  private var lastFavoriteHidden: Bool?
  private var lastFavoriteDimmed: Bool?
  private var debugContainerHidden: Bool?
  private var lastCategoryID: Int?

  init(scheduleDismissal: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { action in
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      action()
    }
  }) {
    self.scheduleDismissal = scheduleDismissal
  }

  func viewDidLoad() {
    guard let environment = AppEnvironment.current else { return }
    let hidden = !(environment.mainBundle.isAlpha || environment.mainBundle.isBeta || environment.mainBundle.isDebug)
    self.debugContainerHidden = hidden
    self.onEvent?(.debugContainerViewIsHidden(hidden))
    self.publishFavoriteHidden(true)
    self.onEvent?(.primaryLabelOpacityAnimated(0, false))
    self.onEvent?(.arrowOpacityAnimated(0, false))
  }

  func configureWith(params: DiscoveryParams) {
    self.currentRow = SelectableRow(isSelected: true, params: params)
    guard self.configuredParams != params else { return }
    self.configuredParams = params
    self.receive(params: params)
  }

  func filtersSelected(row: SelectableRow) {
    self.currentRow = row
    self.onEvent?(.exploreLabelIsHidden(shouldHideLabel(row.params)))
    self.receive(params: row.params)
    self.dismissAfterDelay()
  }

  func titleButtonTapped() {
    guard let params = self.currentParams else { return }
    self.filtersHidden.toggle()
    self.publish(params: params)
    if self.filtersHidden { self.dismissAfterDelay() }
    else if let row = self.currentRow { self.onEvent?(.showDiscoveryFilters(row)) }
  }

  func favoriteButtonTapped() {
    if let id = self.lastCategoryID {
      toggleStoredFavoriteCategory(withId: id)
      self.publishFavorite(id: id, animated: true)
    }
    guard let params = self.currentParams else { return }
    guard let environment = AppEnvironment.current else { return }
    guard !environment.ubiquitousStore.hasSeenFavoriteCategoryAlert || !environment.userDefaults.hasSeenFavoriteCategoryAlert else { return }
    let title = stringsForTitle(params: params)
    environment.ubiquitousStore.hasSeenFavoriteCategoryAlert = true
    environment.userDefaults.hasSeenFavoriteCategoryAlert = true
    self.onEvent?(.showFavoriteOnboardingAlert(Strings.category_name_saved(category_name: title.subcategory ?? title.filter)))
  }

  private func receive(params: DiscoveryParams) {
    self.currentParams = params
    self.filtersHidden = true
    self.publish(params: params)
    if self.hasPublishedParams {
      self.onEvent?(.notifyDelegateFilterSelectedParams(params))
      self.dismissAfterDelay()
    }
    self.hasPublishedParams = true
    if let id = params.category?.intID {
      self.lastCategoryID = id
      self.publishFavorite(id: id, animated: false)
    }
  }

  private func publish(params: DiscoveryParams) {
    let strings = stringsForTitle(params: params)
    let secondaryHidden = strings.subcategory == nil
    self.onEvent?(.animateArrowToDown(self.filtersHidden))
    if self.lastSecondaryHidden != secondaryHidden {
      self.lastSecondaryHidden = secondaryHidden
      self.onEvent?(.dividerIsHidden(secondaryHidden))
      self.onEvent?(.secondaryLabelIsHidden(secondaryHidden))
    }
    self.publishFavoriteHidden(params.category == nil)
    if params.category != nil {
      let dimmed = !self.filtersHidden
      if self.lastFavoriteDimmed != dimmed {
        self.lastFavoriteDimmed = dimmed
        self.onEvent?(.favoriteViewIsDimmed(dimmed))
      }
    }
    if self.debugContainerHidden == false { self.onEvent?(.debugImageViewIsDimmed(!self.filtersHidden)) }
    self.onEvent?(.primaryLabelFont((params.category?.isRoot ?? true) && self.filtersHidden))
    self.onEvent?(.primaryLabelOpacityAnimated(params.category?.isRoot == .some(false) ? 0.6 : 1, true))
    self.onEvent?(.primaryLabelText(strings.filter))
    self.onEvent?(.secondaryLabelText(strings.subcategory ?? ""))
    if !self.didAnimateArrowOpacity {
      self.didAnimateArrowOpacity = true
      self.onEvent?(.arrowOpacityAnimated(1, true))
    }
    self.onEvent?(.titleButtonAccessibilityHint(self.filtersHidden ? Strings.Opens_filters() : Strings.Closes_filters()))
    self.onEvent?(.titleButtonAccessibilityLabel(accessibilityLabelForTitleButton(params: params)))
  }

  private func publishFavoriteHidden(_ hidden: Bool) {
    guard self.lastFavoriteHidden != hidden else { return }
    self.lastFavoriteHidden = hidden
    self.onEvent?(.favoriteViewIsHidden(hidden))
  }

  private func publishFavorite(id: Int, animated: Bool) {
    let selected = isFavoriteCategoryStored(withId: id)
    self.onEvent?(.updateFavoriteButton(selected, animated))
    self.onEvent?(.favoriteButtonAccessibilityLabel(selected
      ? Strings.discovery_favorite_categories_buttons_unfavorite_a11y_label()
      : Strings.discovery_favorite_categories_buttons_favorite_a11y_label()))
  }

  private func dismissAfterDelay() {
    self.dismissalGeneration += 1
    let generation = self.dismissalGeneration
    self.scheduleDismissal { [weak self] in
      guard let self, self.dismissalGeneration == generation else { return }
      self.onEvent?(.dismissDiscoveryFilters)
    }
  }
}

private func shouldHideLabel(_ params: DiscoveryParams?) -> Bool {
  guard let params = params else { return true }

  return stringsForTitle(params: params).0 != Strings.All_Projects()
}

private func stringsForTitle(params: DiscoveryParams) -> (filter: String, subcategory: String?) {
  let filterText: String
  var subcategoryText: String?

  if params.staffPicks == true {
    filterText = Strings.Projects_We_Love()
  } else if params.starred == true {
    filterText = Strings.Saved()
  } else if params.social == true {
    filterText = Strings.Following()
  } else if let category = params.category {
    filterText = category.isRoot ? string(forCategoryId: category.id) : category.root?.name ?? ""
    subcategoryText = category.isRoot ? nil : category.name
  } else if params.recommended == true {
    filterText = Strings.Recommended_For_You()
  } else {
    filterText = Strings.All_Projects()
  }
  return (filter: filterText, subcategory: subcategoryText)
}

private func accessibilityLabelForTitleButton(params: DiscoveryParams) -> String {
  if params.staffPicks == true {
    return Strings.Filter_by_projects_we_love()
  } else if params.starred == true {
    return Strings.Filter_by_saved_projects()
  } else if params.social == true {
    return Strings.Filter_by_projects_backed_by_friends()
  } else if let category = params.category {
    return category.isRoot
      ? Strings.Filter_by_category_name(category_name: category.name)
      : Strings.Filter_by_subcategory_name_in_category_name(
        subcategory_name: category.name,
        category_name: category.root?.name ?? ""
      )
  } else if params.recommended == true {
    return Strings.Filter_by_projects_recommended_for_you()
  } else {
    return Strings.Filter_by_all_projects()
  }
}

private func string(forCategoryId id: String) -> String {
  return RootCategory(categoryId: id).allProjectsString()
}

@MainActor
private func isFavoriteCategoryStored(withId id: Int) -> Bool {
  return AppEnvironment.current.ubiquitousStore.favoriteCategoryIds.firstIndex(of: id) != nil ||
    AppEnvironment.current.userDefaults.favoriteCategoryIds.firstIndex(of: id) != nil
}

@MainActor
private func toggleStoredFavoriteCategory(withId id: Int) {
  if let index = AppEnvironment.current.ubiquitousStore.favoriteCategoryIds.firstIndex(of: id) {
    AppEnvironment.current.ubiquitousStore.favoriteCategoryIds.remove(at: index)
  } else {
    AppEnvironment.current.ubiquitousStore.favoriteCategoryIds.append(id)
  }

  if let index = AppEnvironment.current.userDefaults.favoriteCategoryIds.firstIndex(of: id) {
    AppEnvironment.current.userDefaults.favoriteCategoryIds.remove(at: index)
  } else {
    AppEnvironment.current.userDefaults.favoriteCategoryIds.append(id)
  }
}
