@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import UIKit
import XCTest

@MainActor
internal final class DiscoveryViewModelTests: TestCase {
  // Logic/output assertions only; visual suites retain their reference-device gate.
  override var requiresSnapshotReferenceSimulator: Bool { false }

  fileprivate lazy var vm = DiscoveryViewModel(
    discoveryFeature: DiscoveryFeature(provider: AsyncDiscoveryProvider()),
    deferInitial: { [weak self] action in self?.deferred.append(action) }
  )

  fileprivate let configureDataSource = DiscoveryRecording<[DiscoveryParams.Sort]>()
  fileprivate let configureNavigationHeader = DiscoveryRecording<DiscoveryParams>()
  fileprivate let loadFilterIntoDataSource = DiscoveryRecording<DiscoveryParams>()
  fileprivate let navigateToSort = DiscoveryRecording<DiscoveryParams.Sort>()
  fileprivate let navigateDirection = DiscoveryRecording<UIPageViewController.NavigationDirection>()
  fileprivate let selectSortPage = DiscoveryRecording<DiscoveryParams.Sort>()
  fileprivate let updateSortPagerStyle = DiscoveryRecording<Int?>()

  private var deferred: [@MainActor () -> Void] = []
  private var ordering: [String] = []

  let initialParams = .defaults
    |> DiscoveryParams.lens.includePOTD .~ true

  let categoryParams = .defaults |> DiscoveryParams.lens.category .~ .art
  let subcategoryParams = .defaults |> DiscoveryParams.lens.category .~ .documentary
  let starredParams = .defaults |> DiscoveryParams.lens.starred .~ true

  internal override func setUp() async throws {
    try await super.setUp()
    self.vm.onEvent = { [weak self] event in
      guard let self else { return }
      switch event {
      case let .configurePager(sorts):
        self.configureDataSource.append(sorts)
        self.ordering.append("configureDataSource")
      case let .navigationHeader(params): self.configureNavigationHeader.append(params)
      case let .loadFilter(params):
        self.loadFilterIntoDataSource.append(params)
        self.ordering.append("loadFilterIntoDataSource")
      case let .navigate(sort, direction):
        self.navigateToSort.append(sort)
        self.navigateDirection.append(direction)
      case let .selectSort(sort): self.selectSortPage.append(sort)
      case let .pagerStyle(value): self.updateSortPagerStyle.append(value)
      case .configureSortPager, .sortsEnabled: break
      }
    }
  }

  private func runDeferred() {
    let actions = self.deferred
    self.deferred.removeAll()
    actions.forEach { $0() }
  }

  func testConfigureDataSource() {
    self.configureDataSource.assertValueCount(0, "Data source doesn't configure immediately.")

    self.vm.viewDidLoad()

    self.configureDataSource.assertValueCount(1, "Data source configures after view loads.")
  }

  func testConfigureDataSourceRemoteConfigConfiguration() {
    withEnvironment(remoteConfigClient: MockRemoteConfigClient()) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)
      self.vm.remoteConfigClientConfigured()

