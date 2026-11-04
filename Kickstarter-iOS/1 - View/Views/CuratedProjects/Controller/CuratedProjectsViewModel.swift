import Foundation
import KsApi
import Observation

public typealias ProjectData = (project: Project, projects: [Project], refTag: RefTag)

@MainActor
@Observable
public final class CuratedProjectsViewModel {
  public private(set) var projects: [Project] = []
  public private(set) var isLoading = false
  var onDismiss: (() -> Void)?
  var onProject: ((ProjectData) -> Void)?
  var onLoading: ((Bool) -> Void)?
  var onProjects: (([Project]) -> Void)?
  var onError: ((String) -> Void)?
  private let feature: RecommendationsFeature
  private let route = UUID()
  private var categories: [KsApi.Category]?
  private var loaded = false
  private var revision = UUID()
  @ObservationIgnored private var presentation: Task<Void, Never>?

  public init(recommendationsFeature: RecommendationsFeature? = nil) {
    self.feature = recommendationsFeature ?? AppModel.shared.recommendationsFeature
  }

  public func configure(with categories: [KsApi.Category]) {
    self.categories = categories
    if self.loaded { self.start() }
  }

  public func viewDidLoad() {
    self.loaded = true
    self.isLoading = true
    self.onLoading?(true)
    if self.categories != nil { self.start() }
  }

  private func start() {
    guard let categories = self.categories else { return }
    self.presentation?.cancel()
    let revision = UUID()
    self.revision = revision
    let feature = self.feature
    let route = self.route
    let session = feature.sessionFeature
    let userID = session.currentUser?.id
    let generation = session.generation
    let command = feature.request(.curated(categories), route: route)
    self.presentation = Task { [weak self] in
      await command.value
      guard !Task.isCancelled, let self, self.revision == revision,
            session.isCurrent(userID: userID, generation: generation),
            let selection = feature.selection(route: route) else { return }
      self.projects = selection.projects
      self.onProjects?(selection.projects)
      if selection.projects.isEmpty { self.onError?(Strings.general_error_something_wrong()) }
      self.isLoading = false
      self.onLoading?(false)
    }
  }

  public func doneButtonTapped() {
    self.revision = UUID()
    self.presentation?.cancel()
    self.feature.release(route: self.route)
    self.onDismiss?()
  }

  public func projectTapped(_ project: Project?) {
    guard let project, self.feature.selection(route: self.route) != nil else { return }
    self.onProject?((project, self.projects, .onboarding))
  }

  func waitForPresentation() async { await self.presentation?.value }
  deinit {
    self.presentation?.cancel()
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }
}
