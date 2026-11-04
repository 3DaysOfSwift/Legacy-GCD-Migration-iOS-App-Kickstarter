import Foundation
import KsApi
import Observation

@MainActor
@Observable
public final class SimilarProjectsUseCase {
  public private(set) var similarProjects: SimilarProjectsState = .loading
  var onState: ((SimilarProjectsState) -> Void)?
  var onNavigate: ((ProjectCardProperties) -> Void)?
  private let projectDetailsFeature: ProjectDetailsFeature
  private let route = UUID()
  private var revision = UUID()
  @ObservationIgnored internal private(set) var loadingTask: Task<Void, Never>?

  init(projectDetailsFeature: ProjectDetailsFeature? = nil) {
    self.projectDetailsFeature = projectDetailsFeature ?? AppModel.shared.projectDetailsFeature
  }

  deinit {
    self.loadingTask?.cancel()
    let feature = self.projectDetailsFeature
    let route = self.route
    Task { @MainActor in feature.releaseRelated(route: route) }
  }

  public func projectTapped(project: ProjectCardProperties) { self.onNavigate?(project) }

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
      let state: SimilarProjectsState
      if let error = snapshot.error { state = .error(error: error) }
      else { state = .loaded(projects: snapshot.projects) }
      self.similarProjects = state
      self.onState?(state)
    }
  }
}
