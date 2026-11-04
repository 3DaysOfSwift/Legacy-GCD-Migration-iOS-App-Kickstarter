import KsApi
import Observation

@MainActor
@Observable
public final class ProjectTabCheckmarkListCellViewModel {
  public init() {}
  public private(set) var categoryLabelText = ""
  public private(set) var descriptionOptionsText: [String] = []

  public func configureWith(value: ProjectTabFundingOptions) {
    self.categoryLabelText = Strings.My_project_seeks_funding_for_AI_technology()
    var options: [String] = []
    if value.fundingForAiConsent { options.append(internationalizedString(for: .consent)) }
    if value.fundingForAiAttribution { options.append(internationalizedString(for: .attribution)) }
    if value.fundingForAiOption { options.append(internationalizedString(for: .option)) }
    self.descriptionOptionsText = options
  }
}

private func internationalizedString(for category: ProjectTabAIFundingCategory) -> String {
  switch category {
  case .attribution:
    return Strings.The_owners_of_those_works()
  case .consent:
    return Strings.For_the_database_or_source_I_will_use()
  case .option:
    return Strings.There_is_or_will_be_an_opt()
  }
}
