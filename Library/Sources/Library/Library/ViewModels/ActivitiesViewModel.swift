import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

@MainActor
public protocol ActitiviesViewModelInputs {
  /// Called when the project image in an update activity cell is tapped.
  func activityUpdateCellTappedProjectImage(activity: Activity)

  /// Call when the controller has received a user updated notification.
  func currentUserUpdated()

  /// Called when the user tapped to fix an errored pledge.
  func erroredBackingViewDidTapManage(with backing: ProjectAndBackingEnvelope)

  /// Call when the ManagePledgeViewController made changes.
  func managePledgeViewControllerDidFinish()

  /// Call when the feed should be refreshed, e.g. pull-to-refresh.
  func refresh()

  /// Call when the SurveyResponseViewController has been dismissed.
  func surveyResponseViewControllerDismissed()

  /// Call when an activity is tapped.
  func tappedActivity(_ activity: Activity)

  /// Call when the respond button is tapped in a survey cell.
  func tappedRespondNow(forSurveyResponse surveyResponse: SurveyResponse)

  /// Call when the Track shipping button is tapped in a TrackingActivitiesCell.
  func tappedTrackShipping(with trackingURL: URL)

  /// Call when a user session ends.
  func userSessionEnded()

  /// Call when a user session has started.
  func userSessionStarted()

  /// Call when the view did load.
  func viewDidLoad()

  /// Call when the view will appear with animated property.
  func viewWillAppear(animated: Bool)

  /**
   Call from the controller's `tableView:willDisplayCell:forRowAtIndexPath` method.

   - parameter row:       The 0-based index of the row displaying.
   - parameter totalRows: The total number of rows in the table view.
   */
  func willDisplayRow(_ row: Int, outOf totalRows: Int)
}

@MainActor
public protocol ActivitiesViewModelOutputs {
  /// Emits an array of activities that should be displayed.
  var activities: Signal<[Activity], Never> { get }

  /// Emits when the tab bar item's badge value should be cleared.
  var clearBadgeValue: Signal<(), Never> { get }

  /// Emits an array of errored backings to be displayed on the top of the list of projects.
  var erroredBackings: Signal<[ProjectAndBackingEnvelope], Never> { get }

  /// Emits when we should dismiss the empty state controller.
  var hideEmptyState: Signal<(), Never> { get }

  /// Emits a project and backing Param to navigate to ManagePledgeViewController.
  var goToManagePledge: Signal<ManagePledgeViewParamConfigData, Never> { get }

  /// Emits a project and ref tag that should be used to present a project controller.
  var goToProject: Signal<(Project, RefTag), Never> { get }

  /// Emits a survey response when we should navigate to the survey to fill it out.
  var goToSurveyResponse: Signal<SurveyResponse, Never> { get }

  /// Emits a project and update when we should navigate to that update.
  var goToUpdate: Signal<(Project, Update), Never> { get }

  /// Emits a tracking URL when we should navigate to a shipping tracking page.
  var goToTrackShipping: Signal<URL, Never> { get }

  /// Emits a boolean that indicates if the activities are refreshing.
  var isRefreshing: Signal<Bool, Never> { get }

  /// Emits `true` when logged-in, `false` when logged-out, when we should show the empty state controller.
  var showEmptyStateIsLoggedIn: Signal<Bool, Never> { get }

  /// Emits a non-`nil` survey response if there is an unanswered one available, and `nil` otherwise.
  var unansweredSurveys: Signal<[SurveyResponse], Never> { get }

  /// Emits a User that can be used to replace the current user in the environment.
  var updateUserInEnvironment: Signal<User, Never> { get }
}

@MainActor
public protocol ActivitiesViewModelType {
  var inputs: ActitiviesViewModelInputs { get }
  var outputs: ActivitiesViewModelOutputs { get }
}

