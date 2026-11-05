import Foundation
import KsApi
import Prelude

@MainActor
final class ActivitiesViewModel {
  enum Event {
    case activities([Activity]), clearBadgeValue, erroredBackings([ProjectAndBackingEnvelope])
    case hideEmptyState, goToManagePledge(ManagePledgeViewParamConfigData)
    case goToProject(Project, RefTag), goToSurveyResponse(SurveyResponse), goToUpdate(Project, Update)
    case isRefreshing(Bool), showEmptyStateIsLoggedIn(Bool), unansweredSurveys([SurveyResponse])
    case updateUserInEnvironment(User)
  }
  var onEvent: ((Event) -> Void)?
  private let activityFeature: ActivityFeature
  private var observation: UUID?
  internal private(set) var pageTask: Task<Void, Never>?
  internal private(set) var surveyTask: Task<Void, Never>?
  internal private(set) var userTask: Task<Void, Never>?
  internal private(set) var badgeTask: Task<Void, Never>?
  private var userProjection: (userID: Int?, generation: Int, token: UUID)?
  private var badgeProjection: (userID: Int?, generation: Int, token: UUID)?
  private var hasAppeared = false
  private var lastActivity: [Activity]?
  private var displayedActivities: [Activity] = []
  private var hasEmittedActivity = false
  private var pendingRefreshes = 0
  private var pendingPageEvents = 0
  private var viewedUserKnown = false
  private var lastViewedUser: User?
  private var lastLoggedInEmpty: [Activity]?
  private var lastNearBottom: Bool?

