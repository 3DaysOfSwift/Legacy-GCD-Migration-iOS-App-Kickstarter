import KDS
import KsApi
import Prelude
import Observation
import UIKit

@MainActor @Observable
public final class MostPopularSearchProjectCellViewModel {
  public init() {}

  public private(set) var metadataText = ""
  public private(set) var percentFundedText = NSAttributedString(string: "")
  public private(set) var progress: Float = 0
  public private(set) var progressBarColor = UIColor.clear
  public private(set) var projectImageUrl: URL?
  public private(set) var projectName = NSAttributedString(string: "")
  public private(set) var prelaunchProject = false

  public func configureWith(project: any BackerDashboardProjectCellViewModel.ProjectCellModel) {
    self.metadataText = metadataString(for: project)
    self.percentFundedText = percentFundedString(for: project)
    self.progress = project.fundingProgress
    self.progressBarColor = progressBarColorForProject(project)
    self.projectImageUrl = project.imageURL.flatMap(URL.init(string:))
    self.projectName = titleString(for: project)
    self.prelaunchProject = isProjectPrelaunch(project)
  }
}

private func progressBarColorForProject(
  _ project: any BackerDashboardProjectCellViewModel
    .ProjectCellModel
) -> UIColor {
  guard !isProjectPrelaunch(project) else { return LegacyColors.ksr_create_700.uiColor() }

  switch project.state {
  case .live, .successful:
    return LegacyColors.ksr_create_700.uiColor()
  default:
    return LegacyColors.ksr_support_400.uiColor()
  }
}
