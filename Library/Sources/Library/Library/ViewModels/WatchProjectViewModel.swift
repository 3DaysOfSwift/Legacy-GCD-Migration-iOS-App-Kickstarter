import Foundation
import KsApi
import Prelude
import ReactiveSwift

public typealias WatchProjectValue = (
  project: Project,
  context: KSRAnalytics.PageContext,
  discoveryParams: DiscoveryParams?
)

@MainActor
public protocol WatchProjectViewModelInputs {
  func awakeFromNib()
  func configure(with value: WatchProjectValue)
  func projectFromNotification(project: Project?)
  func saveButtonTapped(selected: Bool)
  func saveButtonTouched()
  func userSessionEnded()
  func userSessionStarted()
  func viewDidLoad()
}

@MainActor
public protocol WatchProjectViewModelOutputs {
  /// Emits when haptic feedback should be generated
  var generateImpactFeedback: Signal<(), Never> { get }

  /// Emits when haptic feedback should be generated
  var generateSelectionFeedback: Signal<(), Never> { get }

  /// Emits when haptic feedback should be generated
  var generateNotificationSuccessFeedback: Signal<(), Never> { get }

  /// Emits when the login tout should be shown to the user.
  var goToLoginTout: Signal<(), Never> { get }

  /// Emits a project.
  var postNotificationWithProject: Signal<Project, Never> { get }

  /// Emits the accessibility hint for the star button.
  var saveButtonAccessibilityValue: Signal<String, Never> { get }

  /// Emits a boolean that determines if the save button is selected.
  var saveButtonSelected: Signal<Bool, Never> { get }

  /// Emits when a contextual Push Notification dialog should be shown.
  var showNotificationDialog: Signal<Notification, Never> { get }

  /// Emits when the project has been successfully saved and a prompt should be shown to the user.
  var showProjectSavedAlert: Signal<Void, Never> { get }
}

@MainActor
public protocol WatchProjectViewModelType {
  var inputs: WatchProjectViewModelInputs { get }
  var outputs: WatchProjectViewModelOutputs { get }
}

