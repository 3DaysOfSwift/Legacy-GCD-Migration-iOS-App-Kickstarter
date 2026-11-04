import Foundation
import KsApi
import ReactiveSwift

@MainActor public protocol SimilarProjectsUseCaseType {
  var inputs: SimilarProjectsUseCaseInputs { get }
  var outputs: SimilarProjectsUseCaseOutputs { get }
}

@MainActor public protocol SimilarProjectsUseCaseInputs {
  /// Call when a user taps on a similar project.
  /// Triggers navigation to the selected project's details.
  ///
  /// - Parameter project: The project that was tapped.
  func projectTapped(project: ProjectCardProperties)

  /// Call when a project ID is loaded or becomes available.
  /// Initiates fetching of similar projects for the given project ID.
  ///
  /// - Parameter projectID: The ID of the project to find similar projects for.
  func projectIDLoaded(projectID: String)
}

@MainActor public protocol SimilarProjectsUseCaseOutputs {
  /// The current state of similar projects.
  var similarProjects: Property<SimilarProjectsState> { get }

  /// Signal that emits when a user has tapped on a similar project.
  /// Use this to navigate to the selected project's details.
  var navigateToProject: Signal<ProjectCardProperties, Never> { get }
}

/// A Use Case for fetching similar projects and navigating to them when the user taps them.
@MainActor public final class SimilarProjectsUseCase: SimilarProjectsUseCaseType,
  SimilarProjectsUseCaseInputs,
  SimilarProjectsUseCaseOutputs {
  // MARK: - Initialization

  private let projectDetailsFeature: ProjectDetailsFeature
  private let route = UUID()
  private var revision = UUID()
  internal private(set) var loadingTask: Task<Void, Never>?

  init(projectDetailsFeature: ProjectDetailsFeature? = nil) {
    let feature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
    self.projectDetailsFeature = feature
    self.navigateToProject = self.projectTappedSignal

  }

  deinit {
    self.loadingTask?.cancel()

    let feature = self.projectDetailsFeature
    let route = self.route
    Task { @MainActor in feature.releaseRelated(route: route) }
  }

  // MARK: - Inputs

  private let (projectTappedSignal, projectTappedObserver) = Signal<ProjectCardProperties, Never>.pipe()
  public func projectTapped(project: ProjectCardProperties) {
    self.projectTappedObserver.send(value: project)
  }

  public func projectIDLoaded(projectID: String) {
    self.loadingTask?.cancel()
    let revision = UUID()
    self.revision = revision
    let feature = self.projectDetailsFeature
    let route = self.route
    let userID = AppEnvironment.current.currentUser?.id
    let command = feature.requestRelated(route: route, projectID: projectID)
    self.loadingTask = Task { [weak self] in
      await command.value
      guard !Task.isCancelled, let self, self.revision == revision,
            userID == AppEnvironment.current.currentUser?.id else { return }
      let snapshot = feature.relatedSnapshot(for: route)
      if let error = snapshot.error { self.similarProjectsProperty.value = .error(error: error) }
      else { self.similarProjectsProperty.value = .loaded(projects: snapshot.projects) }
    }
  }

  // MARK: - Outputs

  public let navigateToProject: Signal<ProjectCardProperties, Never>

  public let similarProjectsProperty = MutableProperty<SimilarProjectsState>(.loading)
  public var similarProjects: Property<SimilarProjectsState> {
    Property(self.similarProjectsProperty)
  }

  // MARK: - Type

  public var inputs: any SimilarProjectsUseCaseInputs { return self }
  public var outputs: any SimilarProjectsUseCaseOutputs { return self }
}
