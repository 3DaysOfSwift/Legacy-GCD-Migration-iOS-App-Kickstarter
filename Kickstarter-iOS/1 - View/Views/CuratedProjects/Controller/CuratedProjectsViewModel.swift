import Foundation
import KsApi
import Prelude
import ReactiveSwift

public typealias ProjectData = (project: Project, projects: [Project], refTag: RefTag)

@MainActor
public protocol CuratedProjectsViewModelInputs {
  func configure(with categories: [KsApi.Category])
  func doneButtonTapped()
  func projectTapped(_ project: Project?)
  func viewDidLoad()
}

@MainActor
public protocol CuratedProjectsViewModelOutputs {
  var dismissViewController: Signal<Void, Never> { get }
  var goToProject: Signal<ProjectData, Never> { get }
  var isLoading: Signal<Bool, Never> { get }
  var loadProjects: Signal<[Project], Never> { get }
  var showErrorMessage: Signal<String, Never> { get }
}

@MainActor
public protocol CuratedProjectsViewModelType {
  var inputs: CuratedProjectsViewModelInputs { get }
  var outputs: CuratedProjectsViewModelOutputs { get }
}

@MainActor
public final class CuratedProjectsViewModel: CuratedProjectsViewModelType, CuratedProjectsViewModelInputs,
  CuratedProjectsViewModelOutputs {
  private let feature: RecommendationsFeature
  private let route = UUID()
  public init(recommendationsFeature: RecommendationsFeature? = nil) {
    let feature = recommendationsFeature ?? AppModel.shared.recommendationsFeature
    self.feature = feature
    let route = self.route
    let curatedProjects = feature.selections.filter { $0.0 == route }.map { $0.1.projects }
    self.categoriesSignal.combineLatest(with: self.viewDidLoadSignal)
      .map(first)
      .observeValues { feature.request(.curated($0), route: route) }

    self.loadProjects = curatedProjects

    self.showErrorMessage = curatedProjects
      .filter { $0.isEmpty }
      .ignoreValues()
      .map { _ in Strings.general_error_something_wrong() }

    self.dismissViewController = self.doneButtonTappedSignal

    self.isLoading = Signal.merge(
      self.viewDidLoadSignal.mapConst(true),
      curatedProjects.mapConst(false)
    )

    self.goToProject = curatedProjects
      .takePairWhen(self.projectTappedSignal.skipNil())
      .map { projects, project in (project, projects, RefTag.onboarding) }
  }

  deinit {
    let feature = self.feature
    let route = self.route
    Task { @MainActor in feature.release(route: route) }
  }

  private let (categoriesSignal, categoriesObserver) = Signal<[KsApi.Category], Never>.pipe()
  public func configure(with categories: [KsApi.Category]) {
    self.categoriesObserver.send(value: categories)
  }

  private let (doneButtonTappedSignal, doneButtonTappedObserver) = Signal<Void, Never>.pipe()
  public func doneButtonTapped() {
    self.feature.release(route: self.route)
    self.doneButtonTappedObserver.send(value: ())
  }

  private let (projectTappedSignal, projectTappedObserver) = Signal<Project?, Never>.pipe()
  public func projectTapped(_ project: Project?) {
    self.projectTappedObserver.send(value: project)
  }

  private let (viewDidLoadSignal, viewDidLoadObserver) = Signal<Void, Never>.pipe()
  public func viewDidLoad() {
    self.viewDidLoadObserver.send(value: ())
  }

  public let dismissViewController: Signal<Void, Never>
  public let goToProject: Signal<ProjectData, Never>
  public let isLoading: Signal<Bool, Never>
  public let loadProjects: Signal<[Project], Never>
  public let showErrorMessage: Signal<String, Never>

  public var inputs: CuratedProjectsViewModelInputs { return self }
  public var outputs: CuratedProjectsViewModelOutputs { return self }
}
