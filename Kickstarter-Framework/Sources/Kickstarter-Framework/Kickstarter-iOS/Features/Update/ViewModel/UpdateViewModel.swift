import Foundation
import KsApi
import Library
import Prelude
import ReactiveSwift
import WebKit

private struct UpdateData {
  fileprivate let project: Project
  fileprivate let update: Update
}

@MainActor
internal protocol UpdateViewModelInputs {
  /// Call with the project and update given to the controller.
  func configureWith(project: Project, update: Update)

  /// Call when the webview needs to decide a policy for a navigation action. Returns the decision policy.
  func decidePolicyFor(navigationAction: WKNavigationActionData)
    -> WKNavigationActionPolicy

  /// Call when the view loads.
  func viewDidLoad()
}

@MainActor
internal protocol UpdateViewModelOutputs {
  /// Emits when we should go to comments for the update.
  var goToComments: Signal<Update, Never> { get }

  /// Emits when we should go to the project.
  var goToProject: Signal<(Project, RefTag), Never> { get }

  /// Emits when we should open a safari browser with the URL.
  var goToSafariBrowser: Signal<URL, Never> { get }

  /// Emits the title of the controller.
  var title: Signal<String, Never> { get }

  /// Emits a request that should be loaded into the webview.
  var webViewLoadRequest: Signal<URLRequest, Never> { get }
}

@MainActor
internal protocol UpdateViewModelType {
  var inputs: UpdateViewModelInputs { get }
  var outputs: UpdateViewModelOutputs { get }
}

@MainActor
internal final class UpdateViewModel: UpdateViewModelType, UpdateViewModelInputs, UpdateViewModelOutputs {
  private let feature: DiscussionFeature
  private let route = UUID()
  private let disposables = CompositeDisposable()
  private var updateTask: Task<Void, Never>?
  private var projectTask: Task<Void, Never>?
  private let projectNavigation = Signal<(WKNavigationActionData, Project, RefTag), Never>.pipe()
  private var pendingProjectNavigation: (WKNavigationActionData, RefTag)?

