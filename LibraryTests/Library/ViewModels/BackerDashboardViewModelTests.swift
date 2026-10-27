@testable import KsApi
@testable import KsApiTestHelpers
@testable import Library
@testable import LibraryTestHelpers
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

@MainActor
internal final class BackerDashboardViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let sessionFeature =
    SessionFeature(makeProvider: { AsyncSessionProvider(service: AppEnvironment.current.apiService) })
  private lazy var feature = ProfileFeature(
    sessionFeature: self.sessionFeature,
    makeProvider: { AsyncProfileProvider(service: AppEnvironment.current.apiService) },
    sleep: { _ in }
  )
  private lazy var vm = BackerDashboardViewModel(profileFeature: self.feature)
  private func advanceRequests() async {
    await self.scheduler.advance()
    await self.vm.headerTask?.value
  }

  override func tearDown() async throws {
    await self.advanceRequests()
    try await super.tearDown()
  }

  private let avatarURL = TestObserver<String, Never>()
  private let backedButtonTitleText = TestObserver<String, Never>()
  private let backerNameText = TestObserver<String, Never>()
  private let configurePagesDataSourceTab = TestObserver<BackerDashboardTab, Never>()
  private let goToMessages = TestObserver<(), Never>()
  private let goToProject = TestObserver<Project, Never>()
  private let goToSettings = TestObserver<(), Never>()
  private let navigateToTab = TestObserver<BackerDashboardTab, Never>()
  private let pinSelectedIndicatorToTab = TestObserver<BackerDashboardTab, Never>()
  private let pinSelectedIndicatorToTabAnimated = TestObserver<Bool, Never>()
  private let postNotification = TestObserver<Notification, Never>()
  private let savedButtonTitleText = TestObserver<String, Never>()
  private let setSelectedButton = TestObserver<BackerDashboardTab, Never>()
  private let updateCurrentUserInEnvironment = TestObserver<User, Never>()

  override func setUp() {
    super.setUp()

    MainActor.assumeIsolated {
      self.vm.outputs.avatarURL.map { $0?.absoluteString ?? "" }.observe(self.avatarURL.observer)
      self.vm.outputs.backedButtonTitleText.observe(self.backedButtonTitleText.observer)
      self.vm.outputs.backerNameText.observe(self.backerNameText.observer)
      self.vm.outputs.configurePagesDataSource.observe(self.configurePagesDataSourceTab.observer)
      self.vm.outputs.goToMessages.observe(self.goToMessages.observer)
      self.vm.outputs.goToSettings.observe(self.goToSettings.observer)
      self.vm.outputs.navigateToTab.observe(self.navigateToTab.observer)
      self.vm.outputs.pinSelectedIndicatorToTab.map(first).observe(self.pinSelectedIndicatorToTab.observer)
      self.vm.outputs.pinSelectedIndicatorToTab.map(second)
        .observe(self.pinSelectedIndicatorToTabAnimated.observer)
      self.vm.outputs.savedButtonTitleText.observe(self.savedButtonTitleText.observer)
      self.vm.outputs.setSelectedButton.observe(self.setSelectedButton.observer)
      self.vm.outputs.updateCurrentUserInEnvironment.observe(self.updateCurrentUserInEnvironment.observer)
      self.vm.outputs.postNotification.observe(self.postNotification.observer)
    }
  }

  func testUserAndHeaderDisplayData() async {
    let location = Location.template
      |> Location.lens.displayableName .~ "Siberia"

    let user = User.template
      |> \.name .~ "Princess Vespa"
      |> \.location .~ location
      |> \.stats.backedProjectsCount .~ 45
      |> \.stats.starredProjectsCount .~ 58
      |> \.avatar.large .~ "http://cats.com/furball.jpg"

    let userEnvelope = UserEnvelope(me: user)

    await withEnvironment(apiService: MockService(
      fetchGraphUserSelfResult: .success(userEnvelope),
      fetchUserSelfResponse: user
    )) {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: user))

      self.avatarURL.assertValueCount(0)
      self.backedButtonTitleText.assertValueCount(0)
      self.backerNameText.assertValueCount(0)
      self.pinSelectedIndicatorToTab.assertValueCount(0)
      self.pinSelectedIndicatorToTabAnimated.assertValueCount(0)
      self.savedButtonTitleText.assertValueCount(0)
      self.setSelectedButton.assertValueCount(0)
      self.postNotification.assertValueCount(0)
      self.updateCurrentUserInEnvironment.assertValueCount(0)

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear(false)

      await self.advanceRequests()

      // Signals emit twice as they are prefixed with the current user data.
      self.avatarURL.assertValues(["http://cats.com/furball.jpg", "http://cats.com/furball.jpg"])
      self.backedButtonTitleText.assertValues(["45\nbacked", "45\nbacked"])
      self.backerNameText.assertValues(["Princess Vespa", "Princess Vespa"])
      self.savedButtonTitleText.assertValues(["58\nsaved"])
      self.setSelectedButton.assertValues([.backed])
      self.postNotification.assertValueCount(0)
      self.updateCurrentUserInEnvironment.assertValues([user])

      self.vm.inputs.currentUserUpdatedInEnvironment()

      self.postNotification.assertValueCount(1)

      // Signals that emit just once because they rely on the datasource tab index to exist first.
      self.pinSelectedIndicatorToTab.assertValues([.backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false])
    }
  }

  func testConfigurePagesData() async {
    self.configurePagesDataSourceTab.assertValueCount(0)

    self.vm.inputs.viewDidLoad()

    self.configurePagesDataSourceTab.assertValues([.backed])
  }

  func testTabNavigation() async {
    let userEnvelope = UserEnvelope(me: User.template)

    await withEnvironment(apiService: MockService(
      fetchGraphUserSelfResult: .success(userEnvelope)
    )) {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: .template))

      self.vm.inputs.viewDidLoad()
      self.vm.inputs.viewWillAppear(false)

      self.setSelectedButton.assertValueCount(0)
      self.pinSelectedIndicatorToTab.assertValueCount(0)
      self.pinSelectedIndicatorToTabAnimated.assertValueCount(0)
      XCTAssertEqual(.backed, self.vm.outputs.currentSelectedTab)

      await self.advanceRequests()

      self.navigateToTab.assertValueCount(0)
      self.setSelectedButton.assertValues([.backed])
      self.pinSelectedIndicatorToTab.assertValues([.backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false])
      XCTAssertEqual(.backed, self.vm.outputs.currentSelectedTab)

      self.vm.inputs.savedProjectsButtonTapped()

      self.navigateToTab.assertValues([.saved])
      self.setSelectedButton.assertValues([.backed, .saved])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true])
      XCTAssertEqual(.saved, self.vm.outputs.currentSelectedTab)

      XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
      XCTAssertEqual("watched", self.segmentTrackingClient.properties.last?["context_type"] as? String)
      XCTAssertEqual(
        "account_menu",
        self.segmentTrackingClient.properties.last?["context_location"] as? String
      )

      self.vm.inputs.backedProjectsButtonTapped()

      self.navigateToTab.assertValues([.saved, .backed])
      self.setSelectedButton.assertValues([.backed, .saved, .backed])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true, true])
      XCTAssertEqual(.backed, self.vm.outputs.currentSelectedTab)

      // Swiping.
      self.vm.inputs.willTransition(toPage: 1)
      self.vm.inputs.pageTransition(completed: false)

      self.navigateToTab.assertValues([.saved, .backed], "Tab switch does not complete.")
      self.setSelectedButton.assertValues([.backed, .saved, .backed], "Selection does not emit.")
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed], "Selection does not emit.")
      XCTAssertEqual(.backed, self.vm.outputs.currentSelectedTab)

      self.vm.inputs.willTransition(toPage: 1)
      self.vm.inputs.pageTransition(completed: true)

      self.navigateToTab.assertValues([.saved, .backed, .saved])
      self.setSelectedButton.assertValues([.backed, .saved, .backed, .saved])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed, .saved])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true, true, true])
      XCTAssertEqual(.saved, self.vm.outputs.currentSelectedTab)

      XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
      XCTAssertEqual("watched", self.segmentTrackingClient.properties.last?["context_type"] as? String)
      XCTAssertEqual(
        "account_menu",
        self.segmentTrackingClient.properties.last?["context_location"] as? String
      )
    }
  }

  func testGoPlaces() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.viewWillAppear(false)

    self.goToSettings.assertValueCount(0)

    self.vm.inputs.settingsButtonTapped()

    self.goToSettings.assertValueCount(1)
    self.goToMessages.assertValueCount(0)

    self.vm.inputs.messagesButtonTapped()

    self.goToMessages.assertValueCount(1)
  }

  func testHeaderPanning() async {
    self.vm.inputs.viewDidLoad()
    self.vm.inputs.viewWillAppear(false)

    // Panning on the header view.
    self.vm.inputs.beganPanGestureWith(headerTopConstant: -101.0, scrollViewYOffset: 0.0)

    XCTAssertEqual(-101.0, self.vm.outputs.initialTopConstant)

    // Panning on the projects table view.
    self.vm.inputs.beganPanGestureWith(headerTopConstant: -101.0, scrollViewYOffset: 500.0)

    XCTAssertEqual(-500, self.vm.outputs.initialTopConstant)
  }
}
