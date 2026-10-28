import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

@MainActor
public protocol ProjectNotificationCellViewModelInputs {
  /// Call with the initial cell notification value.
  func configureWith(notification: ProjectNotification)

  /// Call when the notification switch is tapped.
  func notificationTapped(on: Bool)
}

@MainActor
public protocol ProjectNotificationCellViewModelOutputs {
  /// Emits the project name.
  var name: Signal<String, Never> { get }

  /// Emits true when the notification is turned on, false otherwise.
  var notificationOn: Signal<Bool, Never> { get }

  /// Emits when an update error has occurred and a message should be displayed.
  var notifyDelegateOfSaveError: Signal<String, Never> { get }
}

@MainActor
public protocol ProjectNotificationCellViewModelType {
  var inputs: ProjectNotificationCellViewModelInputs { get }
  var outputs: ProjectNotificationCellViewModelOutputs { get }
}

@MainActor
public final class ProjectNotificationCellViewModel: ProjectNotificationCellViewModelType,
  ProjectNotificationCellViewModelInputs, ProjectNotificationCellViewModelOutputs {
  private let feature: SettingsFeature
  private var notification: ProjectNotification?
  private var presentation: Disposable?
  private let names = Signal<String, Never>.pipe()
  private let switches = Signal<Bool, Never>.pipe()
  private let errors = Signal<String, Never>.pipe()

  public init(feature: SettingsFeature? = nil) {
    self.feature = feature ?? AppModel.shared.settingsFeature
    self.notificationOn = self.switches.output.skipRepeats()
  }

  public func configureWith(notification: ProjectNotification) {
    // Reused cells cannot receive a previous project's delayed save/error.
    self.presentation?.dispose()
    let current = self.feature.cachedProjectNotification(notification)
    self.notification = current
    self.names.input.send(value: current.project.name)
    self.switches.input.send(value: current.email && current.mobile)
  }

  public func notificationTapped(on: Bool) {
    guard let source = self.notification else { return }
    self.switches.input.send(value: on)
    let edited = source
      |> ProjectNotification.lens.email .~ on
      |> ProjectNotification.lens.mobile .~ on
    self.presentation?.dispose()
    self.presentation = self.feature.projectNotificationResult(edited).startWithResult { [weak self] result in
      guard let self else { return }
      switch result {
      case .success:
        // Confirmed state is in the shared cache; presentation remains optimistic.
        break
      case let .failure(error):
        let confirmed = self.feature.cachedProjectNotification(source)
        self.errors.input.send(value: error.errorMessages.first ?? Strings.profile_settings_error())
        self.switches.input.send(value: confirmed.email && confirmed.mobile)
      }
    }
  }

  deinit { self.presentation?.dispose() }

  public var name: Signal<String, Never> { self.names.output }
  public let notificationOn: Signal<Bool, Never>
  public var notifyDelegateOfSaveError: Signal<String, Never> { self.errors.output }
  public var inputs: ProjectNotificationCellViewModelInputs { self }
  public var outputs: ProjectNotificationCellViewModelOutputs { self }
}
