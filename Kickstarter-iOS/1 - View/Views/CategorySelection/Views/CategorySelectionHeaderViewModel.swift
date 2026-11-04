import Foundation

public enum CuratedProjectsContext {
  case onboarding
  case discovery
}

public enum CategorySelectionOnboardingHeaderViewContext {
  case categorySelection
  case curatedProjects(CuratedProjectsContext)

  var stepLabelText: String? {
    switch self {
    case .categorySelection:
      return Strings.Step_number(current_step: "1", total_steps: "2")
    case let .curatedProjects(context):
      switch context {
      case .onboarding:
        return Strings.Step_number(current_step: "2", total_steps: "2")
      case .discovery:
        return nil
      }
    }
  }

  var stepLabelHidden: Bool {
    switch self {
    case .categorySelection:
      return false
    case let .curatedProjects(context):
      switch context {
      case .discovery:
        return true
      case .onboarding:
        return false
      }
    }
  }

  var subtitleLabelText: String? {
    switch self {
    case .categorySelection:
      return Strings.Select_up_to_five()
    case .curatedProjects:
      return nil
    }
  }

  var titleLabelText: String {
    switch self {
    case .categorySelection:
      return Strings.Which_categories_interest_you()
    case .curatedProjects:
      return Strings.Check_out_these_handpicked_projects()
    }
  }
}

@MainActor
public final class CategorySelectionHeaderViewModel {
  var onStepHidden: ((Bool) -> Void)?
  var onStepText: ((String) -> Void)?
  var onSubtitle: ((String) -> Void)?
  var onTitle: ((String) -> Void)?

  func configure(with context: CategorySelectionOnboardingHeaderViewContext) {
    if let step = context.stepLabelText { self.onStepText?(step) }
    if let subtitle = context.subtitleLabelText { self.onSubtitle?(subtitle) }
    self.onTitle?(context.titleLabelText)
    self.onStepHidden?(context.stepLabelHidden)
  }
}
