import KsApi
import Prelude
import WebKit

public protocol HasProjectCreatorProperties {
  var projectCreatorProperties: ProjectCreatorProperties { get }
}

public struct ProjectCreatorProperties {
  public let id: Int
  public let name: String
  public let projectWebURL: String

  public init(id: Int, name: String, projectWebURL: String) {
    self.id = id
    self.name = name
    self.projectWebURL = projectWebURL
  }
}

extension Project: HasProjectCreatorProperties {
  public var projectCreatorProperties: ProjectCreatorProperties {
    return ProjectCreatorProperties(
      id: self.id,
      name: self.name,
      projectWebURL: self.urls.web.project
    )
  }
}

public typealias ProjectCreatorConfiguration = HasProjectCreatorProperties & HasProjectWebURL

@MainActor public final class ProjectCreatorViewModel {
  public var onGoBack: (() -> Void)?
  public var onLogin: ((LoginIntent) -> Void)?
  public var onMessage: ((MessageSubject, KSRAnalytics.MessageDialogContext) -> Void)?
  public var onSafari: ((URL) -> Void)?
  public var onLoad: ((URLRequest) -> Void)?
  private let projectDetailsFeature: ProjectDetailsFeature
  private var project: (any ProjectCreatorConfiguration)?
  private var loaded = false

  public init(projectDetailsFeature: ProjectDetailsFeature? = nil) {
    self.projectDetailsFeature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
  }

  public func configureWith(project: any ProjectCreatorConfiguration) {
    self.project = project
    self.loadIfReady()
  }

  public func viewDidLoad() {
    self.loaded = true
    self.loadIfReady()
  }

  private func loadIfReady() {
    guard self.loaded, let properties = self.project?.projectCreatorProperties,
          let request = self.projectDetailsFeature.creatorBiographyRequest(projectURL: properties.projectWebURL) else { return }
    self.onLoad?(request)
  }

  public func decidePolicy(forNavigationAction action: WKNavigationActionData) -> WKNavigationActionPolicy {
    if action.navigationType == .linkActivated {
      let isMessage = self.projectDetailsFeature.isCreatorMessage(request: action.request)
      if isMessage {
        if self.projectDetailsFeature.creatorMessageRequiresAuthentication { self.onLogin?(.messageCreator) }
        if self.loaded, let properties = self.project?.projectCreatorProperties,
           let subject = self.projectDetailsFeature.creatorMessageSubject(projectID: properties.id, projectName: properties.name) {
          self.onMessage?(subject, .projectPage)
        }
      }
      if self.loaded, let properties = self.project?.projectCreatorProperties {
        if properties.projectWebURL == action.request.url?.absoluteString {
          self.onGoBack?()
        } else if !isMessage, let url = action.request.url {
          self.onSafari?(url)
        }
      }
    }
    return action.navigationType == .other ? .allow : .cancel
  }
}