@MainActor
public final class ActivitiesViewModel: ActivitiesViewModelType, ActitiviesViewModelInputs,
  ActivitiesViewModelOutputs {
  private let activityFeature: ActivityFeature
  internal private(set) var pageTask: Task<Void, Never>?
  internal private(set) var surveyTask: Task<Void, Never>?
  internal private(set) var userTask: Task<Void, Never>?
  internal private(set) var badgeTask: Task<Void, Never>?
  private var userProjection: (userID: Int?, generation: Int, token: UUID)?
  private var badgeProjection: (userID: Int?, generation: Int, token: UUID)?
  private let userPipe = Signal<User, Never>.pipe()
  public init(activityFeature: ActivityFeature? = nil) {
    let activityFeature = activityFeature ?? AppModel.shared.activityFeature
    self.activityFeature = activityFeature
    let isCloseToBottom = self.willDisplayRowProperty.signal.skipNil()
      .map { row, total in total > 3 && row >= total - 2 }
      .skipRepeats()
      .filter(isTrue)
      .ignoreValues()

    let requestFirstPage = Signal
      .merge(
        self.userSessionStartedProperty.signal,
        self.viewWillAppearProperty.signal.skipNil().filter(isTrue).ignoreValues(),
        self.refreshProperty.signal
      )
      .filter { activityFeature.sessionFeature.currentUser != nil }

    let activities = activityFeature.activityValues
    self.isRefreshing = activityFeature.loadingValues
    let clearedActivitiesOnSessionEnd = self.userSessionEndedProperty.signal.mapConst([Activity]())

    let activityToUpdate: Signal<Activity?, Never> = self.viewWillAppearProperty.signal.skipNil()
      .take(first: 1).mapConst(nil)

    let updatedActivities = Signal.combineLatest(activities, activityToUpdate)
      .map { currentActivities, updatedActivity in
        currentActivities
          .map { activity in
            activity == updatedActivity ? updatedActivity : activity
          }
          .compact()
      }

    self.activities = Signal.merge(clearedActivitiesOnSessionEnd, updatedActivities)
    self.clearBadgeValue = Signal.zip(
      self.refreshProperty.signal,
      updatedActivities.skip(first: 1)
    )
    .ignoreValues()

    self.updateUserInEnvironment = self.userPipe.output

    let currentUser = Signal
      .merge(
        self.currentUserUpdatedProperty.signal.ignoreValues(),
        self.viewDidLoadProperty.signal,
        self.userSessionStartedProperty.signal,
        self.userSessionEndedProperty.signal
      )
      .map { _ in activityFeature.sessionFeature.currentUser }

    // TODO: Remove this whole set of Signals as these live in Backings Dashboard now.
    // https://kickstarter.atlassian.net/browse/MBL-2255
    self.erroredBackings = Signal<[ProjectAndBackingEnvelope], Never>.never

    let loggedInForEmptyState = self.activities
      .filter { activityFeature.sessionFeature.currentUser != nil && $0.isEmpty }
      .skipRepeats(==)
      .mapConst(true)

    let loggedOutForEmptyState = currentUser
      .takeWhen(self.viewWillAppearProperty.signal.skipNil())
      .skipRepeats(==)
      .filter(isNil)
      .mapConst(false)

    self.showEmptyStateIsLoggedIn = Signal.merge(
      loggedInForEmptyState,
      loggedOutForEmptyState
    )

    self.hideEmptyState = Signal.merge(
      self.viewDidLoadProperty.signal.ignoreValues(),
      self.activities
        .combinePrevious([])
        .filter { previousActivities, currentActivities in
          previousActivities.isEmpty
            && !currentActivities.isEmpty
            && activityFeature.sessionFeature.currentUser != nil
        }.ignoreValues()
    )

    let projectActivities = self.tappedActivityProperty.signal.skipNil()
      .filter { $0.category != .update }

    self.goToProject = Signal
      .merge(
        self.tappedActivityProjectImage.signal.map { $0?.project },
        projectActivities.map { $0.project }
      )
      .skipNil()
      .map { ($0, .activity) }

    self.unansweredSurveys = activityFeature.surveyValues

    self.goToSurveyResponse = self.tappedSurveyResponseProperty.signal.skipNil()

    self.goToUpdate = self.tappedActivityProperty.signal.skipNil()
      .filter { $0.category == .update }
      .map { ($0.project, $0.update) }
      .flatMap { project, update -> SignalProducer<(Project, Update), Never> in
        guard let project = project, let update = update else { return .empty }
        return SignalProducer(value: (project, update))
      }

    let goToManagePledgeWithBacking = self.erroredBackingViewDidTapManageWithBackingProperty.signal
      .skipNil()

    self.goToManagePledge = goToManagePledgeWithBacking
      .map { env -> ManagePledgeViewParamConfigData? in
        (projectParam: Param.id(env.project.id), backingParam: Param.id(env.backing.id))
      }
      .skipNil()

    // Tracking

    self.goToProject.signal.map(first).observeValues { project in
      AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
        page: .activities,
        project: project
      )
    }

    self.goToTrackShipping = self.tappedTrackShippingProperty.signal.skipNil()
    requestFirstPage.observeValues { [weak self] _ in
      self?.pageTask = activityFeature.requestPage()
    }
    isCloseToBottom.observeValues { [weak self] _ in
      self?.pageTask = activityFeature.requestPage(next: true)
    }

    self.clearBadgeValue.observeValues { [weak self] in self?.refreshUser(.clearActivity) }
    self.managePledgeViewControllerDidFinishProperty.signal.observeValues { [weak self] in
      self?.refreshUser(.user)
    }
    currentUser.takeWhen(
      Signal.merge(
        self.viewWillAppearProperty.signal.skipNil().ignoreValues(),
        self.surveyResponseViewControllerDismissedProperty.signal
      )
    ).skipNil().observeValues { [weak self] _ in
      self?.surveyTask = activityFeature.requestSurveys()
    }
  }

  private func refreshUser(_ operation: SessionFeature.Operation) {
    let sessionFeature = self.activityFeature.sessionFeature
    guard sessionFeature.currentUser != nil else { return }
    let userID = sessionFeature.currentUser?.id
    let generation = sessionFeature.generation
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
        let user = try await request.value
        guard sessionFeature.isCurrent(userID: userID, generation: generation) else { return }
        self?.userPipe.input.send(value: user)
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

  fileprivate let currentUserUpdatedProperty = MutableProperty(())
  public func currentUserUpdated() {
    self.currentUserUpdatedProperty.value = ()
  }

  fileprivate let erroredBackingViewDidTapManageWithBackingProperty
    = MutableProperty<ProjectAndBackingEnvelope?>(nil)
  public func erroredBackingViewDidTapManage(with backing: ProjectAndBackingEnvelope) {
    self.erroredBackingViewDidTapManageWithBackingProperty.value = backing
  }

  fileprivate let managePledgeViewControllerDidFinishProperty = MutableProperty(())
  public func managePledgeViewControllerDidFinish() {
    self.managePledgeViewControllerDidFinishProperty.value = ()
  }

  fileprivate let viewWillAppearProperty = MutableProperty<Bool?>(nil)
  public func viewWillAppear(animated: Bool) {
    self.viewWillAppearProperty.value = animated
  }

  fileprivate let refreshProperty = MutableProperty(())
  public func refresh() {
    self.refreshProperty.value = ()
  }

  fileprivate let surveyResponseViewControllerDismissedProperty = MutableProperty(())
  public func surveyResponseViewControllerDismissed() {
    self.surveyResponseViewControllerDismissedProperty.value = ()
  }

  fileprivate let tappedActivityProjectImage = MutableProperty<Activity?>(nil)
  public func activityUpdateCellTappedProjectImage(activity: Activity) {
    self.tappedActivityProjectImage.value = activity
  }

  fileprivate let tappedSurveyResponseProperty = MutableProperty<SurveyResponse?>(nil)
  public func tappedRespondNow(forSurveyResponse surveyResponse: SurveyResponse) {
    self.tappedSurveyResponseProperty.value = surveyResponse
  }

  fileprivate let tappedActivityProperty = MutableProperty<Activity?>(nil)
  public func tappedActivity(_ activity: Activity) {
    self.tappedActivityProperty.value = activity
  }

  fileprivate let tappedTrackShippingProperty = MutableProperty<URL?>(nil)
  public func tappedTrackShipping(with trackingURL: URL) {
    self.tappedTrackShippingProperty.value = trackingURL
  }

  fileprivate let userSessionStartedProperty = MutableProperty(())
  public func userSessionStarted() {
    self.userSessionStartedProperty.value = ()
  }

  fileprivate let userSessionEndedProperty = MutableProperty(())
  public func userSessionEnded() {
    self.activityFeature.reset()
    self.userSessionEndedProperty.value = ()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  fileprivate let willDisplayRowProperty = MutableProperty<(row: Int, total: Int)?>(nil)
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    self.willDisplayRowProperty.value = (row, totalRows)
  }

  public let activities: Signal<[Activity], Never>
  public let clearBadgeValue: Signal<(), Never>
  public let erroredBackings: Signal<[ProjectAndBackingEnvelope], Never>
  public let hideEmptyState: Signal<(), Never>
  public let isRefreshing: Signal<Bool, Never>
  public let goToManagePledge: Signal<ManagePledgeViewParamConfigData, Never>
  public let goToProject: Signal<(Project, RefTag), Never>
  public let goToSurveyResponse: Signal<SurveyResponse, Never>
  public let goToUpdate: Signal<(Project, Update), Never>
  public let goToTrackShipping: Signal<URL, Never>
  public let showEmptyStateIsLoggedIn: Signal<Bool, Never>
  public let unansweredSurveys: Signal<[SurveyResponse], Never>
  public let updateUserInEnvironment: Signal<User, Never>

  public var inputs: ActitiviesViewModelInputs { return self }
  public var outputs: ActivitiesViewModelOutputs { return self }
}
