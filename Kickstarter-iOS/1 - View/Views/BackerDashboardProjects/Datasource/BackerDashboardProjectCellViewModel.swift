import Foundation
import KDS
import KsApi
import Observation
import UIKit

@MainActor
@Observable
public final class BackerDashboardProjectCellViewModel {
  public protocol HasProjectCellModel {
    var projectCellModel: any ProjectCellModel { get }
  }

  public protocol ProjectCellModel {
    var name: String { get }
    var state: Project.State { get }
    var imageURL: String? { get }
    var fundingProgress: Float { get }
    var percentFunded: Int { get }
    var displayPrelaunch: Bool? { get }
    var prelaunchActivated: Bool? { get }
    var launchedAt: TimeInterval? { get }
    var deadline: TimeInterval? { get }
    var isStarred: Bool? { get }
  }

  public struct State {
    let metadataBackgroundColor: UIColor
    let metadataIconIsHidden: Bool
    let metadataText: String
    let percentFundedText: NSAttributedString
    let photoURL: URL?
    let progress: Float
    let progressBarColor: UIColor
    let projectTitleText: NSAttributedString
    let prelaunchProject: Bool
    let savedIconIsHidden: Bool
  }

  public init() {}
  public private(set) var state: State?
  public var onChange: (() -> Void)?

  public func configureWith(project: any ProjectCellModel) {
    self.state = State(
      metadataBackgroundColor: metadataBackgroundColorForProject(project),
      metadataIconIsHidden: isProjectPrelaunch(project) || project.state != .live,
      metadataText: metadataString(for: project),
      percentFundedText: percentFundedString(for: project, fontSize: 10.0),
      photoURL: project.imageURL.flatMap(URL.init(string:)),
      progress: project.fundingProgress,
      progressBarColor: progressBarColorForProject(project),
      projectTitleText: titleString(for: project),
      prelaunchProject: isProjectPrelaunch(project),
      savedIconIsHidden: project.isStarred != .some(true)
    )
    self.onChange?()
  }
}

private func progressBarColorForProject(
  _ project: any BackerDashboardProjectCellViewModel
    .ProjectCellModel
) -> UIColor {
  switch project.state {
  case .live, .successful:
    return LegacyColors.ksr_create_700.uiColor()
  default:
    return LegacyColors.ksr_support_300.uiColor()
  }
}

// MARK: `ProjectCardProperties` extension

// Public class for easy conversions between `ProjectCardProperties` and
// `ProjectCellModel` protocol conformance.
public struct ProjectCardPropertiesProjectCellModel: BackerDashboardProjectCellViewModel.ProjectCellModel {
  public let properties: ProjectCardProperties
  init(_ properties: ProjectCardProperties) {
    self.properties = properties
  }

  public var name: String { self.properties.name }
  public var state: KsApi.Project.State { self.properties.state }
  public var imageURL: String? { self.properties.image.url?.absoluteString }
  public var fundingProgress: Float { Float(self.properties.percentFunded) / 100 }
  public var percentFunded: Int { self.properties.percentFunded }
  public var displayPrelaunch: Bool? { self.properties.shouldDisplayPrelaunch }
  public var prelaunchActivated: Bool? { self.properties.isPrelaunchActivated }
  public var launchedAt: TimeInterval? { self.properties.launchedAt?.timeIntervalSince1970 }
  public var deadline: TimeInterval? { self.properties.deadlineAt?.timeIntervalSince1970 }
  public var isStarred: Bool? { self.properties.isStarred }
}

extension ProjectCardProperties: BackerDashboardProjectCellViewModel.HasProjectCellModel {
  public var projectCellModel: any BackerDashboardProjectCellViewModel.ProjectCellModel {
    ProjectCardPropertiesProjectCellModel(self)
  }
}