      self.configureDataSource.assertValueCount(1)
    }
  }

  func testConfigureDataSource_RemoteConfigConfiguration_Failed() {
    withEnvironment(remoteConfigClient: nil) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.vm.remoteConfigClientConfigurationFailed()

      self.configureDataSource.assertValueCount(1)
    }
  }

  func testLoadFilterIntoDataSource() {
    withEnvironment {
      self.loadFilterIntoDataSource.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)
      self.runDeferred()

      self.loadFilterIntoDataSource.assertValues(
        [self.initialParams],
        "Initial params load into data source immediately."
      )

      self.vm.filter(withParams: self.starredParams)

      self.loadFilterIntoDataSource.assertValues(
        [self.initialParams, self.starredParams],
        "New params load into data source after selecting."
      )
    }
  }

  func testLoadFilterIntoDataSource_RemoteConfigConfiguration() {
    withEnvironment(remoteConfigClient: nil) {
      self.loadFilterIntoDataSource.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.loadFilterIntoDataSource.assertDidNotEmitValue("Waits for Remote Config configuration")

      self.vm.remoteConfigClientConfigured()

      self.runDeferred()

      self.loadFilterIntoDataSource.assertValues([self.initialParams])

      self.vm.filter(withParams: self.starredParams)

      self.loadFilterIntoDataSource.assertValues(
        [self.initialParams, self.starredParams],
        "New params load into data source after selecting."
      )
    }
  }

  func testLoadFilterIntoDataSource_RemoteConfigConfiguration_Failed() {
    withEnvironment(remoteConfigClient: nil) {
      self.loadFilterIntoDataSource.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.loadFilterIntoDataSource.assertDidNotEmitValue("Waits for Remote Config configuration")

      self.vm.remoteConfigClientConfigurationFailed()

      self.runDeferred()

      self.loadFilterIntoDataSource.assertValues([self.initialParams], "Proceeds after 3 seconds")

      self.vm.filter(withParams: self.starredParams)

      self.loadFilterIntoDataSource.assertValues(
        [self.initialParams, self.starredParams],
        "New params load into data source after selecting."
      )
    }
  }

  func testLoadRecommendedProjectsIntoDataSource_UserRecommendationsOptedOut() {
    let user = User.template
      |> \.optedOutOfRecommendations .~ true

    withEnvironment(config: Config.template, currentUser: user) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.runDeferred()

      self.configureNavigationHeader.assertValues([self.initialParams])
    }
  }

  func testLoadRecommendedProjectsIntoDataSource_UserRecommendationsOptedIn() {
    let recsInitialParams = .defaults
      |> DiscoveryParams.lens.includePOTD .~ true
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.backed .~ false

    let user = User.template
      |> \.optedOutOfRecommendations .~ false

    withEnvironment(config: Config.template, currentUser: user) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.runDeferred()

      self.configureNavigationHeader.assertValues([recsInitialParams])
    }
  }

  func testLoadRecommendedProjectsIntoDataSource_AfterChangingSetting() {
    let recsInitialParams = .defaults
      |> DiscoveryParams.lens.includePOTD .~ true
      |> DiscoveryParams.lens.recommended .~ true
      |> DiscoveryParams.lens.backed .~ false

    let user = User.template
      |> \.optedOutOfRecommendations .~ false

    let optedOutUser = User.template
      |> \.optedOutOfRecommendations .~ true

    withEnvironment(config: Config.template, currentUser: user) {
      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.runDeferred()

      self.configureNavigationHeader.assertValues([recsInitialParams])

      withEnvironment(currentUser: optedOutUser) {
        self.vm.didChangeRecommendationsSetting()
        self.vm.viewWillAppear(animated: false)

        self.runDeferred()

        self.configureNavigationHeader.assertValues([recsInitialParams, self.initialParams])
      }
    }
  }

  func testConfigureNavigationHeader() {
    self.configureNavigationHeader.assertValueCount(0)

    self.vm.viewDidLoad()
    self.vm.viewWillAppear(animated: false)

    self.runDeferred()

    self.configureNavigationHeader.assertValues([self.initialParams])
  }

  func testConfigureNavigationHeader_RemoteConfigConfiguration() {
    withEnvironment(remoteConfigClient: nil) {
      self.configureNavigationHeader.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.configureNavigationHeader.assertDidNotEmitValue("Waits for Remote Config configuration")

      self.vm.remoteConfigClientConfigured()

      self.runDeferred()

      self.configureNavigationHeader.assertValues([self.initialParams])

      self.vm.filter(withParams: self.starredParams)

      self.configureNavigationHeader.assertValues(
        [self.initialParams, self.starredParams],
        "New params load into data source after selecting."
      )
    }
  }

  func testConfigureNavigationHeader_RemoteConfigConfiguration_Failed() {
    withEnvironment(remoteConfigClient: nil) {
      self.configureNavigationHeader.assertValueCount(0)

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(animated: false)

      self.configureNavigationHeader.assertDidNotEmitValue("Waits for Remote Config configuration")

      self.vm.remoteConfigClientConfigurationFailed()

      self.runDeferred()

      self.configureNavigationHeader.assertValues([self.initialParams], "Proceeds after 3 seconds")

      self.vm.filter(withParams: self.starredParams)

      self.configureNavigationHeader.assertValues(
        [self.initialParams, self.starredParams],
        "New params load into data source after selecting."
      )
    }
  }

  func testOrdering() {
    self.vm.viewDidLoad()
    self.vm.viewWillAppear(animated: false)

    self.runDeferred()

    XCTAssertEqual(
      self.ordering, ["configureDataSource", "loadFilterIntoDataSource"],
      "The data source should be configured first, and then the filter changed."
    )
  }

  /**
   Tests the ways in which a user can swipe between sorts and select sorts from the page.
   */
  func testNavigatingSorts() {
    self.vm.viewDidLoad()

    self.selectSortPage.assertValues([], "Nothing emits at first.")
    self.navigateToSort.assertValues([], "Nothing emits at first.")
    self.navigateDirection.assertValues([], "Nothing emits at first.")

    self.vm.willTransition(toPage: 1)

    self.selectSortPage.assertValues([], "Nothing emits when a swipe transition starts.")
    self.navigateToSort.assertValues([], "Nothing emits when a swipe transition starts.")
    self.navigateDirection.assertValues([], "Nothing emits when a swipe transition starts.")

    self.vm.pageTransition(completed: false)

    self.selectSortPage.assertValues([], "Nothing emits when a transition doesn't complete.")
    self.navigateToSort.assertValues([], "Nothing emits when a transition doesn't complete.")
    self.navigateDirection.assertValues([], "Nothing emits when a transition doesn't complete.")

    self.vm.willTransition(toPage: 1)

    self.selectSortPage.assertValues([], "Nothing emits when a swipe transition starts.")
    self.navigateToSort.assertValues([], "Nothing emits when a swipe transition starts.")
    self.navigateDirection.assertValues([], "Nothing emits when a swipe transition starts.")

    self.vm.pageTransition(completed: true)

    self.selectSortPage.assertValues([.popular], "Select the popular page in the pager.")
    self.navigateToSort.assertValues([], "Don't navigate to a page.")
    self.navigateDirection.assertValues([], "Don't navigate to a page.")

    self.vm.willTransition(toPage: 2)
    self.vm.pageTransition(completed: true)

    self.selectSortPage.assertValues([.popular, .newest], "Select the newest page in the pager.")
    self.navigateToSort.assertValues([], "Navigate to the newest page.")
    self.navigateDirection.assertValues([], "Navigate forward to the page.")

    self.vm.sortPagerSelected(sort: .magic)

    self.selectSortPage.assertValues([.popular, .newest, .magic], "Select the magic page in the pager.")
    self.navigateToSort.assertValues([.magic], "Navigate to the magic page.")
    self.navigateDirection.assertValues([.reverse], "Navigate backwards to the page.")

    self.vm.sortPagerSelected(sort: .magic)

    self.selectSortPage.assertValues(
      [.popular, .newest, .magic],
      "Selecting the same page again emits nothing new."
    )
    self.navigateToSort.assertValues(
      [.magic],
      "Selecting the same page again emits nothing new."
    )
    self.navigateDirection.assertValues(
      [.reverse],
      "Selecting the same page again emits nothing new."
    )
  }

  /**
   Tests that events are tracked correctly while swiping sorts and selecting sorts from the page.
   */
  func testSortSwipeEventTracking() {
    self.vm.viewDidLoad()
    self.vm.viewWillAppear(animated: true)

    XCTAssertEqual([], self.segmentTrackingClient.events)

    self.vm.willTransition(toPage: 1)

    XCTAssertEqual(
      [],
      self.segmentTrackingClient.events,
      "No events tracked when starting a swipe transition."
    )

    self.vm.pageTransition(completed: false)

    XCTAssertEqual(
      [],
      self.segmentTrackingClient.events,
      "No events tracked when the transition did not complete."
    )

    self.vm.willTransition(toPage: 1)

    XCTAssertEqual(
      [],
      self.segmentTrackingClient.events,
      "Still no events tracked when starting transition."
    )

    self.vm.pageTransition(completed: true)

    XCTAssertEqual(
      ["CTA Clicked"], self.segmentTrackingClient.events,
      "Swipe event tracked once the transition completes."
    )

    XCTAssertEqual(
      ["popular"], self.segmentTrackingClient.properties(forKey: "context_type"),
      "Correct sort is tracked."
    )

    XCTAssertEqual(
      ["magic"], self.segmentTrackingClient.properties(forKey: "discover_sort"),
      "Correct sort is tracked."
    )

    self.vm.sortPagerSelected(sort: .newest)

    XCTAssertEqual(
      ["CTA Clicked", "CTA Clicked"],
      self.segmentTrackingClient.events,
      "Event is tracked when a sort is chosen from the pager."
    )

    XCTAssertEqual(
      ["magic", "popular"],
      self.segmentTrackingClient.properties(forKey: "discover_sort"),
      "Correct sort is tracked."
    )

    XCTAssertEqual(
      ["popular", "newest"],
      self.segmentTrackingClient.properties(forKey: "context_type"),
      "Correct sort is tracked."
    )

    self.vm.sortPagerSelected(sort: .newest)

    XCTAssertEqual(
      ["CTA Clicked", "CTA Clicked"],
      self.segmentTrackingClient.events,
      "Selecting the same sort again does not track another event."
    )

    XCTAssertEqual(
      ["magic", "popular"],
      self.segmentTrackingClient.properties(forKey: "discover_sort")
    )

    XCTAssertEqual(
      ["popular", "newest"],
      self.segmentTrackingClient.properties(forKey: "context_type"),
      "Correct sort is tracked."
    )
  }

  func testUpdateSortPagerStyle() {
    self.vm.viewDidLoad()

    self.updateSortPagerStyle.assertValueCount(0)

    self.vm.filter(withParams: self.categoryParams)

    self.updateSortPagerStyle.assertValues([1], "Emits the category id")

    self.vm.filter(withParams: self.categoryParams)

    self.updateSortPagerStyle.assertValues([1], "Does not emit a repeat value.")

    self.vm.filter(withParams: self.subcategoryParams)

    self.updateSortPagerStyle.assertValues([1, 30], "Emits root category id.")
  }
}

private final class DiscoveryRecording<Value> {
  private(set) var values: [Value] = []
  func append(_ value: Value) { self.values.append(value) }
  func assertDidNotEmitValue(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(self.values.isEmpty, message, file: file, line: line)
  }
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}
private extension DiscoveryRecording where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
