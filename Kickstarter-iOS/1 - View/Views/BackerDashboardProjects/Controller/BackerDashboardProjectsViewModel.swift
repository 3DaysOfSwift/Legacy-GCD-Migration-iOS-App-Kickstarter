import Foundation
import GraphAPI
import KsApi

public enum ProfileProjectsType: Decodable, Hashable {
  case backed
  case saved

  var trackingString: String {
    switch self {
    case .backed: return "backed"
    case .saved: return "saved"
    }
  }
}

@MainActor
public final class BackerDashboardProjectsViewModel {
  public var onEmptyState: ((Bool, ProfileProjectsType) -> Void)?
  public var onProject: ((ProjectCardProperties, RefTag) -> Void)?
  public var onRefreshing: ((Bool) -> Void)?
  public var onLoadingNextPage: ((Bool) -> Void)?
  public var onProjects: (([ProjectCardProperties]) -> Void)?
  private let profileFeature: ProfileFeature
  private var observer: PlatformObservation?
  private var projectsType: ProfileProjectsType?
  private var latestProjects: [ProjectCardProperties]?
  private var lastTappedProject: ProjectCardProperties?
  private var lastCounts: (Int?, Int, Int)?
  private var closeToBottom: Bool?
  private var latestWasRefresh: Bool?
  private var isLoading: Bool?
  private var refreshing: Bool?
  private var loadingNextPage: Bool?
  internal private(set) var pageTask: Task<Void, Never>?

  public init(profileFeature: ProfileFeature? = nil) {
    let feature = profileFeature ?? AppModel.shared.profileFeature
    self.profileFeature = feature
    self.observer = feature.observePages { [weak self] event in self?.receive(event) }
  }

  public func configureWith(projectsType: ProfileProjectsType) {
    self.projectsType = projectsType
    if let projects = self.latestProjects { self.onEmptyState?(projects.isEmpty, projectsType) }
    if let project = self.lastTappedProject { self.track(project, type: projectsType) }
  }
  public func currentUserUpdated() { self.refreshIfCountChanged() }
  public func viewDidAppear(_ animated: Bool) { self.refreshIfCountChanged() }
  public func viewDidLoad() {}

  private func refreshIfCountChanged() {
    guard let type = self.projectsType else { return }
    let counts = (self.profileFeature.sessionFeature.currentUser?.id,
                  self.profileFeature.projectCount(for: type), self.profileFeature.sessionFeature.generation)
    if let previous = self.lastCounts, previous.0 == counts.0, previous.1 == counts.1, previous.2 == counts.2 { return }
    self.lastCounts = counts
    self.setMode(refresh: true)
    self.pageTask = self.profileFeature.requestPage(type: type)
  }

  public func refresh() {
    self.setMode(refresh: true)
    if let type = self.projectsType { self.pageTask = self.profileFeature.requestPage(type: type) }
  }

  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    let close = totalRows > 5 && row >= totalRows - 3
    guard self.closeToBottom != close else { return }
    self.closeToBottom = close
    guard close else { return }
    self.setMode(refresh: false)
    if let type = self.projectsType { self.pageTask = self.profileFeature.requestPage(type: type, next: true) }
  }

  public func projectTapped(_ project: ProjectCardProperties) {
    self.lastTappedProject = project
    guard let type = self.projectsType else { return }
    self.onProject?(project, type == .backed ? .profileBacked : .profileSaved)
    self.track(project, type: type)
  }

  private func track(_ project: ProjectCardProperties, type: ProfileProjectsType) {
    AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
      page: .profile, project: project.projectAnalytics, location: .accountMenu,
      section: type == .backed ? .backed : .watched
    )
  }

  private func receive(_ event: ProfileFeature.PageEvent) {
    switch event {
    case let .projects(type, projects):
      guard self.projectsType == type else { return }
      self.latestProjects = projects
      self.onEmptyState?(projects.isEmpty, type)
      self.onProjects?(projects)
    case let .loading(type, loading):
      guard self.projectsType == type else { return }
      self.isLoading = loading
      self.publishLoading()
    }
  }

  private func setMode(refresh: Bool) { self.latestWasRefresh = refresh; self.publishLoading() }
  private func publishLoading() {
    guard let loading = self.isLoading, let refresh = self.latestWasRefresh else { return }
    let refreshing = loading && refresh
    let next = loading && !refresh
    if self.refreshing != refreshing { self.refreshing = refreshing; self.onRefreshing?(refreshing) }
    if self.loadingNextPage != next { self.loadingNextPage = next; self.onLoadingNextPage?(next) }
  }
}
