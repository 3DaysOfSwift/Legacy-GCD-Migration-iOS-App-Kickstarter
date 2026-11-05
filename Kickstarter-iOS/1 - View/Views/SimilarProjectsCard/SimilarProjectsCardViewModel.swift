import KDS
import Kingfisher
import KsApi
import UIKit

@MainActor
struct ProjectCardPresentation {
  let imageSource: Kingfisher.Source?
  let status: String
  let statusImage: UIImage?
  let title: String
  let progress: Float
  let progressBarColor: UIColor
  let isPrelaunch: Bool

  init(project: ProjectCardProperties) {
    self.imageSource = project.image
    self.status = getProjectStatus(for: project)
    self.statusImage = getProjectStatusImage(for: project)
    self.title = project.name
    self.progress = Float(project.percentFunded) / 100
    self.progressBarColor = progressBarColorForProject(project)
    self.isPrelaunch = similarProjectsCardViewModelIsProjectPrelaunch(project)
  }
}

@MainActor
private func getProjectStatus(for project: ProjectCardProperties) -> String {
  guard !similarProjectsCardViewModelIsProjectPrelaunch(project) else { return Strings.Launching_soon() }

  let percentage = Format.percentage(project.percentFunded)

  guard !(project.isInPostCampaignPledgingPhase && project.isPostCampaignPledgingEnabled)
  else { return Strings.Late_pledges_active() + " • " + Strings
    .percentage_funded(percentage: percentage)
  }

  switch project.state {
  case .live:
    guard let deadline = project.deadlineAt?.timeIntervalSince1970 else {
      return ""
    }

    let duration = Format.duration(secondsInUTC: deadline, abbreviate: true, useToGo: false)

    return Strings.Time_left_left(time_left: "\(duration.time) \(duration.unit)") + " • " + Strings
      .percentage_funded(percentage: percentage)
  case .successful, .failed:
    return Strings.Ended() + " • " + Strings
      .percentage_funded(percentage: percentage)
  default:
    return ""
  }
}

private func getProjectStatusImage(for project: ProjectCardProperties) -> UIImage? {
//  guard !(project.isInPostCampaignPledgingPhase && project.isPostCampaignPledgingEnabled)
//  else { return UIImage(named: "icon-late-pledge-timer") }

  guard !similarProjectsCardViewModelIsProjectPrelaunch(project) else { return image(named: "icon-launching-soon") }

  switch project.state {
  case .successful, .failed:
    return image(named: "icon-project-ended-flag")
  case .live:
    return image(named: "icon-timer")
  default:
    return nil
  }
}

private func similarProjectsCardViewModelIsProjectPrelaunch(_ project: ProjectCardProperties) -> Bool {
  project.shouldDisplayPrelaunch && project.isPrelaunchActivated
}

private func progressBarColorForProject(_ project: ProjectCardProperties) -> UIColor {
  switch project.state {
  case .live, .successful:
    return LegacyColors.ksr_create_500.uiColor()
  default:
    return LegacyColors.ksr_support_200.uiColor()
  }
}
