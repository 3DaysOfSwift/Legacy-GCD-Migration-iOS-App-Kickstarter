import KsApi
import Observation

@MainActor
@Observable
public final class ProjectTabCategoryDescriptionCellViewModel {
  public init() {}
  public private(set) var categoryLabelText = ""
  public private(set) var descriptionLabelText = ""

  public func configureWith(value: ProjectTabCategoryDescription) {
    self.categoryLabelText = internationalizedString(for: value.category)
    self.descriptionLabelText = value.description
  }
}

private func internationalizedString(for category: ProjectTabCategory) -> String {
  switch category {
  case .longLastingDesign:
    return Strings.Long_lasting_design()
  case .sustainableMaterials:
    return Strings.Sustainable_materials()
  case .environmentallyFriendlyFactories:
    return Strings.Environmentally_friendly_factories()
  case .sustainableDistribution:
    return Strings.Sustainable_distribution()
  case .reusabilityAndRecyclability:
    return Strings.Reusability_and_recyclability()
  case .aiDisclosureOtherDetails:
    return Strings.I_am_incorporating_AI_in_my_project()
  case .somethingElse:
    return Strings.Something_else()
  }
}