@MainActor
public final class WatchProjectViewModel: WatchProjectViewModelType,
  WatchProjectViewModelInputs, WatchProjectViewModelOutputs {
  public init(feature: ProjectMediaFeature? = nil) {
    let feature = feature ?? AppModel.shared.projectMediaFeature
    self.feature = feature
    let revision = self.revision
    let pendingIntent = self.pendingIntent
    let viewReady = Signal.merge(self.viewDidLoadProperty.signal, self.awakeFromNibProperty.signal)
    let projectProperty = self.configureWithValueProperty.signal.skipNil().map { $0.project }

    let configuredProject = Signal.combineLatest(
      projectProperty,
      viewReady
    )
    .map(first)
    .map(feature.cached)

    let currentUser = Signal.merge([
      viewReady,
      self.userSessionStartedProperty.signal,
      self.userSessionEndedProperty.signal
    ])
    .map { AppEnvironment.current.currentUser }
    .skipRepeats(==)

    let loggedInUserTappedSaveButton = currentUser
      .takePairWhen(self.saveButtonTappedProperty.signal)
      .filter { user, _ in user != nil }
      .map(second)

    let loggedOutUserTappedSaveButton = currentUser
      .takePairWhen(self.saveButtonTappedProperty.signal)
      .filter { user, _ in user == nil }
      .map(second)

    // Emits only when a user logs in after having tapped the save/heart while logged out.
    let userLoginAfterTappingSaveButton = Signal.combineLatest(
      self.userSessionStartedProperty.signal,
      loggedOutUserTappedSaveButton
    )

    let saveButtonTapped = Signal.merge(
      loggedInUserTappedSaveButton,
      userLoginAfterTappingSaveButton.map(second)
    )

    let projectOnSaveButtonToggle = configuredProject
      .takePairWhen(saveButtonTapped)

    let watchProjectToggle = projectOnSaveButtonToggle
      .map { project, selected -> (Project, ProjectMediaFeature.WatchIntent, UUID) in
        let intent = feature.prepareWatch(projectID: project.graphID, watched: !selected, previous: selected)
        pendingIntent.value = intent
        var project = project
        project.personalization.isStarred = !selected
        return (project, intent, revision.value)
      }

    let invalidation = Signal.merge(
      saveButtonTapped.ignoreValues(), projectProperty.ignoreValues(),
      self.userSessionEndedProperty.signal, self.userSessionStartedProperty.signal
    )
    let watchProjectResult = watchProjectToggle
      .ksr_debounce(.milliseconds(500), on: AppEnvironment.current.scheduler)
      .switchMap { project, intent, capturedRevision -> SignalProducer<Project, Never> in
        guard revision.value == capturedRevision else { return .empty }
        return feature.watchResult(project: project, intent: intent).take(until: invalidation)
      }

    let projectSavedFromNotification = configuredProject
      .takePairWhen(self.projectFromNotificationProperty.signal.skipNil())
      .filter { $0.id == $1.id }
      .map { $0.1 }

    // Project emits with initial configured value, immediately when watched, again on watch result
    let project = Signal.merge(
      configuredProject,
      projectSavedFromNotification,
      watchProjectToggle.map { $0.0 },
      watchProjectResult
    )

    self.goToLoginTout = loggedOutUserTappedSaveButton.ignoreValues()

    self.showProjectSavedAlert = project
      .takeWhen(saveButtonTapped)
      .filter { !$0.endsIn48Hours(today: AppEnvironment.current.dateType.init().date) }
      .filter { _ in
        !AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert ||
          !AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert
      }
      .on(value: { _ in
        AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert = true
        AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert = true
      })
      .ignoreValues()

    self.showNotificationDialog = project
      .takeWhen(saveButtonTapped)
      .filter { _ in shouldShowNotificationDialog() }
      .on(value: { _ in
        AppEnvironment.current.ubiquitousStore.hasSeenSaveProjectAlert = true
        AppEnvironment.current.userDefaults.hasSeenSaveProjectAlert = true
      })
      .ignoreValues()
      .map { _ in
        Notification(
          name: .ksr_showNotificationsDialog,
          userInfo: [UserInfoKeys.context: PushNotificationDialog.Context.save]
        )
      }

    self.saveButtonSelected = project
      .map { $0.personalization.isStarred == true }
      .skipRepeats()

    self.generateImpactFeedback = self.saveButtonTouchedProperty.signal
    self.generateNotificationSuccessFeedback = saveButtonTapped.signal.filter(isFalse).ignoreValues()
    self.generateSelectionFeedback = saveButtonTapped.signal.filter(isTrue).ignoreValues()

    self.saveButtonAccessibilityValue = self.saveButtonSelected
      .map { starred in starred ? Strings.Saved() : Strings.Unsaved() }

    self.postNotificationWithProject = project

    // Tracking
    let saveButtonTappedProperty = self.saveButtonTappedProperty

    self.configureWithValueProperty.signal.skipNil()
      .takeWhen(self.saveButtonTappedProperty.signal)
      .observeValues { project, context, discoveryParams in
        AppEnvironment.current.ksrAnalytics.trackWatchProjectButtonClicked(
          project: project,
          page: context,
          params: discoveryParams,
          typeContext: saveButtonTappedProperty.value ? .unwatch : .watch
        )
      }
  }

  private let feature: ProjectMediaFeature
  private let pendingIntent = MutableProperty<ProjectMediaFeature.WatchIntent?>(nil)
  deinit {
    let feature = self.feature
    let intent = self.pendingIntent.value
    if let intent { Task { @MainActor in feature.cancelPreparedWatch(intent) } }
  }
  private let revision = MutableProperty(UUID())
  private let awakeFromNibProperty = MutableProperty(())
  public func awakeFromNib() {
    self.awakeFromNibProperty.value = ()
  }

  fileprivate let configureWithValueProperty = MutableProperty<WatchProjectValue?>(nil)
  public func configure(with value: WatchProjectValue) {
    if let intent = self.pendingIntent.value { self.feature.cancelPreparedWatch(intent) }
    self.pendingIntent.value = nil
    self.revision.value = UUID()
    self.configureWithValueProperty.value = value
  }

  fileprivate let projectFromNotificationProperty = MutableProperty<Project?>(nil)
  public func projectFromNotification(project: Project?) {
    self.projectFromNotificationProperty.value = project
  }

  fileprivate let saveButtonTappedProperty = MutableProperty(false)
  public func saveButtonTapped(selected: Bool) {
    self.saveButtonTappedProperty.value = selected
  }

  fileprivate let saveButtonTouchedProperty = MutableProperty(())
  public func saveButtonTouched() {
    self.saveButtonTouchedProperty.value = ()
  }

  fileprivate let userSessionEndedProperty = MutableProperty(())
  public func userSessionEnded() {
    if let intent = self.pendingIntent.value { self.feature.cancelPreparedWatch(intent) }
    self.pendingIntent.value = nil
    self.revision.value = UUID()
    self.userSessionEndedProperty.value = ()
  }

  fileprivate let userSessionStartedProperty = MutableProperty(())
  public func userSessionStarted() {
    if let intent = self.pendingIntent.value { self.feature.cancelPreparedWatch(intent) }
    self.pendingIntent.value = nil
    self.revision.value = UUID()
    self.userSessionStartedProperty.value = ()
  }

  fileprivate let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  public let generateImpactFeedback: Signal<(), Never>
  public let generateNotificationSuccessFeedback: Signal<(), Never>
  public let generateSelectionFeedback: Signal<(), Never>
  public let goToLoginTout: Signal<(), Never>
  public let postNotificationWithProject: Signal<Project, Never>
  public let saveButtonAccessibilityValue: Signal<String, Never>
  public let saveButtonSelected: Signal<Bool, Never>
  public let showNotificationDialog: Signal<Notification, Never>
  public let showProjectSavedAlert: Signal<Void, Never>

  public var inputs: WatchProjectViewModelInputs { return self }
  public var outputs: WatchProjectViewModelOutputs { return self }
}

private func shouldShowNotificationDialog() -> Bool {
  return PushNotificationDialog.canShowDialog(for: .save) &&
    AppEnvironment.current.currentUser?.stats.starredProjectsCount == 0
}
