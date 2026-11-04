@testable import Kickstarter_iOS
import ApolloTestSupport
import GraphAPI
import GraphAPITestMocks
@testable import KsApi


import Prelude
import ReactiveSwift
import XCTest

@MainActor
internal final class BackerDashboardProjectsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let sessionFeature =
    SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) })
  private lazy var feature = ProfileFeature(
    sessionFeature: self.sessionFeature,
    makeProvider: { AsyncProfileProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in }
  )
  private lazy var vm = BackerDashboardProjectsViewModel(profileFeature: self.feature)
  private func advanceRequests() async {
    await self.scheduler.advance()
    await self.vm.pageTask?.value
  }

  override func tearDown() async throws {
    await self.advanceRequests()
    try await super.tearDown()
  }

  private let emptyStateIsVisible = PageRecorder<Bool>()
  private let emptyStateProjectsType = PageRecorder<ProfileProjectsType>()
  private let isRefreshing = PageRecorder<Bool>()
  private let isLoadingNextPage = PageRecorder<Bool>()
  private let goToProject = PageRecorder<ProjectCardProperties>()
  private let goToProjectRefTag = PageRecorder<RefTag>()
  private let projects = PageRecorder<[ProjectCardProperties]>()

  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated {
      self.vm.onEmptyState = { [weak self] visible, type in
        self?.emptyStateIsVisible.values.append(visible)
        self?.emptyStateProjectsType.values.append(type)
      }
      self.vm.onRefreshing = { [weak self] in self?.isRefreshing.values.append($0) }
      self.vm.onLoadingNextPage = { [weak self] in self?.isLoadingNextPage.values.append($0) }
      self.vm.onProject = { [weak self] project, tag in
        self?.goToProject.values.append(project)
        self?.goToProjectRefTag.values.append(tag)
      }
      self.vm.onProjects = { [weak self] in self?.projects.values.append($0) }
    }
  }

  func testProjects() async {
    let response1 = self.dataForMyBackingsFetch(numberOfProjects: 3)
    let response2 = self.dataForMyBackingsFetch(numberOfProjects: 4)
    let response3 = self.dataForMyBackingsFetch(numberOfProjects: 5)

    await withEnvironment(
      apiService: MockService(fetchBackerBackedProjectsResponse: response1),
      currentUser: .template
    ) {
      self.vm.configureWith(projectsType: .backed)
      self.vm.viewDidAppear(false)
      self.vm.currentUserUpdated()

      self.projects.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)
      self.isRefreshing.assertValues([true])
      self.isLoadingNextPage.assertLastValue(false)

      XCTAssertEqual([], self.segmentTrackingClient.events)
      XCTAssertEqual([], self.segmentTrackingClient.properties(forKey: "type", as: String.self))

      await self.advanceRequests()

      XCTAssertEqual(self.projects.lastValue?.count, 3)
      self.emptyStateIsVisible.assertValues([false])
      self.emptyStateProjectsType.assertValues([.backed])
      self.isRefreshing.assertValues([true, false])

      self.vm.viewDidAppear(true)
      self.isRefreshing.assertValues([true, false], "Projects don't refresh.")

      await self.advanceRequests()

      XCTAssertEqual(self.projects.lastValue?.count, 3)
      self.projects.assertValueCount(1, "Projects have only been fetched once")
      self.emptyStateIsVisible.assertValues([false])
      self.isRefreshing.assertValues([true, false], "Projects don't refresh.")

      let updatedUser = User.template |> \.stats.backedProjectsCount .~ 1

      // Come back after backing a project.
      await withEnvironment(
        apiService: MockService(fetchBackerBackedProjectsResponse: response2),
        currentUser: updatedUser
      ) {
        self.vm.currentUserUpdated()
        self.vm.viewDidAppear(false)

        self.isRefreshing.assertValues([true, false, true])
        self.isLoadingNextPage.assertLastValue(false)

        await self.advanceRequests()

        XCTAssertEqual(self.projects.lastValue?.count, 4)
        self.emptyStateIsVisible.assertValues([false, false])
        self.isRefreshing.assertValues([true, false, true, false])
        self.isLoadingNextPage.assertLastValue(false)
      }

      // Refresh.
      await withEnvironment(
        apiService: MockService(fetchBackerBackedProjectsResponse: response3),
        currentUser: updatedUser
      ) {
        self.vm.refresh()

        self.isRefreshing.assertValues([true, false, true, false, true])
        self.isLoadingNextPage.assertLastValue(false)

        await self.advanceRequests()

        XCTAssertEqual(self.projects.lastValue?.count, 5)
        self.emptyStateIsVisible.assertValues([false, false, false])
        self.isRefreshing.assertValues([true, false, true, false, true, false])
        self.isLoadingNextPage.assertLastValue(false)
      }
    }
  }

  func testNoProjects() async {
    let response = self.dataForSavedProjectsFetch(numberOfProjects: 0)

    await withEnvironment(
      apiService: MockService(fetchBackerSavedProjectsResponse: response),
      currentUser: .template
    ) {
      self.vm.configureWith(projectsType: .saved)
      self.vm.viewDidAppear(false)

      self.projects.assertValueCount(0)
      self.emptyStateIsVisible.assertValueCount(0)
      self.isLoadingNextPage.assertValues([false])
      self.isRefreshing.assertValues([true])

      await self.advanceRequests()

      XCTAssert(self.projects.lastValue?.isEmpty == true)
      self.emptyStateIsVisible.assertValues([true], "Empty state is shown for user with no projects.")
      self.emptyStateProjectsType.assertValues([.saved])
      self.isRefreshing.assertValues([true, false])

      XCTAssertEqual([], self.segmentTrackingClient.events)
      XCTAssertEqual([], self.segmentTrackingClient.properties(forKey: "type", as: String.self))

      self.vm.viewDidAppear(true)

      await self.advanceRequests()

      XCTAssert(self.projects.lastValue?.isEmpty == true, "Projects emits empty list")
      self.emptyStateIsVisible.assertValues([true], "Empty state does not emit.")
    }
  }

  func testProjectCellTapped() async {
    let response = self.dataForMyBackingsFetch(numberOfProjects: 3)
    let projectCardFragment = response.projects?.nodes?[0]?.fragments.projectCardFragment
    let projectCardProperties = ProjectCardProperties(projectCardFragment!)!

    await withEnvironment(
      apiService: MockService(fetchBackerBackedProjectsResponse: response),
      currentUser: .template
    ) {
      self.vm.configureWith(projectsType: .backed)
      self.vm.viewDidAppear(false)

      await self.advanceRequests()

      self.vm.projectTapped(projectCardProperties)

      XCTAssertEqual(
        projectCardProperties.projectID,
        self.goToProject.lastValue?.projectID,
        "Project emitted"
      )
      self.goToProjectRefTag.assertValues([.profileBacked], "RefTag = profile_backed emitted.")

      XCTAssertEqual(self.segmentTrackingClient.events, ["CTA Clicked"])

      XCTAssertEqual(
        ["profile"],
        self.segmentTrackingClient.properties(forKey: "context_page", as: String.self)
      )
      XCTAssertEqual(
        ["backed"],
        self.segmentTrackingClient.properties(forKey: "context_section", as: String.self)
      )
      XCTAssertEqual(
        ["account_menu"],
        self.segmentTrackingClient.properties(forKey: "context_location", as: String.self)
      )
    }
  }

  func testRefresh() async {
    let response = self.dataForMyBackingsFetch(numberOfProjects: 3)
    let user = User.template

    await withEnvironment(
      apiService: MockService(fetchBackerBackedProjectsResponse: response),
      currentUser: user
    ) {
      self.vm.configureWith(projectsType: .backed)
      self.vm.viewDidAppear(false)
      self.vm.currentUserUpdated()

      self.isRefreshing.assertLastValue(true)
      self.isLoadingNextPage.assertLastValue(false)

      // Load all projects to end refreshing.
      await self.advanceRequests()
      self.isRefreshing.assertLastValue(false)
      self.isLoadingNextPage.assertLastValue(false)

      // Test that updating the saved projects count doesn't trigger re-fetching backed projects.
      let userSavedCountChanged = user |> \.stats.starredProjectsCount .~ 3
      await withEnvironment(
        apiService: MockService(fetchBackerBackedProjectsResponse: response),
        currentUser: userSavedCountChanged
      ) {
        self.vm.viewDidAppear(true)
        self.isRefreshing.assertLastValue(false)
        self.isLoadingNextPage.assertLastValue(false)
      }

      // Test that updating the backed projects count triggers re-fetching backed projects.
      let userBackedCountChanged = userSavedCountChanged |> \.stats.backedProjectsCount .~ 1
      await withEnvironment(
        apiService: MockService(fetchBackerBackedProjectsResponse: response),
        currentUser: userBackedCountChanged
      ) {
        self.vm.viewDidAppear(true)
        self.isRefreshing.assertLastValue(true)
        self.isLoadingNextPage.assertLastValue(false)

        await self.advanceRequests()
        self.isRefreshing.assertLastValue(false)
        self.isLoadingNextPage.assertLastValue(false)
      }
    }
  }

  func testLoadNextPage() async {
    let response = self.dataForMyBackingsFetch(numberOfProjects: 3)

    let user = User.template

    await withEnvironment(
      apiService: MockService(fetchBackerBackedProjectsResponse: response),
      currentUser: user
    ) {
      self.vm.configureWith(projectsType: .backed)
      self.vm.viewDidAppear(false)
      self.vm.currentUserUpdated()

      self.isRefreshing.assertLastValue(true)
      self.isLoadingNextPage.assertLastValue(false)

      // Finish loading.
      await self.advanceRequests()
      self.isRefreshing.assertLastValue(false)
      self.isLoadingNextPage.assertLastValue(false)

      // Trigger next page fetch.
      self.vm.willDisplayRow(10, outOf: 10)

      self.isRefreshing.assertLastValue(false)
      self.isLoadingNextPage.assertLastValue(true)

      // Finish loading.
      await self.advanceRequests()
      self.isRefreshing.assertLastValue(false)
      self.isLoadingNextPage.assertLastValue(false)
    }
  }

  // - MARK: Helpers

  func dataForMyBackingsFetch(numberOfProjects: Int) -> GraphAPI.FetchMyBackedProjectsQuery.Data {
    let mock = GraphAPI.ProjectCardFragment.mockProjectsConnectionQuery(numberOfProjects: numberOfProjects)
    return GraphAPI.FetchMyBackedProjectsQuery.Data.from(mock)
  }

  func dataForSavedProjectsFetch(numberOfProjects: Int) -> GraphAPI.FetchMySavedProjectsQuery.Data {
    let mock = GraphAPI.ProjectCardFragment.mockProjectsConnectionQuery(numberOfProjects: numberOfProjects)
    return GraphAPI.FetchMySavedProjectsQuery.Data.from(mock)
  }
}

private final class PageRecorder<Value> {
  var values: [Value] = []
  var lastValue: Value? { self.values.last }

  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}

private extension PageRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }

  func assertLastValue(_ expected: Value, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.lastValue, expected, message, file: file, line: line)
  }
}
