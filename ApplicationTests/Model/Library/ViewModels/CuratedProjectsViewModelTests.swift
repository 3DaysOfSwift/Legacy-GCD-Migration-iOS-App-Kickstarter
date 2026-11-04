@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import XCTest

@MainActor
final class CuratedProjectsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let dismissViewController = CuratedRecorder<Void>()
  private let goToProjectProject = CuratedRecorder<Project>()
  private let goToProjectProjects = CuratedRecorder<[Project]>()
  private let goToProjectRefTag = CuratedRecorder<RefTag>()
  private let isLoading = CuratedRecorder<Bool>()
  private let loadProjectsCount = CuratedRecorder<Int>()
  private let showErrorMessage = CuratedRecorder<String>()
  private let feature = RecommendationsFeature(settingsFeature: SettingsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) }),
    makeProvider: { AsyncAccountPreferencesProvider(service: AppEnvironment.current.apiService) }
  ), makeProvider: { AsyncRecommendationsProvider(service: AppEnvironment.current.apiService) })
  private lazy var viewModel: CuratedProjectsViewModel = CuratedProjectsViewModel(recommendationsFeature: self.feature)

  override func setUp() async throws {
    try await super.setUp()
    MainActor.assumeIsolated { self.bindOutputs() }
  }

  private func bindOutputs() {
    self.viewModel.onDismiss = { [weak self] in self?.dismissViewController.record(()) }
    self.viewModel.onLoading = { [weak self] in self?.isLoading.record($0) }
    self.viewModel.onProjects = { [weak self] in self?.loadProjectsCount.record($0.count) }
    self.viewModel.onProject = { [weak self] value in
      self?.goToProjectProject.record(value.project)
      self?.goToProjectProjects.record(value.projects)
      self?.goToProjectRefTag.record(value.refTag)
    }
    self.viewModel.onError = { [weak self] in self?.showErrorMessage.record($0) }
  }

  func testDismissViewController_OnButtonTap() async {
    self.dismissViewController.assertDidNotEmitValue()

    self.viewModel.doneButtonTapped()

    self.dismissViewController.assertValueCount(1)
  }

  func testLoadProjects() async {
    let projects = (1...5).map {
      .template
        |> Project.lens.id .~ $0
        |> Project.lens.category .~ Project.Category.art
    }

    let envelope = .template
      |> DiscoveryEnvelope.lens.projects .~ projects

    let apiService = MockService(fetchDiscoveryResponse: envelope)
    await withEnvironment(apiService: apiService) {
      self.viewModel.configure(with: [Category.art, Category.tabletopGames])

      self.viewModel.viewDidLoad()

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      // We configured the viewModel with 2 categories,
      // therefore, the request was made 2x, returning 10 projects
      self.loadProjectsCount.assertValue(10)
    }
  }

  func testLoadProjects_WhenCategoryListIsEmpty() async {
    let envelope = .template
      |> DiscoveryEnvelope.lens.projects .~ []

    let apiService = MockService(fetchDiscoveryResponse: envelope)
    await withEnvironment(apiService: apiService) {
      self.viewModel.configure(with: [])
      self.viewModel.viewDidLoad()

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      self.loadProjectsCount.assertDidNotEmitValue()
    }
  }

  func testIsLoading() async {
    let category = Project.Category.art
    let projects = (1...5).map {
      .template
        |> Project.lens.id .~ $0
        |> Project.lens.category .~ category
    }
    let envelope = .template
      |> DiscoveryEnvelope.lens.projects .~ projects

    let apiService = MockService(fetchDiscoveryResponse: envelope)

    await withEnvironment(apiService: apiService) {
      self.isLoading.assertDidNotEmitValue()

      self.viewModel.viewDidLoad()

      self.isLoading.assertValues([true])

      self.viewModel.configure(with: [Category.art])

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      self.isLoading.assertValues([true, false])
    }
  }

  func testShowErrorMessage_WhenServerError() async {
    let apiService = MockService(fetchDiscoveryError: .couldNotParseJSON)

    await withEnvironment(apiService: apiService) {
      self.viewModel.configure(with: [Category.art, Category.tabletopGames])

      self.showErrorMessage.assertDidNotEmitValue()

      self.viewModel.viewDidLoad()

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      self.showErrorMessage.assertValue("Something went wrong.", "Should show a generic error message")
    }
  }

  func testShowErrorMessage_WhenNoProjectsReturned() async {
    let emptyEnvelope = .template
      |> DiscoveryEnvelope.lens.projects .~ []

    let apiService = MockService(fetchDiscoveryResponse: emptyEnvelope)

    await withEnvironment(apiService: apiService) {
      self.viewModel.configure(with: [Category.art, Category.tabletopGames])

      self.showErrorMessage.assertDidNotEmitValue()

      self.viewModel.viewDidLoad()

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      self.showErrorMessage.assertValue("Something went wrong.", "Should show a generic error message")
    }
  }

  func testGoToProject() async {
    let discoveryEnvelope = .template
      |> DiscoveryEnvelope.lens.projects .~ [.template]

    let apiService = MockService(fetchDiscoveryResponse: discoveryEnvelope)

    await withEnvironment(apiService: apiService) {
      self.viewModel.configure(with: [.art])
      self.viewModel.viewDidLoad()

      await self.feature.waitForOperations()
      await self.viewModel.waitForPresentation()

      self.goToProjectProject.assertDidNotEmitValue()
      self.goToProjectProjects.assertDidNotEmitValue()
      self.goToProjectRefTag.assertDidNotEmitValue()

      self.viewModel.projectTapped(.template)

      self.goToProjectProject.assertValues([.template])
      self.goToProjectProjects.assertValues([[.template]])
      self.goToProjectRefTag.assertValues([.onboarding])
    }
  }
}

private final class CuratedRecorder<Value> {
  private var values: [Value] = []
  func record(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, file: file, line: line)
  }
  func assertValueCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, file: file, line: line)
  }
  func assertValues(_ values: [Value], file: StaticString = #filePath, line: UInt = #line) where Value: Equatable {
    XCTAssertEqual(self.values, values, file: file, line: line)
  }
  func assertValue(_ value: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) where Value: Equatable {
    XCTAssertEqual(self.values, [value], message, file: file, line: line)
  }
}
