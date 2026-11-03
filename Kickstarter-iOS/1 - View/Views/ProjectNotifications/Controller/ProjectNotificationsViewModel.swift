import Foundation
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

@MainActor
public protocol ProjectNotificationsViewModelInputs {
  /// Call when the view loads.
  func viewDidLoad()
}

@MainActor
public protocol ProjectNotificationsViewModelOutputs {
  /// Emits a list of project notifications that should be displayed.
  var projectNotifications: Signal<[ProjectNotification], Never> { get }
}

@MainActor
public protocol ProjectNotificationsViewModelType {
  var inputs: ProjectNotificationsViewModelInputs { get }
  var outputs: ProjectNotificationsViewModelOutputs { get }
}

@MainActor
public final class ProjectNotificationsViewModel: ProjectNotificationsViewModelType,
  ProjectNotificationsViewModelInputs, ProjectNotificationsViewModelOutputs {
  private let feature: SettingsFeature
  private let notifications = Signal<[ProjectNotification], Never>.pipe()
  private var loadingTask: Task<Void, Never>?

  public init(feature: SettingsFeature? = nil) {
    self.feature = feature ?? AppModel.shared.settingsFeature
  }

  public func viewDidLoad() {
    self.loadingTask?.cancel()
    let feature = self.feature
    self.loadingTask = Task { [weak self] in
      do {
        let values = try await feature.projectNotifications()
        try Task.checkCancellation()
        self?.notifications.input.send(value: values)
      } catch {
        // Preserve the existing list's silent failure behavior.
      }
    }
  }

  func waitForLoading() async { await self.loadingTask?.value }
  deinit { self.loadingTask?.cancel() }

  public var projectNotifications: Signal<[ProjectNotification], Never> { self.notifications.output }

  public var inputs: ProjectNotificationsViewModelInputs { return self }
  public var outputs: ProjectNotificationsViewModelOutputs { return self }
}
