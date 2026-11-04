import KsApi

@MainActor
public final class ThanksCategoryCellViewModel {
  private var category: KsApi.Category?
  var onGoToDiscovery: ((KsApi.Category) -> Void)?
  public init() {}

  func configureWith(category: KsApi.Category) -> String {
    self.category = category
    return Strings.See_all_category_name_projects(category_name: category.name)
  }

  func seeAllProjectsButtonTapped() {
    if let category = self.category { self.onGoToDiscovery?(category) }
  }
}
