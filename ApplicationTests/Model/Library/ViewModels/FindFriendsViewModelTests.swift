@testable import Kickstarter_iOS
@testable import KsApi
import Prelude
import XCTest

@MainActor
final class FindFriendsViewModelTests: TestCase {
  override var requiresSnapshotReferenceSimulator: Bool { false }
  private let feature = FriendsFeature(
    sessionFeature: SessionFeature(makeProvider: { AsyncSessionProvider(service: MockService()) }),
    makeProvider: { AsyncFriendsProvider(service: AppEnvironment.current.apiService) }, sleep: { _ in }
  )
  private lazy var vm = FindFriendsViewModel(feature: self.feature, refreshDelay: {})

  override func tearDown() async throws {
    self.feature.reset()
    await self.feature.waitForOperations()
    try await super.tearDown()
  }

  func testConnectedUserLoadsFriendsAndStats() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ true) {
      self.vm.configureWith(source: .settings)
      self.vm.viewDidLoad()
      XCTAssertEqual(self.vm.showFacebookConnect, false)
      XCTAssertTrue(self.vm.showLoadingIndicator)
      await self.vm.waitForObservations()
      XCTAssertNotNil(self.vm.friends)
      XCTAssertNotNil(self.vm.stats)
      XCTAssertFalse(self.vm.showLoadingIndicator)
    }
  }

  func testDisconnectedUserSeesFacebookPromptWithoutLoading() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ false) {
      self.vm.configureWith(source: .settings)
      self.vm.viewDidLoad()
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.showFacebookConnect, true)
      XCTAssertNil(self.vm.friends)
      XCTAssertNil(self.vm.stats)
      XCTAssertFalse(self.vm.showLoadingIndicator)
    }
  }

  func testFollowAllRefreshesList() async {
    let response = FindFriendsEnvelope.template
    await withEnvironment(apiService: MockService(fetchFriendsResponse: response), currentUser: User.template |> \.facebookConnected .~ true) {
      self.vm.configureWith(source: .settings)
      self.vm.viewDidLoad()
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.friends, response.users)
      self.vm.confirmFollowAllFriends()
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.friends, response.users)
    }
  }

  func testEventsRemainRepeatable() {
    var counts: [Int] = []
    self.vm.onEvent = { event in
      if case let .followAllConfirmation(count) = event { counts.append(count) }
    }
    self.vm.findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: 1_000)
    self.vm.findFriendsStatsCellShowFollowAllFriendsAlert(friendCount: 1_000)
    XCTAssertEqual(counts, [1_000, 1_000])
  }
  func testConnectedUserNeedingReconnectShowsPrompt() async {
    let user = User.template |> \.facebookConnected .~ true |> \.needsFreshFacebookToken .~ true
    await withEnvironment(currentUser: user) {
      self.vm.configureWith(source: .findFriends)
      self.vm.viewDidLoad()
      await self.vm.waitForObservations()
      XCTAssertEqual(self.vm.showFacebookConnect, true)
      XCTAssertNil(self.vm.friends)
      XCTAssertNil(self.vm.stats)
    }
  }

  func testConnectingFacebookStartsLoading() async {
    await withEnvironment(currentUser: User.template |> \.facebookConnected .~ false) {
      self.vm.configureWith(source: .discovery)
      self.vm.viewDidLoad()
      XCTAssertEqual(self.vm.showFacebookConnect, true)
      AppEnvironment.updateCurrentUser(User.template |> \.facebookConnected .~ true)
      self.vm.findFriendsFacebookConnectCellDidFacebookConnectUser()
      XCTAssertEqual(self.vm.showFacebookConnect, false)
      await self.vm.waitForObservations()
      XCTAssertNotNil(self.vm.friends)
      XCTAssertNotNil(self.vm.stats)
      XCTAssertFalse(self.vm.showLoadingIndicator)
    }
  }

  func testSourceAndRepeatedErrorEvents() {
    self.vm.configureWith(source: .discovery)
    XCTAssertEqual(self.vm.source, .discovery)
    var errors: [AlertError] = []
    self.vm.onEvent = { if case let .error(error) = $0 { errors.append(error) } }
    self.vm.findFriendsFacebookConnectCellShowErrorAlert(.facebookTokenFail)
    self.vm.findFriendsFacebookConnectCellShowErrorAlert(.facebookTokenFail)
    XCTAssertEqual(errors.count, 2)
  }

  func testDiscoveryEvent() {
    var received: DiscoveryParams?
    self.vm.onEvent = { if case let .discovery(params) = $0 { received = params } }
    self.vm.discoverButtonTapped()
    let expected = DiscoveryParams.defaults |> DiscoveryParams.lens.social .~ true |> DiscoveryParams.lens.sort .~ .magic
    XCTAssertEqual(received, expected)
  }

}
