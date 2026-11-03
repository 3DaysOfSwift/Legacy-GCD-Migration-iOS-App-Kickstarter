import Foundation
import GraphAPI
import KsApi
import Prelude
import ReactiveExtensions
import ReactiveSwift

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
public protocol BackerDashboardProjectsViewModelInputs {
  /// Call to configure with the ProfileProjectsType to display.
  func configureWith(projectsType: ProfileProjectsType)

  /// Call when the user has updated.
  func currentUserUpdated()

  /// Call when a project cell is tapped.
  func projectTapped(_ project: ProjectCardProperties)

  /// Call when pull-to-refresh is invoked.
  func refresh()

  /// Call when the view loads.
  func viewDidLoad()

  /// Call when the view did appear.
  func viewDidAppear(_ animated: Bool)

  /// Call when a new row is displayed.
  func willDisplayRow(_ row: Int, outOf totalRows: Int)
}

@MainActor
public protocol BackerDashboardProjectsViewModelOutputs {
  /// Emits a boolean that determines if the empty state is visible and a ProfileProjectsType.
  var emptyStateIsVisible: Signal<(Bool, ProfileProjectsType), Never> { get }

  /// Emits the project, projects, and ref tag when should go to project page.
  var goToProject: Signal<(ProjectCardProperties, RefTag), Never> { get }

  /// Emits when the pull-to-refresh control is refreshing or not.
  var isRefreshing: Signal<Bool, Never> { get }

  /// Emits `true` when the next page is loading.
  var isLoadingNextPage: Signal<Bool, Never> { get }

  /// Emits a list of projects for the tableview datasource.
  var projects: Signal<[ProjectCardProperties], Never> { get }
}

@MainActor
public protocol BackerDashboardProjectsViewModelType {
  var inputs: BackerDashboardProjectsViewModelInputs { get }
  var outputs: BackerDashboardProjectsViewModelOutputs { get }
}

@MainActor
public final class BackerDashboardProjectsViewModel: BackerDashboardProjectsViewModelType,
  BackerDashboardProjectsViewModelInputs, BackerDashboardProjectsViewModelOutputs {
  private let profileFeature: ProfileFeature
  internal private(set) var pageTask: Task<Void, Never>?
  public init(profileFeature: ProfileFeature? = nil) {
    let profileFeature = profileFeature ?? AppModel.shared.profileFeature
    self.profileFeature = profileFeature
    let projectsType = self.configureWithProjectsTypeAndSortProperty.signal.skipNil()

    let userUpdated = Signal.merge(
      self.viewDidAppearProperty.signal.ignoreValues(),
      self.currentUserUpdatedProperty.signal
    )

    let userCounts: Signal<(Int?, Int, Int), Never> = projectsType.takeWhen(userUpdated)
      .map { type -> (Int?, Int, Int) in
        (
          profileFeature.sessionFeature.currentUser?.id,
          profileFeature.projectCount(for: type),
          profileFeature.sessionFeature.generation
        )
      }
    let userUpdatedProjectCount = userCounts.skipRepeats { previous, current in
      previous.0 == current.0 && previous.1 == current.1 && previous.2 == current.2
    }

    let requestFirstPageWith = projectsType
      .takeWhen(
        Signal.merge(
          userUpdatedProjectCount.ignoreValues(),
          self.refreshProperty.signal
        )
      )

    let isCloseToBottom = self.willDisplayRowProperty.signal.skipNil()
      .map { row, total in total > 5 && row >= total - 3 }
      .skipRepeats()
      .filter(isTrue)

    let isCloseToBottomWith = projectsType.takeWhen(isCloseToBottom)

    let isLoading = profileFeature.loadingValues
      .filter { [configuredType = self.configureWithProjectsTypeAndSortProperty] type, _ in
        configuredType.value == type
      }
      .map { $0.1 }
    self.projects = profileFeature.projectValues
      .filter { [configuredType = self.configureWithProjectsTypeAndSortProperty] type, _ in
        configuredType.value == type
      }
      .map { $0.1 }

    let latestLoadingWasRefresh = Signal.merge(
      userUpdatedProjectCount.mapConst(true),
      isCloseToBottom.mapConst(false),
      self.refreshProperty.signal.mapConst(true)
    )

    self.isRefreshing = Signal.combineLatest(isLoading, latestLoadingWasRefresh)
      .map { isLoading, latestLoadingWasRefresh in
        isLoading && latestLoadingWasRefresh
      }
      .skipRepeats()

    self.isLoadingNextPage = Signal.combineLatest(isLoading, latestLoadingWasRefresh)
      .map { isLoading, latestLoadingWasRefresh in
        isLoading && !latestLoadingWasRefresh
      }
      .skipRepeats()

    self.emptyStateIsVisible = Signal.combineLatest(projectsType, self.projects)
      .map { type, projects in
        (projects.isEmpty, type)
      }

    self.goToProject = projectsType
      .takePairWhen(self.projectTappedProperty.signal.skipNil())
      .map { projectsType, project in
        let ref = (projectsType == .backed) ? RefTag.profileBacked : RefTag.profileSaved
        return (project, ref)
      }

    requestFirstPageWith.observeValues { [weak self] type in
      self?.pageTask = profileFeature.requestPage(type: type)
    }
    isCloseToBottomWith.observeValues { [weak self] type in
      self?.pageTask = profileFeature.requestPage(type: type, next: true)
    }

    // Tracking

    Signal.combineLatest(self.projectTappedProperty.signal, projectsType)
      .observeValues { project, profilesProjectType in
        guard let project = project else { return }
        let sectionContext: KSRAnalytics.SectionContext = profilesProjectType == .backed ?
          .backed : .watched

        AppEnvironment.current.ksrAnalytics.trackProjectCardClicked(
          page: .profile,
          project: project.projectAnalytics,
          location: .accountMenu,
          section: sectionContext
        )
      }
  }

  private let configureWithProjectsTypeAndSortProperty =
    MutableProperty<ProfileProjectsType?>(nil)
  public func configureWith(projectsType: ProfileProjectsType) {
    self.configureWithProjectsTypeAndSortProperty.value = projectsType
  }

  private let currentUserUpdatedProperty = MutableProperty(())
  public func currentUserUpdated() {
    self.currentUserUpdatedProperty.value = ()
  }

  private let projectTappedProperty = MutableProperty<ProjectCardProperties?>(nil)
  public func projectTapped(_ project: ProjectCardProperties) {
    self.projectTappedProperty.value = project
  }

  private let refreshProperty = MutableProperty(())
  public func refresh() {
    self.refreshProperty.value = ()
  }

  private let viewDidAppearProperty = MutableProperty(false)
  public func viewDidAppear(_ animated: Bool) {
    self.viewDidAppearProperty.value = animated
  }

  private let willDisplayRowProperty = MutableProperty<(row: Int, total: Int)?>(nil)
  public func willDisplayRow(_ row: Int, outOf totalRows: Int) {
    self.willDisplayRowProperty.value = (row, totalRows)
  }

  private let viewDidLoadProperty = MutableProperty(())
  public func viewDidLoad() {
    self.viewDidLoadProperty.value = ()
  }

  public let emptyStateIsVisible: Signal<(Bool, ProfileProjectsType), Never>
  public let goToProject: Signal<(ProjectCardProperties, RefTag), Never>
  public let isRefreshing: Signal<Bool, Never>
  public let isLoadingNextPage: Signal<Bool, Never>
  public let projects: Signal<[ProjectCardProperties], Never>

  public var inputs: BackerDashboardProjectsViewModelInputs { return self }
  public var outputs: BackerDashboardProjectsViewModelOutputs { return self }
}
