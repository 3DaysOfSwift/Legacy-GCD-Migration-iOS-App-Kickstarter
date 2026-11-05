import Foundation
import KsApi
import Prelude

public typealias WatchProjectValue = (
  project: Project,
  context: KSRAnalytics.PageContext,
  discoveryParams: DiscoveryParams?
)

@MainActor
final class WatchProjectViewModel {
  enum Event {
    case selected(Bool)
    case impact, selection, success, login, savedAlert
    case project(Project)
    case notification(Notification)
  }

  var onEvent: ((Event) -> Void)?
  private let feature: ProjectMediaFeature
  private let sleep: @MainActor (TimeInterval) async throws -> Void
  private var configured: WatchProjectValue?
  private var project: Project?
  private var isReady = false
  private var selected: Bool?
  private var pendingLoginSelection: Bool?
  private var pendingIntent: ProjectMediaFeature.WatchIntent?
  private var task: Task<Void, Never>?

  init(feature: ProjectMediaFeature? = nil, sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { seconds in
    if seconds.isInfinite { try await Task.sleep(nanoseconds: UInt64.max) }
    else if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    try Task.checkCancellation()
  }) {
    self.feature = feature ?? AppModel.shared.projectMediaFeature
    self.sleep = sleep
  }

  func configure(with value: WatchProjectValue) {
    self.invalidate()
    self.configured = value
    if self.isReady { self.publishProject(self.feature.cached(value.project)) }
  }

  func awakeFromNib() { self.ready() }
  func viewDidLoad() { self.ready() }
  private func ready() {
    self.isReady = true
    if let value = self.configured { self.publishProject(self.feature.cached(value.project)) }
  }

  func projectFromNotification(project: Project?) {
    guard let project, let current = self.project, current.id == project.id else { return }
    self.publishProject(project)
  }

  func saveButtonTouched() { self.onEvent?(.impact) }

  func saveButtonTapped(selected: Bool) {
    if let value = self.configured {
      AppEnvironment.current.ksrAnalytics.trackWatchProjectButtonClicked(
        project: value.project, page: value.context, params: value.discoveryParams,
        typeContext: selected ? .unwatch : .watch
      )
    }
    guard self.isReady else { return }
    guard AppEnvironment.current.currentUser != nil else {
      self.pendingLoginSelection = selected
      self.onEvent?(.login)
      return
    }
    self.submit(selected: selected)
  }

  func userSessionEnded() { self.invalidate() }
  func userSessionStarted() {
    self.invalidate()
    guard let selected = self.pendingLoginSelection else { return }
    self.submit(selected: selected)
  }

  private func submit(selected: Bool) {
    guard var project = self.project else { return }
    self.invalidate()
    let intent = self.feature.prepareWatch(projectID: project.graphID, watched: !selected, previous: selected)
    self.pendingIntent = intent
    project.personalization.isStarred = !selected
    self.publishProject(project)
    self.onEvent?(selected ? .selection : .success)
    if !project.endsIn48Hours(today: AppEnvironment.current.dateType.init().date),
       !AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert || !AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert {
      AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert = true
      AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert = true
      self.onEvent?(.savedAlert)
    }
    if shouldShowNotificationDialog() {
      AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert = true
      AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert = true
      self.onEvent?(.notification(Notification(name: .ksr_showNotificationsDialog, userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.save])))
    }
    let feature = self.feature
    let sleep = self.sleep
    self.task = Task { [weak self] in
      do { try await sleep(0.5) } catch { return }
      guard !Task.isCancelled, feature.isCurrentIntent(intent), let result = await feature.watch(project: project, intent: intent) else { return }
      do { try await sleep(AppEnvironment.current.apiDelayInterval.searchDelaySeconds) } catch { return }
      guard !Task.isCancelled, feature.isCurrentIntent(intent) else { return }
      self?.publishProject(result)
    }
  }

  func waitForOperation() async { await self.task?.value }

  private func invalidate() {
    self.task?.cancel()
    self.task = nil
    if let pendingIntent { self.feature.cancelPreparedWatch(pendingIntent) }
    self.pendingIntent = nil
  }

  private func publishProject(_ project: Project) {
    self.project = project
    let selected = project.personalization.isStarred == true
    if self.selected != selected {
      self.selected = selected
      self.onEvent?(.selected(selected))
    }
    self.onEvent?(.project(project))
  }

  deinit {
    self.task?.cancel()
    if let intent = self.pendingIntent {
      let feature = self.feature
      Task { @MainActor in feature.cancelPreparedWatch(intent) }
    }
  }
}

@MainActor
private func shouldShowNotificationDialog() -> Bool {
  return PushNotificationDialog.canShowDialog(for: .save) &&
    AppEnvironment.current.currentUser?.stats.starredProjectsCount == 0
}
