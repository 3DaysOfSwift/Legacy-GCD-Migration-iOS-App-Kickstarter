import KsApi
import MessageUI
import WebKit

@MainActor
public final class ProjectUpdatesViewModel {
  public var onSafari: ((URL) -> Void)?
  public var onUpdate: ((Project, Update) -> Void)?
  public var onComments: ((Update) -> Void)?
  public var onActivityHidden: ((Bool) -> Void)?
  public var onPhone: ((URL) -> Void)?
  public var onMail: ((String) -> Void)?
  public var onNoEmail: ((UIAlertController) -> Void)?
  public var onLoadRequest: ((URLRequest) -> Void)?
  private let feature: DiscussionFeature
  private let route = UUID()
  private let commentsRoute = UUID()
  private var project: Project?
  private var loaded = false
  private var canSend = false
  private var hasMailCapability = false
  private var hasPhoneCapability = false
  private var updateRevision = 0
  private var commentsRevision = 0
  private(set) var loadingTask: Task<Void, Never>?
  private(set) var contextTask: Task<Void, Never>?

  public init(feature: DiscussionFeature? = nil) {
    self.feature = feature ?? AppModel.shared.discussionFeature
  }

  public func configureWith(project: Project) {
    self.project = project
    if self.loaded { self.presentProject(project) }
  }

  public func viewDidLoad() {
    self.loaded = true
    self.hasPhoneCapability = true
    if let project = self.project { self.presentProject(project) }
  }

  private func presentProject(_ project: Project) {
    if let url = URL(string: project.urls.web.updates ?? "") {
      self.onLoadRequest?(AppEnvironment.current.apiService.preparedRequest(forURL: url))
    }
    AppEnvironment.current.ksrAnalytics.trackProjectViewed(project, sectionContext: .updates)
  }

  public func canSendEmail(_ canSend: Bool) { self.canSend = canSend; self.hasMailCapability = true }
  public func mailComposeCompletion(result: MFMailComposeResult) {}
  public func webViewDidFinishNavigation() { self.onActivityHidden?(true) }
  public func webViewDidStartProvisionalNavigation() { self.onActivityHidden?(false) }

  public func decidePolicy(forNavigationAction action: WKNavigationActionData) -> WKNavigationActionPolicy {
    let request = action.request
    let comments = isGoToCommentsRequest(request: request)
    let update = isGoToUpdateRequest(request: request)
    let updates = isUpdatesRequest(request: request)
    if comments, let params = projectUpdateParams(fromRequest: request) {
      self.load(params, comments: true)
    }
    if update, let params = projectUpdateParams(fromRequest: request) {
      self.load(params, comments: false)
    }
    if action.navigationType == .linkActivated {
      if updates, let url = request.url {
        self.onLoadRequest?(AppEnvironment.current.apiService.preparedRequest(forURL: url))
      } else if !comments && !update && !updates {
        if isPhoneLink(action: action), self.hasPhoneCapability, let url = request.url {
          self.onPhone?(url)
        } else if isEmailLink(action: action), self.hasMailCapability {
          if self.canSend { self.onMail?(formattedEmailAddress(action)) } else { self.onNoEmail?(noEmailError()) }
        } else if !isPhoneLink(action: action), !isEmailLink(action: action), let url = request.url {
          self.onSafari?(url)
        }
      }
    }
    return action.navigationType == .other || action.targetFrame?.mainFrame == .some(false) ? .allow : .cancel
  }

  private func load(_ params: (projectParam: Param, updateId: Int), comments: Bool) {
    let route = comments ? self.commentsRoute : self.route
    let request = self.feature.requestUpdate(route: route, id: params.updateId, project: params.projectParam)
    if comments { self.commentsRevision += 1 } else { self.updateRevision += 1 }
    let revision = comments ? self.commentsRevision : self.updateRevision
    let task = Task { [weak self] in
      guard let update = await request.value, !Task.isCancelled, let self else { return }
      if comments {
        guard self.commentsRevision == revision else { return }
        self.onComments?(update)
      } else {
        guard self.updateRevision == revision, self.loaded, let project = self.project else { return }
        self.onUpdate?(project, update)
      }
    }
    if comments { self.contextTask = task } else { self.loadingTask = task }
  }

  deinit {
    self.loadingTask?.cancel()
    self.contextTask?.cancel()
    let feature = self.feature
    let route = self.route
    let commentsRoute = self.commentsRoute
    Task { @MainActor in feature.release(route: route); feature.release(route: commentsRoute) }
  }

  func waitForLoads() async { await self.contextTask?.value; await self.loadingTask?.value }
}

// Returns project and update params for update and comments requests.
@MainActor
private func projectUpdateParams(fromRequest request: URLRequest) -> (projectParam: Param, updateId: Int)? {
  guard let nav = Navigation.match(request) else { return nil }
  switch nav {
  case .project(_, .update(_, .comments), _, _):
    return Navigation.Project.updateCommentsWithRequest(request)
  case .project(_, .update(_, .root), _, _):
    return Navigation.Project.updateWithRequest(request)
  default:
    return nil
  }
}

private func formattedEmailAddress(_ action: WKNavigationActionData) -> String {
  return action.request.url?.absoluteString.replacingOccurrences(of: "mailto:", with: "") ?? ""
}

private func isEmailLink(action: WKNavigationActionData) -> Bool {
  return action.request.url?.scheme == "mailto"
}

@MainActor
private func isGoToCommentsRequest(request: URLRequest) -> Bool {
  if let nav = Navigation.match(request), case .project(_, .update(_, .comments), _, _) = nav { return true }
  return false
}

@MainActor
private func isGoToUpdateRequest(request: URLRequest) -> Bool {
  if let nav = Navigation.match(request), case .project(_, .update(_, .root), _, _) = nav { return true }
  return false
}

private func isPhoneLink(action: WKNavigationActionData) -> Bool {
  return action.request.url?.scheme == "tel" ? true : false
}

@MainActor
private func isUpdatesRequest(request: URLRequest) -> Bool {
  if let nav = Navigation.match(request), case .project(_, .updates, _, _) = nav { return true }
  return false
}

@MainActor
private func noEmailError() -> UIAlertController {
  let alertController = UIAlertController(
    title: Strings.support_email_noemail_title(),
    message: Strings.support_email_noemail_message(),
    preferredStyle: .alert
  )
  alertController.addAction(
    UIAlertAction(
      title: Strings.general_alert_buttons_ok(),
      style: .cancel,
      handler: nil
    )
  )

  return alertController
}