  init(activityFeature: ActivityFeature? = nil) {
    let feature = activityFeature ?? AppModel.shared.activityFeature
    self.activityFeature = feature
    self.observation = feature.observe { [weak self] event in self?.receive(event) }
  }
  deinit {
    let feature = self.activityFeature
    if let observation = self.observation { Task { @MainActor in feature.stopObserving(observation) } }
  }
  private func receive(_ event: ActivityFeature.Event) {
    switch event {
    case let .loading(value): self.onEvent?(.isRefreshing(value))
    case let .surveys(surveys): self.onEvent?(.unansweredSurveys(surveys))
    case let .activities(activities):
      self.lastActivity = activities
      if self.hasAppeared { self.publishActivities(activities, pageResult: true) }
    }
  }
  private func publishActivities(_ activities: [Activity], pageResult: Bool) {
    let wasEmpty = self.displayedActivities.isEmpty
    self.displayedActivities = activities
    self.onEvent?(.activities(activities))
    if wasEmpty, !activities.isEmpty, self.activityFeature.sessionFeature.currentUser != nil {
      self.onEvent?(.hideEmptyState)
    }
    if self.activityFeature.sessionFeature.currentUser != nil, activities.isEmpty,
       self.lastLoggedInEmpty != activities {
      self.lastLoggedInEmpty = activities
      self.onEvent?(.showEmptyStateIsLoggedIn(true))
    }
    if pageResult {
      if self.hasEmittedActivity { self.pendingPageEvents += 1 }
      self.hasEmittedActivity = true
      self.drainBadgeEvents()
    }
  }
  private func drainBadgeEvents() {
    while self.pendingRefreshes > 0 && self.pendingPageEvents > 0 {
      self.pendingRefreshes -= 1
      self.pendingPageEvents -= 1
      self.onEvent?(.clearBadgeValue)
      self.refreshUser(.clearActivity)
    }
  }
  func viewDidLoad() { self.onEvent?(.hideEmptyState) }
  func viewWillAppear(animated: Bool) {
    let user = self.activityFeature.sessionFeature.currentUser
    if !self.viewedUserKnown || self.lastViewedUser != user {
      self.viewedUserKnown = true
      self.lastViewedUser = user
      if user == nil { self.onEvent?(.showEmptyStateIsLoggedIn(false)) }
    }
    if !self.hasAppeared {
      self.hasAppeared = true
      if let activities = self.lastActivity { self.publishActivities(activities, pageResult: true) }
    }
    if user != nil { self.surveyTask = self.activityFeature.requestSurveys() }
    if animated, user != nil { self.pageTask = self.activityFeature.requestPage() }
  }
  func userSessionStarted() {
    if self.activityFeature.sessionFeature.currentUser != nil { self.pageTask = self.activityFeature.requestPage() }
  }
  func userSessionEnded() {
    self.lastActivity = nil
    self.activityFeature.reset()
    self.publishActivities([], pageResult: false)
  }
  func currentUserUpdated() {}
  func refresh() {
    self.pendingRefreshes += 1
    self.drainBadgeEvents()
    if self.activityFeature.sessionFeature.currentUser != nil { self.pageTask = self.activityFeature.requestPage() }
  }
  func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    let nearBottom = totalRows > 3 && row >= totalRows - 2
    guard self.lastNearBottom != nearBottom else { return }
    self.lastNearBottom = nearBottom
    if nearBottom { self.pageTask = self.activityFeature.requestPage(next: true) }
  }
  func surveyResponseViewControllerDismissed() {
    if self.activityFeature.sessionFeature.currentUser != nil { self.surveyTask = self.activityFeature.requestSurveys() }
  }
  func managePledgeViewControllerDidFinish() { self.refreshUser(.user) }
  func erroredBackingViewDidTapManage(with backing: ProjectAndBackingEnvelope) {
    self.onEvent?(.goToManagePledge((projectParam: .id(backing.project.id), backingParam: .id(backing.backing.id))))
  }
  func activityUpdateCellTappedProjectImage(activity: Activity) { self.goToProject(activity.project) }
  func tappedActivity(_ activity: Activity) {
    if activity.category == .update {
      if let project = activity.project, let update = activity.update { self.onEvent?(.goToUpdate(project, update)) }
    } else { self.goToProject(activity.project) }
  }
  private func goToProject(_ project: Project?) {
    guard let project else { return }
    self.onEvent?(.goToProject(project, .activity))
    AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(page: .activities, project: project)
  }
  func tappedRespondNow(forSurveyResponse response: SurveyResponse) { self.onEvent?(.goToSurveyResponse(response)) }

  private func refreshUser(_ operation: SessionFeature.Operation) {
    let sessionFeature = self.activityFeature.sessionFeature
    guard sessionFeature.currentUser != nil else { return }
    let userID = sessionFeature.currentUser?.id
    let generation = sessionFeature.generation
    let readGeneration = sessionFeature.readGeneration
    let projection = operation == .clearActivity ? self.badgeProjection : self.userProjection
    if projection?.userID == userID, projection?.generation == generation { return }
    let token = UUID()
    let request = sessionFeature.request(operation)
    let task = Task { [weak self] in
      defer {
        if operation == .clearActivity, self?.badgeProjection?.token == token {
          self?.badgeTask = nil
          self?.badgeProjection = nil
        } else if operation == .user, self?.userProjection?.token == token {
          self?.userTask = nil
          self?.userProjection = nil
        }
      }
      do {
        var user = try await request.value
        guard sessionFeature.isCurrent(userID: userID, generation: generation),
              operation == .clearActivity || sessionFeature.readGeneration == readGeneration else { return }
        if operation == .clearActivity, var current = sessionFeature.currentUser {
          current.unseenActivityCount = user.unseenActivityCount
          user = current
        }
        if operation != .clearActivity {
          sessionFeature.commitUser(user, userID: userID, generation: generation)
        }
        self?.onEvent?(.updateUserInEnvironment(user))
      } catch {
        // Legacy presentation intentionally has no user-refresh error output.
        // SessionFeature's throwing API remains directly testable.
      }
    }
    if operation == .clearActivity {
      self.badgeTask = task
      self.badgeProjection = (userID, generation, token)
    } else {
      self.userTask = task
      self.userProjection = (userID, generation, token)
    }
  }

}
