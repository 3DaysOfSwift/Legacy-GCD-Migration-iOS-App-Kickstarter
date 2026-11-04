import Foundation
import KsApi
import WebKit

@MainActor
internal final class UpdateViewModel {
  var onComments: ((Update) -> Void)?
  var onProject: ((Project, RefTag) -> Void)?
  var onSafari: ((URL) -> Void)?
  var onTitle: ((String) -> Void)?
  var onLoadRequest: ((URLRequest) -> Void)?
  private let feature: DiscussionFeature
  private let route = UUID()
  private var project: Project?
  private var currentUpdate: Update?
  private var loaded = false
  private var updateTask: Task<Void, Never>?
  private var projectTask: Task<Void, Never>?
  private var updateRevision = 0
  private var projectRevision = 0

  internal init(feature: DiscussionFeature? = nil) {
    self.feature = feature ?? AppModel.shared.discussionFeature
  }

  internal func configureWith(project: Project, update: Update) {
    self.project = project
    self.currentUpdate = update
    if self.loaded { self.displayTitle(update) }
  }

  internal func viewDidLoad() {
    self.loaded = true
    guard let update = self.currentUpdate else { return }
    if let url = URL(string: update.urls.web.update) {
      self.onLoadRequest?(AppEnvironment.current.apiService.preparedRequest(forURL: url))
    }
    self.displayTitle(update)
  }

  private func displayTitle(_ update: Update) {
    self.onTitle?(Strings.activity_project_update_update_count(update_count: Format.wholeNumber(update.sequence)))
  }

  internal func decidePolicyFor(navigationAction action: WKNavigationActionData) -> WKNavigationActionPolicy {
    if action.navigationType == .linkActivated {
      if let (param, id) = Navigation.Project.updateWithRequest(action.request) {
        let request = AppEnvironment.current.apiService.preparedRequest(forRequest: action.request)
        self.onLoadRequest?(request)
        self.loadUpdate(project: param, id: id)
      }
      if isExternalNavigation(action) {
        if let url = action.request.url { self.onSafari?(url) }
      } else {
        if Navigation.Project.updateCommentsWithRequest(action.request) != nil, let update = self.currentUpdate {
          self.onComments?(update)
        }
        if let (param, refTag) = Navigation.Project.withRequest(action.request), let current = self.project {
          self.navigateToProject(param: param, refTag: refTag ?? .update, action: action, current: current)
        }
      }
    }
    return action.navigationType == .other || action.targetFrame?.mainFrame == .some(false) ? .allow : .cancel
  }

  private func loadUpdate(project: Param, id: Int) {
    let request = self.feature.requestUpdate(route: self.route, id: id, project: project)
    self.updateRevision += 1
    let revision = self.updateRevision
    self.updateTask = Task { [weak self] in
      guard let update = await request.value, !Task.isCancelled, let self, self.updateRevision == revision else { return }
      self.currentUpdate = update
      if self.loaded { self.displayTitle(update) }
    }
  }

  private func navigateToProject(param: Param, refTag: RefTag, action: WKNavigationActionData, current: Project) {
    self.projectRevision += 1
    let revision = self.projectRevision
    if param == .id(current.id) || param == .slug(current.slug) {
      self.feature.cancelProject(route: self.route)
      self.deliverProject(current, refTag: refTag, action: action)
      return
    }
    let request = self.feature.requestProject(route: self.route, param: param)
    self.projectTask = Task { [weak self] in
      guard let project = await request.value, !Task.isCancelled, let self, self.projectRevision == revision else { return }
      self.deliverProject(project, refTag: refTag, action: action)
    }
  }

  private func deliverProject(_ project: Project, refTag: RefTag, action: WKNavigationActionData) {
    if project.displayPrelaunch == true {
      if let url = action.request.url { self.onSafari?(url) }
    } else {
      self.onProject?(project, refTag)
    }
  }

  deinit {
    self.updateTask?.cancel()
    self.projectTask?.cancel()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  func waitForLoads() async { await self.updateTask?.value; await self.projectTask?.value }
}

@MainActor
func isExternalNavigation(_ action: WKNavigationActionData) -> Bool {
  return ([
    Navigation.Project.withRequest(action.request),
    Navigation.Project.updateWithRequest(action.request),
    Navigation.Project.updateCommentsWithRequest(action.request)
  ] as [Any?]).compactMap { $0 }.isEmpty
}
