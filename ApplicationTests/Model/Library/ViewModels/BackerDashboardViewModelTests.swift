@testable import Kickstarter_iOS
@testable import KsApi


import Prelude
import ReactiveSwift // The legacy test environment owns the scheduler.
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

  private let avatarURL = HeaderRecorder<String>()
  private let backedButtonTitleText = HeaderRecorder<String>()
  private let backerNameText = HeaderRecorder<String>()
  private let configurePagesDataSourceTab = HeaderRecorder<BackerDashboardTab>()
  private let goToMessages = HeaderRecorder<()>()
  private let goToProject = HeaderRecorder<Project>()
  private let goToSettings = HeaderRecorder<()>()
  private let navigateToTab = HeaderRecorder<BackerDashboardTab>()
  private let pinSelectedIndicatorToTab = HeaderRecorder<BackerDashboardTab>()
  private let pinSelectedIndicatorToTabAnimated = HeaderRecorder<Bool>()
  private let postNotification = HeaderRecorder<Notification>()
  private let savedButtonTitleText = HeaderRecorder<String>()
  private let setSelectedButton = HeaderRecorder<BackerDashboardTab>()
  private let updateCurrentUserInEnvironment = HeaderRecorder<User>()

  override func setUp() async throws {
    try await super.setUp()

    MainActor.assumeIsolated {
      self.vm.onAvatarURL = { [weak self] in self?.avatarURL.values.append($0?.absoluteString ?? "") }
      self.vm.onBackedTitle = { [weak self] in self?.backedButtonTitleText.values.append($0) }
      self.vm.onName = { [weak self] in self?.backerNameText.values.append($0) }
      self.vm.onConfigurePages = { [weak self] in self?.configurePagesDataSourceTab.values.append($0) }
      self.vm.onMessages = { [weak self] in self?.goToMessages.values.append(()) }
      self.vm.onSettings = { [weak self] in self?.goToSettings.values.append(()) }
      self.vm.onNavigate = { [weak self] in self?.navigateToTab.values.append($0) }
      self.vm.onPinIndicator = { [weak self] tab, animated in
        self?.pinSelectedIndicatorToTab.values.append(tab)
        self?.pinSelectedIndicatorToTabAnimated.values.append(animated)
      }
      self.vm.onSavedTitle = { [weak self] in self?.savedButtonTitleText.values.append($0) }
      self.vm.onSelectedButton = { [weak self] in self?.setSelectedButton.values.append($0) }
      self.vm.onCurrentUserUpdated = { [weak self] in self?.updateCurrentUserInEnvironment.values.append($0) }
      self.vm.onNotification = { [weak self] in self?.postNotification.values.append($0) }
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

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(false)

      await self.advanceRequests()

      // Signals emit twice as they are prefixed with the current user data.
      self.avatarURL.assertValues(["http://cats.com/furball.jpg", "http://cats.com/furball.jpg"])
      self.backedButtonTitleText.assertValues(["45\nbacked", "45\nbacked"])
      self.backerNameText.assertValues(["Princess Vespa", "Princess Vespa"])
      self.savedButtonTitleText.assertValues(["58\nsaved"])
      self.setSelectedButton.assertValues([.backed])
      self.postNotification.assertValueCount(0)
      self.updateCurrentUserInEnvironment.assertValues([user])

      self.vm.currentUserUpdatedInEnvironment()

      self.postNotification.assertValueCount(1)

      // Signals that emit just once because they rely on the datasource tab index to exist first.
      self.pinSelectedIndicatorToTab.assertValues([.backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false])
    }
  }

  func testConfigurePagesData() async {
    self.configurePagesDataSourceTab.assertValueCount(0)

    self.vm.viewDidLoad()

    self.configurePagesDataSourceTab.assertValues([.backed])
  }

  func testTabNavigation() async {
    let userEnvelope = UserEnvelope(me: User.template)

    await withEnvironment(apiService: MockService(
      fetchGraphUserSelfResult: .success(userEnvelope)
    )) {
      AppEnvironment.login(AccessTokenEnvelope(accessToken: "deadbeef", user: .template))

      self.vm.viewDidLoad()
      self.vm.viewWillAppear(false)

      self.setSelectedButton.assertValueCount(0)
      self.pinSelectedIndicatorToTab.assertValueCount(0)
      self.pinSelectedIndicatorToTabAnimated.assertValueCount(0)
      XCTAssertEqual(.backed, self.vm.currentSelectedTab)

      await self.advanceRequests()

      self.navigateToTab.assertValueCount(0)
      self.setSelectedButton.assertValues([.backed])
      self.pinSelectedIndicatorToTab.assertValues([.backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false])
      XCTAssertEqual(.backed, self.vm.currentSelectedTab)

      self.vm.savedProjectsButtonTapped()

      self.navigateToTab.assertValues([.saved])
      self.setSelectedButton.assertValues([.backed, .saved])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true])
      XCTAssertEqual(.saved, self.vm.currentSelectedTab)

      XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
      XCTAssertEqual("watched", self.segmentTrackingClient.properties.last?["context_type"] as? String)
      XCTAssertEqual(
        "account_menu",
        self.segmentTrackingClient.properties.last?["context_location"] as? String
      )

      self.vm.backedProjectsButtonTapped()

      self.navigateToTab.assertValues([.saved, .backed])
      self.setSelectedButton.assertValues([.backed, .saved, .backed])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true, true])
      XCTAssertEqual(.backed, self.vm.currentSelectedTab)

      // Swiping.
      self.vm.willTransition(toPage: 1)
      self.vm.pageTransition(completed: false)

      self.navigateToTab.assertValues([.saved, .backed], "Tab switch does not complete.")
      self.setSelectedButton.assertValues([.backed, .saved, .backed], "Selection does not emit.")
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed], "Selection does not emit.")
      XCTAssertEqual(.backed, self.vm.currentSelectedTab)

      self.vm.willTransition(toPage: 1)
      self.vm.pageTransition(completed: true)

      self.navigateToTab.assertValues([.saved, .backed, .saved])
      self.setSelectedButton.assertValues([.backed, .saved, .backed, .saved])
      self.pinSelectedIndicatorToTab.assertValues([.backed, .saved, .backed, .saved])
      self.pinSelectedIndicatorToTabAnimated.assertValues([false, true, true, true])
      XCTAssertEqual(.saved, self.vm.currentSelectedTab)

      XCTAssertEqual("discover", self.segmentTrackingClient.properties.last?["context_page"] as? String)
      XCTAssertEqual("watched", self.segmentTrackingClient.properties.last?["context_type"] as? String)
      XCTAssertEqual(
        "account_menu",
        self.segmentTrackingClient.properties.last?["context_location"] as? String
      )
    }
  }

  func testGoPlaces() async {
    self.vm.viewDidLoad()
    self.vm.viewWillAppear(false)

    self.goToSettings.assertValueCount(0)

    self.vm.settingsButtonTapped()

    self.goToSettings.assertValueCount(1)
    self.goToMessages.assertValueCount(0)

    self.vm.messagesButtonTapped()

    self.goToMessages.assertValueCount(1)
  }

  func testHeaderPanning() async {
    self.vm.viewDidLoad()
    self.vm.viewWillAppear(false)

    // Panning on the header view.
    self.vm.beganPanGestureWith(headerTopConstant: -101.0, scrollViewYOffset: 0.0)

    XCTAssertEqual(-101.0, self.vm.initialTopConstant)

    // Panning on the projects table view.
    self.vm.beganPanGestureWith(headerTopConstant: -101.0, scrollViewYOffset: 500.0)

    XCTAssertEqual(-500, self.vm.initialTopConstant)
  }
}

private final class HeaderRecorder<Value> {
  var values: [Value] = []
  func assertValueCount(_ count: Int, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values.count, count, message, file: file, line: line)
  }
}

private extension HeaderRecorder where Value: Equatable {
  func assertValues(_ expected: [Value], _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(self.values, expected, message, file: file, line: line)
  }
}