  internal init(feature: DiscussionFeature? = nil) {
    let feature = feature ?? AppModel.shared.discussionFeature
    self.feature = feature
    let route = self.route
    let configurationData = self.configurationDataProperty.signal.skipNil()

    let initialUpdate = configurationData.map { $0.update }

    let project = configurationData.map { $0.project }

    let initialUpdateLoadRequest = initialUpdate
      .takeWhen(self.viewDidLoadProperty.signal)
      .map { URL(string: $0.urls.web.update) }
      .skipNil()
      .map { AppEnvironment.current.apiService.preparedRequest(forURL: $0) }

    let navigationAction = self.policyForNavigationActionProperty.signal.skipNil()

    let anotherUpdateLoadRequest = navigationAction
      .filter {
        $0.navigationType == .linkActivated && Navigation.Project.updateWithRequest($0.request) != nil
      }
      .map { AppEnvironment.current.apiService.preparedRequest(forRequest: $0.request) }

    self.webViewLoadRequest = Signal.merge(
      initialUpdateLoadRequest,
      anotherUpdateLoadRequest
    )

    let updateRequests = anotherUpdateLoadRequest.map(Navigation.Project.updateWithRequest).skipNil()
    let anotherUpdate = feature.updateValues.filter { $0.0 == route }.map { $0.1 }
    let currentUpdate = Signal.merge(initialUpdate, anotherUpdate)

    self.title = Signal.combineLatest(currentUpdate, self.viewDidLoadProperty.signal.take(first: 1))
      .map(first)
      .map { Strings.activity_project_update_update_count(update_count: Format.wholeNumber($0.sequence)) }

    self.policyDecisionProperty <~ navigationAction
      .map { action in
        action.navigationType == .other || action.targetFrame?.mainFrame == .some(false)
          ? .allow
          : .cancel
      }

    let externalNavigationAction = navigationAction
      .filter { action in action.navigationType == .linkActivated }
      .filter(isExternalNavigation)

    let internalNavigationAction = navigationAction
      .filter { action in action.navigationType == .linkActivated }
      .filter(isExternalNavigation >>> isFalse)

    let goToComments = currentUpdate
      .takePairWhen(internalNavigationAction)
      .map { update, action -> Update? in
        Navigation.Project.updateCommentsWithRequest(action.request) != nil ? update : nil
      }
      .skipNil()

    let goToProject = internalNavigationAction
      .map { action in (action, Navigation.Project.withRequest(action.request)) }
      .filter(second >>> isNotNil)

    let projectAndRefTag = self.projectNavigation.output

    self.goToComments = goToComments
    self.goToProject = projectAndRefTag.filter { _, project, _ in project.displayPrelaunch != .some(true) }
      .map { _, project, refTag in (project, refTag) }

    let goToPrelaunchPage = projectAndRefTag
      .filter { _, project, _ in project.displayPrelaunch == true }
      .map(first)

    self.goToSafariBrowser = Signal.merge(externalNavigationAction, goToPrelaunchPage)
      .map { action in action.request.url }
      .skipNil()
    self.disposables += feature.projectValues.filter { $0.0 == route }
      .observeValues { [weak self] _, project in
        guard let self, let (action, refTag) = self.pendingProjectNavigation else { return }
        self.pendingProjectNavigation = nil
        self.projectNavigation.input.send(value: (action, project, refTag))
      }
    self.disposables += project.takePairWhen(goToProject).map(unpack)
      .observeValues { [weak self] project, action, params in
        guard let self, let (param, refTag) = params else { return }
        self.pendingProjectNavigation = nil
        if param == .id(project.id) || param == .slug(project.slug) {
          feature.cancelProject(route: route)
          self.projectNavigation.input.send(value: (action, project, refTag ?? .update))
        } else {
          self.pendingProjectNavigation = (action, refTag ?? .update)
          self.projectTask = feature.requestProject(route: route, param: param)
        }
      }
    self.disposables += updateRequests.observeValues { [weak self] project, id in
      self?.updateTask = feature.requestUpdate(route: route, id: id, project: project)
    }
  }

  fileprivate let configurationDataProperty = MutableProperty<UpdateData?>(nil)
  internal func configureWith(project: Project, update: Update) {
    self.configurationDataProperty.value = UpdateData(project: project, update: update)
  }

  fileprivate let policyForNavigationActionProperty = MutableProperty<WKNavigationActionData?>(nil)
  fileprivate let policyDecisionProperty = MutableProperty(WKNavigationActionPolicy.allow)
  internal func decidePolicyFor(navigationAction: WKNavigationActionData)
    -> WKNavigationActionPolicy {
    self.policyForNavigationActionProperty.value = navigationAction
    return self.policyDecisionProperty.value
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  internal func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  internal let goToComments: Signal<Update, Never>
  internal let goToProject: Signal<(Project, RefTag), Never>
  internal let goToSafariBrowser: Signal<URL, Never>
  internal let title: Signal<String, Never>
  internal let webViewLoadRequest: Signal<URLRequest, Never>

  deinit {
    self.updateTask?.cancel()
    self.projectTask?.cancel()
    self.disposables.dispose()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  func waitForLoads() async {
    await self.updateTask?.value
    await self.projectTask?.value
  }

  internal var inputs: UpdateViewModelInputs { return self }
  internal var outputs: UpdateViewModelOutputs { return self }
}

func isExternalNavigation(_ action: WKNavigationActionData) -> Bool {
  return ([
    Navigation.Project.withRequest(action.request),
    Navigation.Project.updateWithRequest(action.request),
    Navigation.Project.updateCommentsWithRequest(action.request)
  ] as [Any?]).compactMap { $0 }.isEmpty
}
