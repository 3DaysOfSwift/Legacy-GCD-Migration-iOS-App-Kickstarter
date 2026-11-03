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
  private var observation: Disposable?
  internal private(set) var loadingTask: Task<Void, Never>?

  init(projectDetailsFeature: ProjectDetailsFeature? = nil) {
    let feature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
    self.projectDetailsFeature = feature
    self.navigateToProject = self.projectTappedSignal
    self.observation = feature.relatedCompletions.observeValues { [weak self] route, result in
      guard let self, self.route == route else { return }
      self.loadingTask = nil
      switch result {
      case let .success(projects): self.similarProjectsProperty.value = .loaded(projects: projects)
      case let .failure(error): self.similarProjectsProperty.value = .error(error: error)
      }
    }
  }

  deinit {
    self.loadingTask?.cancel()
    self.observation?.dispose()
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
    self.loadingTask = self.projectDetailsFeature.requestRelated(route: self.route, projectID: projectID)
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
